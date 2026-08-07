import 'dart:async';

import 'package:flutter_network_doctor/flutter_network_doctor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('HTTP probes start concurrently instead of serially', () async {
    const probeCount = 6;
    final allStarted = Completer<void>();
    var activeRequests = 0;
    var maximumConcurrentRequests = 0;

    final doctor = FlutterNetworkDoctor(
      httpClient: MockClient((http.Request request) async {
        activeRequests += 1;
        maximumConcurrentRequests = activeRequests > maximumConcurrentRequests
            ? activeRequests
            : maximumConcurrentRequests;
        if (activeRequests == probeCount && !allStarted.isCompleted) {
          allStarted.complete();
        }

        await allStarted.future.timeout(const Duration(seconds: 1));
        activeRequests -= 1;
        return http.Response('', 204, request: request);
      }),
    );
    addTearDown(doctor.dispose);

    final report = await doctor.diagnose(
      config: NetworkDoctorConfig(
        internetEndpoints: List<Uri>.generate(
          probeCount,
          (index) => Uri.https('endpoint-$index.example'),
        ),
        timeout: const Duration(seconds: 2),
        overallTimeout: const Duration(seconds: 3),
        includeWifiInfo: false,
        includeDnsProbe: false,
        includeTcpProbe: false,
        includeTlsProbe: false,
        includeIpVersionProbes: false,
        includePlatformInfo: false,
      ),
    );

    expect(maximumConcurrentRequests, probeCount);
    expect(report.probes, hasLength(probeCount));
    expect(report.probes.every((probe) => probe.isSuccess), isTrue);
  });

  test('overall deadline bounds a stalled concurrent probe set', () async {
    final neverCompletes = Completer<http.Response>();
    final doctor = FlutterNetworkDoctor(
      httpClient: MockClient((http.Request request) => neverCompletes.future),
    );
    addTearDown(doctor.dispose);
    final stopwatch = Stopwatch()..start();

    final diagnosis = doctor.diagnose(
      config: NetworkDoctorConfig(
        internetEndpoints: List<Uri>.generate(
          4,
          (index) => Uri.https('stalled-$index.example'),
        ),
        timeout: const Duration(seconds: 2),
        overallTimeout: const Duration(milliseconds: 100),
        includeWifiInfo: false,
        includeDnsProbe: false,
        includeTcpProbe: false,
        includeTlsProbe: false,
        includeIpVersionProbes: false,
        includePlatformInfo: false,
      ),
    );

    await expectLater(diagnosis, throwsA(isA<NetworkDoctorTimeoutException>()));
    stopwatch.stop();
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 1)));
  });
}
