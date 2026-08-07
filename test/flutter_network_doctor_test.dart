import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_network_doctor/flutter_network_doctor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'successful HTTP reachability takes precedence over transport state',
    () async {
      final doctor = FlutterNetworkDoctor(
        httpClient: MockClient((http.Request request) async {
          return http.Response('ok', 204, request: request);
        }),
      );
      addTearDown(doctor.dispose);

      final report = await doctor.diagnose(
        config: NetworkDoctorConfig(
          internetEndpoints: <Uri>[Uri.https('example.com', '/health')],
          includeWifiInfo: false,
          includeDnsProbe: false,
          includeTcpProbe: false,
          includeTlsProbe: false,
          includeIpVersionProbes: false,
          includePlatformInfo: false,
        ),
      );

      expect(report.hasInternet, isTrue);
      expect(report.health, NetworkHealth.healthy);
    },
  );

  test('unexpected redirect suggests a captive portal', () async {
    final doctor = FlutterNetworkDoctor(
      httpClient: MockClient((http.Request request) async {
        return http.Response(
          '',
          302,
          headers: <String, String>{'location': 'http://login.example/'},
          request: request,
        );
      }),
    );
    addTearDown(doctor.dispose);

    final report = await doctor.diagnose(
      config: NetworkDoctorConfig(
        internetEndpoints: <Uri>[Uri.https('example.com', '/health')],
        includeWifiInfo: false,
        includeDnsProbe: false,
        includeTcpProbe: false,
        includeTlsProbe: false,
        includeIpVersionProbes: false,
        includePlatformInfo: false,
      ),
    );

    expect(report.hasInternet, isFalse);
    expect(report.captivePortalSuspected, isTrue);
  });

  test('balanced health ignores a redundant HTTP endpoint failure', () async {
    final doctor = FlutterNetworkDoctor(
      httpClient: MockClient((http.Request request) async {
        return http.Response(
          request.url.host == 'healthy.example' ? 'ok' : 'unavailable',
          request.url.host == 'healthy.example' ? 204 : 503,
          request: request,
        );
      }),
    );
    addTearDown(doctor.dispose);

    final report = await doctor.diagnose(
      config: NetworkDoctorConfig(
        internetEndpoints: <Uri>[
          Uri.https('healthy.example'),
          Uri.https('secondary.example'),
        ],
        includeWifiInfo: false,
        includeDnsProbe: false,
        includeTcpProbe: false,
        includeTlsProbe: false,
        includeIpVersionProbes: false,
        includePlatformInfo: false,
      ),
    );

    expect(report.hasInternet, isTrue);
    expect(report.health, NetworkHealth.healthy);
  });

  test('strict health reports a redundant HTTP failure as degraded', () async {
    final doctor = FlutterNetworkDoctor(
      httpClient: MockClient((http.Request request) async {
        return http.Response(
          '',
          request.url.host == 'healthy.example' ? 204 : 503,
          request: request,
        );
      }),
    );
    addTearDown(doctor.dispose);

    final report = await doctor.diagnose(
      config: NetworkDoctorConfig(
        internetEndpoints: <Uri>[
          Uri.https('healthy.example'),
          Uri.https('secondary.example'),
        ],
        includeWifiInfo: false,
        includeDnsProbe: false,
        includeTcpProbe: false,
        includeTlsProbe: false,
        includeIpVersionProbes: false,
        includePlatformInfo: false,
        healthPolicy: NetworkHealthPolicy.strict,
      ),
    );

    expect(report.health, NetworkHealth.degraded);
  });

  test('an overall deadline stops diagnosis', () async {
    final doctor = FlutterNetworkDoctor(
      httpClient: MockClient((http.Request request) async {
        await Future<void>.delayed(const Duration(seconds: 1));
        return http.Response('ok', 204, request: request);
      }),
    );
    addTearDown(doctor.dispose);

    final diagnosis = doctor.diagnose(
      config: NetworkDoctorConfig(
        internetEndpoints: <Uri>[Uri.https('example.com')],
        timeout: const Duration(seconds: 2),
        overallTimeout: const Duration(milliseconds: 20),
        includeWifiInfo: false,
        includeDnsProbe: false,
        includeTcpProbe: false,
        includeTlsProbe: false,
        includeIpVersionProbes: false,
        includePlatformInfo: false,
      ),
    );

    await expectLater(diagnosis, throwsA(isA<NetworkDoctorTimeoutException>()));
  });

  test('a cancellation token stops diagnosis', () async {
    final doctor = FlutterNetworkDoctor(
      httpClient: MockClient((http.Request request) async {
        await Future<void>.delayed(const Duration(seconds: 1));
        return http.Response('ok', 204, request: request);
      }),
    );
    addTearDown(doctor.dispose);
    final cancellationToken = NetworkDoctorCancellationToken();

    final diagnosis = doctor.diagnose(
      config: NetworkDoctorConfig(
        internetEndpoints: <Uri>[Uri.https('example.com')],
        includeWifiInfo: false,
        includeDnsProbe: false,
        includeTcpProbe: false,
        includeTlsProbe: false,
        includeIpVersionProbes: false,
        includePlatformInfo: false,
      ),
      cancellationToken: cancellationToken,
    );
    cancellationToken.cancel();

    await expectLater(
      diagnosis,
      throwsA(isA<NetworkDoctorCancelledException>()),
    );
  });

  test('diagnosis reports progress through completion', () async {
    final doctor = FlutterNetworkDoctor(
      httpClient: MockClient((http.Request request) async {
        return http.Response('ok', 204, request: request);
      }),
    );
    addTearDown(doctor.dispose);
    final stages = <NetworkDoctorProgressStage>[];

    await doctor.diagnose(
      config: NetworkDoctorConfig(
        internetEndpoints: <Uri>[Uri.https('example.com')],
        includeWifiInfo: false,
        includeDnsProbe: false,
        includeTcpProbe: false,
        includeTlsProbe: false,
        includeIpVersionProbes: false,
        includePlatformInfo: false,
      ),
      onProgress: (NetworkDoctorProgress progress) {
        stages.add(progress.stage);
      },
    );

    expect(stages.first, NetworkDoctorProgressStage.starting);
    expect(stages, contains(NetworkDoctorProgressStage.probing));
    expect(stages.last, NetworkDoctorProgressStage.completed);
  });

  test('native platform snapshot is included in the report', () async {
    if (kIsWeb) {
      return;
    }
    const channel = MethodChannel('flutter_network_doctor/native');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    messenger.setMockMethodCallHandler(channel, (MethodCall call) async {
      expect(call.method, 'getNetworkSnapshot');
      return <String, Object?>{
        'dnsServers': <String>['192.168.1.1'],
        'routes': <String>['0.0.0.0/0'],
        'interfaceName': 'wlan0',
        'mtu': 1500,
        'isMetered': false,
        'isValidated': true,
        'supportsIpv4': true,
        'supportsIpv6': false,
        'supportsDns': true,
        'localNetworkPermission': 'notRequired',
      };
    });
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      messenger.setMockMethodCallHandler(channel, null);
    });
    final doctor = FlutterNetworkDoctor(
      httpClient: MockClient((http.Request request) async {
        return http.Response('ok', 204, request: request);
      }),
    );
    addTearDown(doctor.dispose);

    final report = await doctor.diagnose(
      config: NetworkDoctorConfig(
        internetEndpoints: <Uri>[Uri.https('example.com')],
        includeWifiInfo: false,
        includeDnsProbe: false,
        includeTcpProbe: false,
        includeTlsProbe: false,
        includeIpVersionProbes: false,
      ),
    );

    expect(report.platform?.dnsServers, <String>['192.168.1.1']);
    expect(report.platform?.isValidated, isTrue);
    expect(
      report.platform?.localNetworkPermission,
      LocalNetworkPermissionStatus.notRequired,
    );
  });
}
