import 'package:flutter_network_doctor/flutter_network_doctor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('report serializes to JSON-compatible data', () {
    final report = NetworkDoctorReport(
      generatedAt: DateTime.utc(2026, 8, 7, 9),
      transports: const <NetworkTransport>[NetworkTransport.wifi],
      hasInternet: true,
      health: NetworkHealth.healthy,
      probes: const <NetworkProbeResult>[
        NetworkProbeResult(
          name: 'dns',
          status: ProbeStatus.success,
          duration: Duration(milliseconds: 12),
        ),
      ],
      ipv4Available: true,
      ipv6Available: false,
      wifi: const WifiNetworkInfo(
        ssid: 'Office',
        ipv4: '192.168.1.5',
        gateway: '192.168.1.1',
      ),
    );

    final json = report.toJson();

    expect(json['health'], 'healthy');
    expect(json['schemaVersion'], 1);
    expect(json['hasInternet'], isTrue);
    expect(json['transports'], <String>['wifi']);
    expect((json['wifi']! as Map<String, Object?>)['gateway'], '192.168.1.1');
  });

  test('wifi hasData is false when all fields are absent', () {
    expect(const WifiNetworkInfo().hasData, isFalse);
  });

  test('report can redact Wi-Fi identifiers', () {
    final report = NetworkDoctorReport(
      generatedAt: DateTime.utc(2026, 8, 7, 9),
      transports: const <NetworkTransport>[NetworkTransport.wifi],
      hasInternet: true,
      health: NetworkHealth.healthy,
      probes: const <NetworkProbeResult>[],
      ipv4Available: true,
      ipv6Available: false,
      wifi: const WifiNetworkInfo(
        ssid: 'Private WiFi',
        bssid: '00:11:22:33:44:55',
      ),
    );

    final json = report.toJson(redactWifiIdentifiers: true);
    final wifi = json['wifi']! as Map<String, Object?>;

    expect(wifi['ssid'], '<redacted>');
    expect(wifi['bssid'], '<redacted>');
  });

  test('config rejects impossible internet quorum', () {
    expect(
      () => NetworkDoctorConfig(
        internetEndpoints: <Uri>[Uri.https('example.com')],
        minimumInternetSuccesses: 2,
      ),
      throwsArgumentError,
    );
  });

  test('config rejects non-HTTP endpoints', () {
    expect(
      () => NetworkDoctorConfig(
        internetEndpoints: <Uri>[Uri.parse('ftp://example.com/status')],
      ),
      throwsArgumentError,
    );
  });

  test('config rejects a non-positive timeout', () {
    expect(
      () => NetworkDoctorConfig(timeout: Duration.zero),
      throwsArgumentError,
    );
  });

  test('config rejects empty probe hosts', () {
    expect(() => NetworkDoctorConfig(dnsHost: '  '), throwsArgumentError);
  });

  test('config rejects a non-positive overall timeout', () {
    expect(
      () => NetworkDoctorConfig(overallTimeout: Duration.zero),
      throwsArgumentError,
    );
  });

  test('full redaction hides local and native network addresses', () {
    final report = NetworkDoctorReport(
      generatedAt: DateTime.utc(2026, 8, 7, 9),
      transports: const <NetworkTransport>[NetworkTransport.wifi],
      hasInternet: true,
      health: NetworkHealth.healthy,
      probes: const <NetworkProbeResult>[
        NetworkProbeResult(
          name: 'ipv4',
          status: ProbeStatus.success,
          metadata: <String, Object?>{'address': '192.168.1.1'},
        ),
      ],
      ipv4Available: true,
      ipv6Available: false,
      wifi: const WifiNetworkInfo(
        ssid: 'Office',
        ipv4: '192.168.1.5',
        gateway: '192.168.1.1',
      ),
      platform: const PlatformNetworkInfo(
        dnsServers: <String>['192.168.1.1'],
        routes: <String>['0.0.0.0/0'],
        interfaceName: 'wlan0',
      ),
    );

    final json = report.toJson(
      redactWifiIdentifiers: true,
      redactNetworkAddresses: true,
    );
    final wifi = json['wifi']! as Map<String, Object?>;
    final platform = json['platform']! as Map<String, Object?>;
    final probes = json['probes']! as List<Object?>;
    final probe = probes.single! as Map<String, Object?>;
    final metadata = probe['metadata']! as Map<String, Object?>;

    expect(wifi['ssid'], '<redacted>');
    expect(wifi['ipv4'], '<redacted>');
    expect(platform['dnsServers'], <String>['<redacted>']);
    expect(platform['interfaceName'], '<redacted>');
    expect(metadata['address'], '<redacted>');
  });
}
