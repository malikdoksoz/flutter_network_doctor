import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_network_doctor/flutter_network_doctor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'fake_connectivity.dart';

/// Mutable HTTP behaviour shared by a test and its monitor.
final class FakeEndpoints {
  final Map<String, int> statusCodes = <String, int>{
    'probe.example': 204,
    'second.example': 204,
  };

  int requests = 0;
  int activeRequests = 0;
  int peakConcurrentRequests = 0;
  Duration latency = Duration.zero;

  http.Client client() => MockClient((http.Request request) async {
    requests += 1;
    activeRequests += 1;
    peakConcurrentRequests = activeRequests > peakConcurrentRequests
        ? activeRequests
        : peakConcurrentRequests;
    if (latency > Duration.zero) {
      await Future<void>.delayed(latency);
    }
    activeRequests -= 1;
    return http.Response('', statusCodes[request.url.host] ?? 204);
  });
}

NetworkMonitorConfig monitorConfig({
  List<Uri>? endpoints,
  Duration debounce = const Duration(milliseconds: 5),
  Duration? periodicCheckInterval,
  bool runDeepDiagnosisOnFailure = true,
  NetworkHealthPolicy checkPolicy = NetworkHealthPolicy.balanced,
  NetworkHealthPolicy deepPolicy = NetworkHealthPolicy.balanced,
  bool pauseWhenApplicationIsInBackground = false,
}) {
  final uris = endpoints ?? <Uri>[Uri.https('probe.example')];
  return NetworkMonitorConfig(
    check: NetworkCheckConfig(
      endpoints: uris,
      timeout: const Duration(milliseconds: 400),
      overallTimeout: const Duration(seconds: 5),
      healthPolicy: checkPolicy,
    ),
    deepDiagnosis: NetworkDoctorConfig(
      internetEndpoints: uris,
      timeout: const Duration(milliseconds: 400),
      overallTimeout: const Duration(seconds: 5),
      includeWifiInfo: false,
      includeDnsProbe: false,
      includeTcpProbe: false,
      includeTlsProbe: false,
      includeIpVersionProbes: false,
      includePlatformInfo: false,
      healthPolicy: deepPolicy,
    ),
    debounce: debounce,
    periodicCheckInterval: periodicCheckInterval,
    runDeepDiagnosisOnFailure: runDeepDiagnosisOnFailure,
    pauseWhenApplicationIsInBackground: pauseWhenApplicationIsInBackground,
  );
}

Future<void> sendLifecycleState(AppLifecycleState state) {
  return TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
        'flutter/lifecycle',
        const StringCodec().encodeMessage(state.toString()),
        (ByteData? _) {},
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the first status is a baseline that emits no event', () async {
    installFakeConnectivity(addTearDown);
    final endpoints = FakeEndpoints();
    final monitor = NetworkDoctorMonitor(
      config: monitorConfig(),
      httpClient: endpoints.client(),
    );
    addTearDown(monitor.dispose);

    final events = <NetworkMonitorEvent>[];
    monitor.events.listen(events.add);

    final status = await monitor.start();

    expect(status, isNotNull);
    expect(status!.health, NetworkHealth.healthy);
    expect(monitor.currentStatus, same(status));
    expect(monitor.isRunning, isTrue);
    await pumpEventQueue();
    expect(events, isEmpty);

    final requestsAfterStart = endpoints.requests;
    expect(
      await monitor.start(),
      same(status),
      reason: 'starting twice must not begin a second watch',
    );
    expect(endpoints.requests, requestsAfterStart);
  });

  test('losing and regaining reachability emits both transitions', () async {
    final connectivity = installFakeConnectivity(addTearDown);
    final endpoints = FakeEndpoints();
    final monitor = NetworkDoctorMonitor(
      config: monitorConfig(),
      httpClient: endpoints.client(),
    );
    addTearDown(monitor.dispose);

    await monitor.start();
    expect(monitor.currentStatus!.hasInternet, isTrue);

    final offlineEvent = monitor.events.first;
    endpoints.statusCodes['probe.example'] = 503;
    connectivity.emit(<ConnectivityResult>[ConnectivityResult.none]);
    final offline = await offlineEvent.timeout(const Duration(seconds: 5));

    expect(offline, isA<NetworkBecameOffline>());
    expect(monitor.currentStatus!.health, NetworkHealth.offline);
    expect(
      offline.report,
      isNotNull,
      reason: 'a failing quick check must escalate to a deep diagnosis',
    );
    expect(monitor.latestReport, same(offline.report));

    final onlineEvents = monitor.events.take(2).toList();
    endpoints.statusCodes['probe.example'] = 204;
    connectivity.emit(<ConnectivityResult>[ConnectivityResult.wifi]);
    final recovered = await onlineEvents.timeout(const Duration(seconds: 5));

    expect(recovered.whereType<NetworkBecameOnline>(), hasLength(1));
    expect(recovered.whereType<NetworkTransportChanged>(), hasLength(1));
    expect(monitor.currentStatus!.health, NetworkHealth.healthy);
  });

  test('switching transports while online emits a transport change', () async {
    final connectivity = installFakeConnectivity(addTearDown);
    final endpoints = FakeEndpoints();
    final monitor = NetworkDoctorMonitor(
      config: monitorConfig(),
      httpClient: endpoints.client(),
    );
    addTearDown(monitor.dispose);

    await monitor.start();

    final next = monitor.events.first;
    connectivity.emit(<ConnectivityResult>[ConnectivityResult.mobile]);
    final event = await next.timeout(const Duration(seconds: 5));

    expect(event, isA<NetworkTransportChanged>());
    final change = event as NetworkTransportChanged;
    expect(change.previousTransports, <NetworkTransport>[
      NetworkTransport.wifi,
    ]);
    expect(change.transports, <NetworkTransport>[NetworkTransport.mobile]);
    expect(change.report, isNull, reason: 'a healthy state needs no diagnosis');
  });

  test('degradation carries a report and recovery clears it', () async {
    final connectivity = installFakeConnectivity(addTearDown);
    final endpoints = FakeEndpoints();
    final monitor = NetworkDoctorMonitor(
      config: monitorConfig(
        endpoints: <Uri>[
          Uri.https('probe.example'),
          Uri.https('second.example'),
        ],
        checkPolicy: NetworkHealthPolicy.strict,
        deepPolicy: NetworkHealthPolicy.strict,
      ),
      httpClient: endpoints.client(),
    );
    addTearDown(monitor.dispose);

    await monitor.start();
    expect(monitor.currentStatus!.health, NetworkHealth.healthy);

    final degradedEvent = monitor.events.first;
    endpoints.statusCodes['second.example'] = 503;
    connectivity.emit(<ConnectivityResult>[ConnectivityResult.wifi]);
    final degraded = await degradedEvent.timeout(const Duration(seconds: 5));

    expect(degraded, isA<NetworkDegraded>());
    expect(degraded.status.hasInternet, isTrue);
    expect(degraded.report, isNotNull);

    final recoveredEvent = monitor.events.first;
    endpoints.statusCodes['second.example'] = 204;
    connectivity.emit(<ConnectivityResult>[ConnectivityResult.wifi]);
    final recovered = await recoveredEvent.timeout(const Duration(seconds: 5));

    expect(recovered, isA<NetworkRecovered>());
    expect(monitor.currentStatus!.health, NetworkHealth.healthy);
  });

  test('an unchanged network produces no further emissions', () async {
    final connectivity = installFakeConnectivity(addTearDown);
    final endpoints = FakeEndpoints();
    final monitor = NetworkDoctorMonitor(
      config: monitorConfig(),
      httpClient: endpoints.client(),
    );
    addTearDown(monitor.dispose);

    await monitor.start();
    final emissions = <NetworkStatus>[];
    monitor.status.listen(emissions.add);

    connectivity.emit(<ConnectivityResult>[ConnectivityResult.wifi]);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    connectivity.emit(<ConnectivityResult>[ConnectivityResult.wifi]);
    await Future<void>.delayed(const Duration(milliseconds: 120));

    expect(emissions, isEmpty);
    expect(
      endpoints.requests,
      greaterThan(1),
      reason: 'checks still ran; only the emissions were deduplicated',
    );
  });

  test('a deep diagnosis suppresses a false-positive quick check', () async {
    final connectivity = installFakeConnectivity(addTearDown);
    final endpoints = FakeEndpoints();
    final monitor = NetworkDoctorMonitor(
      // The quick check degrades on any failing endpoint; the deep diagnosis
      // treats redundant endpoint failures as informational.
      config: monitorConfig(
        endpoints: <Uri>[
          Uri.https('probe.example'),
          Uri.https('second.example'),
        ],
        checkPolicy: NetworkHealthPolicy.strict,
      ),
      httpClient: endpoints.client(),
    );
    addTearDown(monitor.dispose);

    await monitor.start();
    final emissions = <NetworkStatus>[];
    monitor.status.listen(emissions.add);

    endpoints.statusCodes['second.example'] = 503;
    connectivity.emit(<ConnectivityResult>[ConnectivityResult.wifi]);
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(emissions, isEmpty);
    expect(
      monitor.latestReport,
      isNotNull,
      reason: 'the deep diagnosis ran even though nothing was emitted',
    );
    expect(monitor.currentStatus!.health, NetworkHealth.healthy);
  });

  test('bursts of connectivity events never probe concurrently', () async {
    final connectivity = installFakeConnectivity(addTearDown);
    final endpoints = FakeEndpoints()
      ..latency = const Duration(milliseconds: 20);
    final monitor = NetworkDoctorMonitor(
      config: monitorConfig(debounce: Duration.zero),
      httpClient: endpoints.client(),
    );
    addTearDown(monitor.dispose);

    await monitor.start();
    for (var i = 0; i < 6; i += 1) {
      connectivity.emit(<ConnectivityResult>[ConnectivityResult.wifi]);
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(endpoints.peakConcurrentRequests, 1);
    expect(
      endpoints.requests,
      lessThan(7),
      reason: 'overlapping triggers must coalesce instead of queueing',
    );
  });

  test('debouncing collapses a burst into a single check', () async {
    final connectivity = installFakeConnectivity(addTearDown);
    final endpoints = FakeEndpoints();
    final monitor = NetworkDoctorMonitor(
      config: monitorConfig(debounce: const Duration(milliseconds: 60)),
      httpClient: endpoints.client(),
    );
    addTearDown(monitor.dispose);

    await monitor.start();
    final afterStart = endpoints.requests;

    for (var i = 0; i < 5; i += 1) {
      connectivity.emit(<ConnectivityResult>[ConnectivityResult.wifi]);
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(endpoints.requests - afterStart, 1);
  });

  test('the periodic timer re-arms after each check', () async {
    installFakeConnectivity(addTearDown);
    final endpoints = FakeEndpoints();
    final monitor = NetworkDoctorMonitor(
      config: monitorConfig(
        periodicCheckInterval: const Duration(milliseconds: 40),
      ),
      httpClient: endpoints.client(),
    );
    addTearDown(monitor.dispose);

    await monitor.start();
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(endpoints.requests, greaterThanOrEqualTo(3));
  });

  test(
    'refresh runs a check immediately without waiting for debounce',
    () async {
      installFakeConnectivity(addTearDown);
      final endpoints = FakeEndpoints();
      final monitor = NetworkDoctorMonitor(
        config: monitorConfig(debounce: const Duration(seconds: 30)),
        httpClient: endpoints.client(),
      );
      addTearDown(monitor.dispose);

      await monitor.start();
      final afterStart = endpoints.requests;

      await monitor.refresh();

      expect(endpoints.requests, afterStart + 1);
    },
  );

  test('a stopped monitor can be started again', () async {
    installFakeConnectivity(addTearDown);
    final endpoints = FakeEndpoints();
    final monitor = NetworkDoctorMonitor(
      config: monitorConfig(),
      httpClient: endpoints.client(),
    );
    addTearDown(monitor.dispose);

    await monitor.start();
    await monitor.stop();
    expect(monitor.isRunning, isFalse);

    final requestsWhileStopped = endpoints.requests;
    await monitor.refresh();
    expect(
      endpoints.requests,
      requestsWhileStopped,
      reason: 'a stopped monitor performs no work',
    );

    final status = await monitor.start();
    expect(monitor.isRunning, isTrue);
    expect(status, isNotNull);
    expect(endpoints.requests, greaterThan(requestsWhileStopped));
  });

  test('disposing during an in-flight cycle closes cleanly', () async {
    installFakeConnectivity(addTearDown);
    final endpoints = FakeEndpoints()
      ..latency = const Duration(milliseconds: 80);
    final monitor = NetworkDoctorMonitor(
      config: monitorConfig(),
      httpClient: endpoints.client(),
    );

    final started = monitor.start();
    await monitor.dispose();
    await started;

    expect(monitor.isRunning, isFalse);
    await expectLater(monitor.status.drain<void>(), completes);
    await expectLater(monitor.events.drain<void>(), completes);
    expect(monitor.start, throwsStateError);
    await monitor.dispose();
  });

  test('backgrounding pauses work and resuming checks immediately', () async {
    installFakeConnectivity(addTearDown);
    final endpoints = FakeEndpoints();
    final monitor = NetworkDoctorMonitor(
      config: monitorConfig(
        periodicCheckInterval: const Duration(milliseconds: 40),
        pauseWhenApplicationIsInBackground: true,
      ),
      httpClient: endpoints.client(),
    );
    addTearDown(() async {
      await sendLifecycleState(AppLifecycleState.resumed);
      await monitor.dispose();
    });

    await monitor.start();
    await sendLifecycleState(AppLifecycleState.paused);
    // Let any cycle that was already running settle before sampling.
    await Future<void>.delayed(const Duration(milliseconds: 60));

    final whilePaused = endpoints.requests;
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(
      endpoints.requests,
      whilePaused,
      reason: 'a backgrounded monitor must perform no work',
    );

    await sendLifecycleState(AppLifecycleState.resumed);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(endpoints.requests, greaterThan(whilePaused));
  });

  test('an attached monitor never disposes the doctor it borrows', () async {
    installFakeConnectivity(addTearDown);
    final endpoints = FakeEndpoints();
    final doctor = FlutterNetworkDoctor(httpClient: endpoints.client());
    addTearDown(doctor.dispose);
    final monitor = doctor.monitor(config: monitorConfig());

    await monitor.start();
    await monitor.dispose();

    final status = await doctor.check(
      config: NetworkCheckConfig(endpoints: <Uri>[Uri.https('probe.example')]),
    );
    expect(status.health, NetworkHealth.healthy);
  });

  test('a monitor keeps working without a connectivity stream', () async {
    final connectivity = installFakeConnectivity(addTearDown);
    await connectivity.close();
    final endpoints = FakeEndpoints();
    final monitor = NetworkDoctorMonitor(
      config: monitorConfig(
        periodicCheckInterval: const Duration(milliseconds: 40),
      ),
      httpClient: endpoints.client(),
    );
    addTearDown(monitor.dispose);

    final status = await monitor.start();

    expect(status, isNotNull);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(endpoints.requests, greaterThanOrEqualTo(2));
  });
}
