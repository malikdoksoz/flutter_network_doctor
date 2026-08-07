import 'package:flutter_network_doctor/flutter_network_doctor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
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
      ),
    );

    expect(report.hasInternet, isFalse);
    expect(report.captivePortalSuspected, isTrue);
  });
}
