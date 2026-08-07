import 'dart:convert';

/// Network transports that may currently be active.
enum NetworkTransport {
  /// Wi-Fi.
  wifi,

  /// Cellular/mobile data.
  mobile,

  /// Ethernet.
  ethernet,

  /// VPN.
  vpn,

  /// Bluetooth network transport.
  bluetooth,

  /// Satellite transport.
  satellite,

  /// An unclassified transport.
  other,

  /// No active transport.
  none,
}

/// Status of an individual diagnostic probe.
enum ProbeStatus {
  /// Probe completed successfully.
  success,

  /// Probe ran but failed.
  failure,

  /// Probe is not supported by the current platform.
  unsupported,

  /// Probe was intentionally skipped.
  skipped,
}

/// Overall network health classification.
enum NetworkHealth {
  /// Network and internet probes look healthy.
  healthy,

  /// Internet works, but one or more diagnostics failed.
  degraded,

  /// A local transport exists, but real internet access was not verified.
  localOnly,

  /// No usable network transport is available.
  offline,

  /// The state could not be determined reliably.
  unknown,
}

/// Result of one network diagnostic probe.
final class NetworkProbeResult {
  /// Creates a probe result.
  const NetworkProbeResult({
    required this.name,
    required this.status,
    this.duration,
    this.message,
    this.metadata = const <String, Object?>{},
  });

  /// Probe name.
  final String name;

  /// Probe status.
  final ProbeStatus status;

  /// Time spent running the probe, when measurable.
  final Duration? duration;

  /// Human-readable result details.
  final String? message;

  /// Structured result metadata.
  final Map<String, Object?> metadata;

  /// Whether this probe completed successfully.
  bool get isSuccess => status == ProbeStatus.success;

  /// Converts this result to JSON-compatible data.
  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'status': status.name,
    'durationMs': duration?.inMilliseconds,
    'message': message,
    'metadata': metadata,
  };
}

/// Wi-Fi and local-network metadata.
final class WifiNetworkInfo {
  /// Creates Wi-Fi metadata.
  const WifiNetworkInfo({
    this.ssid,
    this.bssid,
    this.ipv4,
    this.ipv6,
    this.subnetMask,
    this.broadcast,
    this.gateway,
  });

  /// Service set identifier (Wi-Fi name), when available.
  final String? ssid;

  /// Basic service set identifier (access point MAC), when available.
  final String? bssid;

  /// Local IPv4 address.
  final String? ipv4;

  /// Local IPv6 address.
  final String? ipv6;

  /// IPv4 subnet mask.
  final String? subnetMask;

  /// IPv4 broadcast address.
  final String? broadcast;

  /// Default Wi-Fi gateway address.
  final String? gateway;

  /// Whether at least one Wi-Fi/LAN field was discovered.
  bool get hasData => <String?>[
    ssid,
    bssid,
    ipv4,
    ipv6,
    subnetMask,
    broadcast,
    gateway,
  ].any((String? value) => value != null && value.isNotEmpty);

  /// Converts this value to JSON-compatible data.
  ///
  /// Set [redactIdentifiers] to true before sharing a support report outside
  /// the application. SSID and BSSID values will be replaced when present.
  Map<String, Object?> toJson({bool redactIdentifiers = false}) =>
      <String, Object?>{
        'ssid': redactIdentifiers && ssid != null ? '<redacted>' : ssid,
        'bssid': redactIdentifiers && bssid != null ? '<redacted>' : bssid,
        'ipv4': ipv4,
        'ipv6': ipv6,
        'subnetMask': subnetMask,
        'broadcast': broadcast,
        'gateway': gateway,
      };
}

/// Complete result of a network diagnostic run.
final class NetworkDoctorReport {
  /// Creates a report.
  const NetworkDoctorReport({
    required this.generatedAt,
    required this.transports,
    required this.hasInternet,
    required this.health,
    required this.probes,
    required this.ipv4Available,
    required this.ipv6Available,
    this.wifi,
    this.captivePortalSuspected = false,
  });

  /// Time at which the report was produced.
  final DateTime generatedAt;

  /// Active network transports reported by the operating system.
  final List<NetworkTransport> transports;

  /// Whether real internet reachability was verified.
  final bool hasInternet;

  /// Overall health classification.
  final NetworkHealth health;

  /// Individual diagnostic results.
  final List<NetworkProbeResult> probes;

  /// Whether IPv4 routing was verified.
  final bool ipv4Available;

  /// Whether IPv6 routing was verified.
  final bool ipv6Available;

  /// Wi-Fi/LAN metadata, when available.
  final WifiNetworkInfo? wifi;

  /// Heuristic indication that HTTP probes were redirected unexpectedly.
  ///
  /// This is not proof of a captive portal and should be treated as a hint.
  final bool captivePortalSuspected;

  /// Whether at least one non-`none` network transport is active.
  bool get hasNetworkTransport => transports.any(
    (NetworkTransport value) => value != NetworkTransport.none,
  );

  /// Converts this report to JSON-compatible data.
  ///
  /// Set [redactWifiIdentifiers] before sharing reports with third parties.
  Map<String, Object?> toJson({bool redactWifiIdentifiers = false}) =>
      <String, Object?>{
        'generatedAt': generatedAt.toUtc().toIso8601String(),
        'transports': transports.map((NetworkTransport e) => e.name).toList(),
        'hasInternet': hasInternet,
        'health': health.name,
        'ipv4Available': ipv4Available,
        'ipv6Available': ipv6Available,
        'captivePortalSuspected': captivePortalSuspected,
        'wifi': wifi?.toJson(redactIdentifiers: redactWifiIdentifiers),
        'probes': probes.map((NetworkProbeResult e) => e.toJson()).toList(),
      };

  /// Returns a pretty-printed JSON representation suitable for support logs.
  String toPrettyJson({bool redactWifiIdentifiers = false}) =>
      const JsonEncoder.withIndent(
        '  ',
      ).convert(toJson(redactWifiIdentifiers: redactWifiIdentifiers));
}
