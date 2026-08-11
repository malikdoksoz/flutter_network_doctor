import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:flutter_network_doctor/flutter_network_doctor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'fake_connectivity.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('skips every probe when the device reports no transport', () async {
    final fake = installFakeConnectivity(addTearDown, <ConnectivityResult>[
      ConnectivityResult.none,
    ]);
    var requests = 0;
    final doctor = FlutterNetworkDoctor(
      httpClient: MockClient((http.Request request) async {
        requests += 1;
        return http.Response('', 204);
      }),
    );
    addTearDown(doctor.dispose);

    final status = await doctor.check();

    expect(requests, 0);
    expect(
      fake.checkCount,
      4,
      reason:
          'a no-transport answer must be confirmed before it is trusted, '
          'and every confirming read must have had time to observe a settled '
          'path monitor',
    );
    expect(status.health, NetworkHealth.offline);
    expect(status.hasInternet, isFalse);
    expect(status.probes, isEmpty);
    expect(status.transports, <NetworkTransport>[NetworkTransport.none]);
    expect(status.duration, isNotNull);
  });

  test('probes anyway when the offline shortcut is disabled', () async {
    installFakeConnectivity(addTearDown, <ConnectivityResult>[
      ConnectivityResult.none,
    ]);
    var requests = 0;
    final doctor = FlutterNetworkDoctor(
      httpClient: MockClient((http.Request request) async {
        requests += 1;
        return http.Response('', 204);
      }),
    );
    addTearDown(doctor.dispose);

    final status = await doctor.check(
      config: NetworkCheckConfig(skipProbesWhenOffline: false),
    );

    expect(requests, 1);
    expect(status.hasInternet, isTrue);
  });

  test(
    'an unsettled first connectivity read never counts as offline',
    () async {
      // Apple platforms report `none` from a path monitor that has just been
      // restarted, before its first path update arrives.
      final fake = installFakeConnectivity(
        addTearDown,
      )..scriptedReads.add(const <ConnectivityResult>[ConnectivityResult.none]);
      var requests = 0;
      final doctor = FlutterNetworkDoctor(
        httpClient: MockClient((http.Request request) async {
          requests += 1;
          return http.Response('', 204);
        }),
      );
      addTearDown(doctor.dispose);

      final status = await doctor.check();

      expect(fake.checkCount, 2);
      expect(
        requests,
        1,
        reason: 'the confirmed read reported a live transport',
      );
      expect(status.transports, <NetworkTransport>[NetworkTransport.wifi]);
      expect(status.health, NetworkHealth.healthy);
    },
  );

  test('a path monitor that settles slowly never counts as offline', () async {
    // One confirming read is not always enough: the restarted monitor
    // settles on its own schedule, so reads keep going until it does.
    final fake = installFakeConnectivity(addTearDown)
      ..scriptedReads.addAll(const <List<ConnectivityResult>>[
        <ConnectivityResult>[ConnectivityResult.none],
        <ConnectivityResult>[ConnectivityResult.none],
        <ConnectivityResult>[ConnectivityResult.none],
      ]);
    var requests = 0;
    final doctor = FlutterNetworkDoctor(
      httpClient: MockClient((http.Request request) async {
        requests += 1;
        return http.Response('', 204);
      }),
    );
    addTearDown(doctor.dispose);

    final status = await doctor.check();

    expect(fake.checkCount, 4);
    expect(requests, 1, reason: 'the settled read reported a live transport');
    expect(status.transports, <NetworkTransport>[NetworkTransport.wifi]);
    expect(status.health, NetworkHealth.healthy);
  });

  test('a failed connectivity read never counts as offline', () async {
    final fake = installFakeConnectivity(addTearDown)..failCheck = true;
    var requests = 0;
    final doctor = FlutterNetworkDoctor(
      httpClient: MockClient((http.Request request) async {
        requests += 1;
        return http.Response('', 204);
      }),
    );
    addTearDown(doctor.dispose);

    final status = await doctor.check();

    expect(fake.checkCount, 1);
    expect(requests, 1, reason: 'the none fallback must not skip probes');
    expect(status.hasInternet, isTrue);
    expect(status.health, NetworkHealth.healthy);
  });

  test('reports healthy when a reachability endpoint responds', () async {
    installFakeConnectivity(addTearDown);
    final doctor = FlutterNetworkDoctor(
      httpClient: MockClient((http.Request request) async {
        return http.Response('', 204);
      }),
    );
    addTearDown(doctor.dispose);

    final status = await doctor.check();

    expect(status.health, NetworkHealth.healthy);
    expect(status.hasInternet, isTrue);
    expect(status.transports, <NetworkTransport>[NetworkTransport.wifi]);
    expect(status.probes.single.name, 'http:one.one.one.one');
  });

  test('a strict policy degrades a partially reachable network', () async {
    installFakeConnectivity(addTearDown);
    final doctor = FlutterNetworkDoctor(
      httpClient: MockClient((http.Request request) async {
        return http.Response(
          '',
          request.url.host == 'healthy.example' ? 204 : 503,
        );
      }),
    );
    addTearDown(doctor.dispose);

    final status = await doctor.check(
      config: NetworkCheckConfig(
        endpoints: <Uri>[
          Uri.https('healthy.example'),
          Uri.https('broken.example'),
        ],
        healthPolicy: NetworkHealthPolicy.strict,
      ),
    );

    expect(status.hasInternet, isTrue);
    expect(status.health, NetworkHealth.degraded);
  });

  test('suspects a captive portal on an unexpected redirect', () async {
    installFakeConnectivity(addTearDown);
    final doctor = FlutterNetworkDoctor(
      httpClient: MockClient((http.Request request) async {
        return http.Response(
          '',
          302,
          headers: <String, String>{'location': 'https://portal.example/login'},
        );
      }),
    );
    addTearDown(doctor.dispose);

    final status = await doctor.check();

    expect(status.hasInternet, isFalse);
    expect(status.captivePortalSuspected, isTrue);
    expect(status.health, NetworkHealth.localOnly);
  });

  test('honours a cancellation token', () async {
    installFakeConnectivity(addTearDown);
    final doctor = FlutterNetworkDoctor(
      httpClient: MockClient((http.Request request) async {
        return http.Response('', 204);
      }),
    );
    addTearDown(doctor.dispose);
    final token = NetworkDoctorCancellationToken()..cancel();

    await expectLater(
      doctor.check(cancellationToken: token),
      throwsA(isA<NetworkDoctorCancelledException>()),
    );
  });

  test('rejects an invalid quick-check configuration', () {
    expect(() => NetworkCheckConfig(endpoints: <Uri>[]), throwsArgumentError);
    expect(
      () =>
          NetworkCheckConfig(endpoints: <Uri>[Uri.parse('ftp://example.com')]),
      throwsArgumentError,
    );
    expect(
      () => NetworkCheckConfig(timeout: Duration.zero),
      throwsArgumentError,
    );
    expect(
      () => NetworkCheckConfig(overallTimeout: Duration.zero),
      throwsArgumentError,
    );
    expect(
      () => NetworkCheckConfig(minimumInternetSuccesses: 2),
      throwsArgumentError,
    );
    expect(() => NetworkCheckConfig(dnsHost: '  '), throwsArgumentError);
  });

  test('rejects an invalid monitor configuration', () {
    expect(
      () => NetworkMonitorConfig(debounce: const Duration(seconds: -1)),
      throwsArgumentError,
    );
    expect(
      () => NetworkMonitorConfig(periodicCheckInterval: Duration.zero),
      throwsArgumentError,
    );
    expect(
      NetworkMonitorConfig(periodicCheckInterval: null).periodicCheckInterval,
      isNull,
      reason: 'null must disable periodic checks instead of failing validation',
    );
  });
}
