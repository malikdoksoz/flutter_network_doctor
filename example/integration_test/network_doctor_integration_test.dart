import 'package:flutter/foundation.dart';
import 'package:flutter_network_doctor/flutter_network_doctor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('diagnostics complete through the registered platform plugins', (
    WidgetTester tester,
  ) async {
    final doctor = FlutterNetworkDoctor(
      httpClient: MockClient(
        (http.Request request) async =>
            http.Response('', 204, request: request),
      ),
    );
    addTearDown(doctor.dispose);
    final progress = <NetworkDoctorProgress>[];

    final report = await doctor.diagnose(
      config: NetworkDoctorConfig(
        internetEndpoints: <Uri>[
          Uri.https('integration.example', '/network-doctor-smoke'),
        ],
        timeout: const Duration(seconds: 2),
        overallTimeout: const Duration(seconds: 8),
        includeWifiInfo: false,
        includeDnsProbe: false,
        includeTcpProbe: false,
        includeTlsProbe: false,
        includeIpVersionProbes: false,
      ),
      onProgress: progress.add,
    );

    expect(report.probes.map((probe) => probe.name), contains('platform'));
    expect(report.totalDuration, isNotNull);
    expect(report.totalDuration!, lessThan(const Duration(seconds: 12)));
    expect(report.toJson()['schemaVersion'], 1);
    expect(progress.first.stage, NetworkDoctorProgressStage.starting);
    expect(progress.last.stage, NetworkDoctorProgressStage.completed);

    final platformProbe = report.probes.singleWhere(
      (probe) => probe.name == 'platform',
    );
    final supportsNativeSnapshot =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS);

    if (supportsNativeSnapshot) {
      expect(platformProbe.status, ProbeStatus.success);
      expect(report.platform, isNotNull);
    } else {
      expect(platformProbe.status, ProbeStatus.unsupported);
      expect(report.platform, isNull);
    }
  });

  testWidgets('a monitor observes state through the registered plugins', (
    WidgetTester tester,
  ) async {
    final doctor = FlutterNetworkDoctor(
      httpClient: MockClient(
        (http.Request request) async =>
            http.Response('', 204, request: request),
      ),
    );
    addTearDown(doctor.dispose);

    final monitor = doctor.monitor(
      config: NetworkMonitorConfig(
        check: NetworkCheckConfig(
          endpoints: <Uri>[
            Uri.https('integration.example', '/network-doctor-smoke'),
          ],
          timeout: const Duration(seconds: 2),
          overallTimeout: const Duration(seconds: 6),
        ),
        periodicCheckInterval: const Duration(seconds: 1),
        runDeepDiagnosisOnFailure: false,
      ),
    );

    final status = await monitor.start();

    expect(monitor.isRunning, isTrue);
    expect(status, isNotNull);
    expect(status!.hasInternet, isTrue);
    expect(status.health, NetworkHealth.healthy);
    expect(status.toJson()['schemaVersion'], 1);
    expect(monitor.currentStatus, isNotNull);

    // The connectivity stream must survive a stop/start cycle on every
    // platform, including desktop and web.
    await monitor.stop();
    expect(monitor.isRunning, isFalse);
    expect(await monitor.start(), isNotNull);

    await monitor.dispose();
    expect(monitor.isRunning, isFalse);

    // The borrowed doctor stays usable after the monitor is disposed.
    final afterDispose = await doctor.check(
      config: NetworkCheckConfig(
        endpoints: <Uri>[
          Uri.https('integration.example', '/network-doctor-smoke'),
        ],
        timeout: const Duration(seconds: 2),
      ),
    );
    expect(afterDispose.hasInternet, isTrue);
  });
}
