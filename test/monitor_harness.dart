import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_network_doctor/flutter_network_doctor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

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
