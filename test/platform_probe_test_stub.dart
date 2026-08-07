import 'package:flutter_network_doctor/flutter_network_doctor.dart';
import 'package:flutter_network_doctor/src/probes/platform_probe_stub.dart';
import 'package:flutter_network_doctor/src/run_cancellation.dart';
import 'package:flutter_test/flutter_test.dart';

void registerPlatformProbeTests() {
  test('gateway and quality probes are unsupported without dart:io', () async {
    final cancellation = NetworkDoctorRunCancellation(
      overallTimeout: const Duration(seconds: 5),
    );
    addTearDown(cancellation.finish);
    final probe = PlatformNetworkProbeImpl();

    final gateway = await probe.gateway(
      '192.168.1.1',
      <int>[443],
      const Duration(seconds: 1),
      cancellation,
    );
    final quality = await probe.networkQuality(
      '1.1.1.1',
      443,
      3,
      const Duration(seconds: 1),
      Duration.zero,
      cancellation,
    );

    expect(gateway.probe.status, ProbeStatus.unsupported);
    expect(quality.probe.status, ProbeStatus.unsupported);
  });
}
