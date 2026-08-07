import 'package:flutter/foundation.dart';
import 'package:flutter_network_doctor/flutter_network_doctor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('diagnostics complete through the registered platform plugins', (
    WidgetTester tester,
  ) async {
    final doctor = FlutterNetworkDoctor();
    addTearDown(doctor.dispose);
    final progress = <NetworkDoctorProgress>[];

    final report = await doctor.diagnose(
      config: NetworkDoctorConfig(
        internetEndpoints: <Uri>[
          Uri.parse('http://127.0.0.1:9/network-doctor-smoke'),
        ],
        timeout: const Duration(seconds: 5),
        overallTimeout: const Duration(seconds: 12),
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
}
