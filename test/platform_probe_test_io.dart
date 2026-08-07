import 'dart:io';

import 'package:flutter_network_doctor/flutter_network_doctor.dart';
import 'package:flutter_network_doctor/src/probes/platform_probe_io.dart';
import 'package:flutter_network_doctor/src/run_cancellation.dart';
import 'package:flutter_test/flutter_test.dart';

void registerPlatformProbeTests() {
  test('gateway probe accepts a successful local TCP connection', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final subscription = server.listen((Socket socket) => socket.destroy());
    final cancellation = NetworkDoctorRunCancellation(
      overallTimeout: const Duration(seconds: 5),
    );
    addTearDown(() async {
      await cancellation.finish();
      await subscription.cancel();
      await server.close();
    });

    final outcome = await PlatformNetworkProbeImpl().gateway(
      InternetAddress.loopbackIPv4.address,
      <int>[server.port],
      const Duration(seconds: 1),
      cancellation,
    );

    expect(outcome.probe.status, ProbeStatus.success);
    expect(outcome.result?.reachability, GatewayReachability.reachable);
    expect(outcome.result?.testedPorts, <int>[server.port]);
  });

  test('quality probe collects the configured number of TCP samples', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final subscription = server.listen((Socket socket) => socket.destroy());
    final cancellation = NetworkDoctorRunCancellation(
      overallTimeout: const Duration(seconds: 5),
    );
    addTearDown(() async {
      await cancellation.finish();
      await subscription.cancel();
      await server.close();
    });

    final outcome = await PlatformNetworkProbeImpl().networkQuality(
      InternetAddress.loopbackIPv4.address,
      server.port,
      4,
      const Duration(seconds: 1),
      Duration.zero,
      cancellation,
    );

    expect(outcome.probe.status, ProbeStatus.success);
    expect(outcome.result?.sampleCount, 4);
    expect(outcome.result?.successfulSamples, 4);
    expect(outcome.result?.failedSamples, 0);
    expect(outcome.result?.packetLossPercent, 0);
    expect(outcome.result?.samplesMs, hasLength(4));
  });
}
