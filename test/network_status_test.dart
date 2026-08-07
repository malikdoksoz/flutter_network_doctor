import 'package:flutter_network_doctor/flutter_network_doctor.dart';
import 'package:flutter_test/flutter_test.dart';

NetworkStatus buildStatus({
  List<NetworkTransport> transports = const <NetworkTransport>[
    NetworkTransport.wifi,
  ],
  bool hasInternet = true,
  NetworkHealth health = NetworkHealth.healthy,
  bool captivePortalSuspected = false,
  List<NetworkProbeResult> probes = const <NetworkProbeResult>[],
  Duration? duration = const Duration(milliseconds: 120),
}) => NetworkStatus(
  timestamp: DateTime.utc(2026, 8, 7, 12),
  transports: transports,
  hasInternet: hasInternet,
  health: health,
  probes: probes,
  duration: duration,
  captivePortalSuspected: captivePortalSuspected,
);

void main() {
  test('serializes a status with a schema version', () {
    final json = buildStatus(
      probes: const <NetworkProbeResult>[
        NetworkProbeResult(
          name: 'http:probe.example',
          status: ProbeStatus.success,
          duration: Duration(milliseconds: 42),
        ),
      ],
    ).toJson();

    expect(json['schemaVersion'], 1);
    expect(json['timestamp'], '2026-08-07T12:00:00.000Z');
    expect(json['durationMs'], 120);
    expect(json['transports'], <String>['wifi']);
    expect(json['hasInternet'], isTrue);
    expect(json['health'], 'healthy');
    expect(json['captivePortalSuspected'], isFalse);
    expect((json['probes']! as List<Object?>).length, 1);
  });

  test('redacts sensitive probe metadata when requested', () {
    final json = buildStatus(
      probes: const <NetworkProbeResult>[
        NetworkProbeResult(
          name: 'http:probe.example',
          status: ProbeStatus.failure,
          message: 'Could not reach https://probe.example/health.',
          metadata: <String, Object?>{'uri': 'https://probe.example/health'},
        ),
      ],
    ).toJson(redactNetworkAddresses: true);

    final probe =
        (json['probes']! as List<Object?>).first! as Map<String, Object?>;
    expect(probe['metadata'], <String, Object?>{'uri': '<redacted>'});
    expect(probe['message'], 'Could not reach <redacted>.');
  });

  test('sameStateAs ignores timestamp, duration, and probes', () {
    final first = buildStatus(duration: const Duration(milliseconds: 10));
    final second = NetworkStatus(
      timestamp: DateTime.utc(2030),
      transports: const <NetworkTransport>[NetworkTransport.wifi],
      hasInternet: true,
      health: NetworkHealth.healthy,
      probes: const <NetworkProbeResult>[
        NetworkProbeResult(name: 'dns', status: ProbeStatus.success),
      ],
      duration: const Duration(seconds: 9),
    );

    expect(first.sameStateAs(second), isTrue);
  });

  test('sameStateAs ignores transport order but not transport membership', () {
    final first = buildStatus(
      transports: const <NetworkTransport>[
        NetworkTransport.wifi,
        NetworkTransport.vpn,
      ],
    );
    final reordered = buildStatus(
      transports: const <NetworkTransport>[
        NetworkTransport.vpn,
        NetworkTransport.wifi,
      ],
    );
    final different = buildStatus(
      transports: const <NetworkTransport>[NetworkTransport.mobile],
    );

    expect(first.sameStateAs(reordered), isTrue);
    expect(first.sameStateAs(different), isFalse);
    expect(first.sameTransportsAs(different), isFalse);
  });

  test('sameStateAs separates health, reachability, and captive portals', () {
    final healthy = buildStatus();

    expect(
      healthy.sameStateAs(buildStatus(health: NetworkHealth.degraded)),
      isFalse,
    );
    expect(healthy.sameStateAs(buildStatus(hasInternet: false)), isFalse);
    expect(
      healthy.sameStateAs(buildStatus(captivePortalSuspected: true)),
      isFalse,
    );
  });

  test('hasNetworkTransport ignores the none transport', () {
    expect(buildStatus().hasNetworkTransport, isTrue);
    expect(
      buildStatus(
        transports: const <NetworkTransport>[NetworkTransport.none],
      ).hasNetworkTransport,
      isFalse,
    );
  });

  test('fromReport copies the report state', () {
    final report = NetworkDoctorReport(
      generatedAt: DateTime.utc(2026, 8, 7, 12),
      transports: const <NetworkTransport>[NetworkTransport.mobile],
      hasInternet: true,
      health: NetworkHealth.degraded,
      probes: const <NetworkProbeResult>[
        NetworkProbeResult(name: 'dns', status: ProbeStatus.failure),
      ],
      ipv4Available: true,
      ipv6Available: false,
      totalDuration: const Duration(milliseconds: 340),
      captivePortalSuspected: true,
    );

    final status = NetworkStatus.fromReport(report);

    expect(status.timestamp, report.generatedAt);
    expect(status.transports, report.transports);
    expect(status.hasInternet, isTrue);
    expect(status.health, NetworkHealth.degraded);
    expect(status.probes, report.probes);
    expect(status.duration, const Duration(milliseconds: 340));
    expect(status.captivePortalSuspected, isTrue);
  });
}
