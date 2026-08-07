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

/// Stable machine-readable error categories for failed probes.
enum NetworkProbeErrorCode {
  /// The probe exceeded its individual timeout.
  timeout,

  /// DNS lookup failed.
  dnsLookup,

  /// A TCP or IP route connection failed.
  connection,

  /// TLS negotiation failed.
  tlsHandshake,

  /// An HTTP endpoint returned an unexpected status.
  httpStatus,

  /// Required operating-system permission was unavailable.
  permissionDenied,

  /// Platform information could not be obtained.
  unavailable,

  /// The failure did not match a more specific category.
  unknown,
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

/// Transport used to sample connection quality.
enum NetworkQualityMeasurementMethod {
  /// Repeated TCP connection setup measurements.
  tcpConnect,
}

/// Availability state of an Apple network path snapshot.
enum NetworkPathStatus {
  /// The path can currently carry network traffic.
  satisfied,

  /// The path is currently unavailable.
  unsatisfied,

  /// The path may become available after an action such as joining a network.
  requiresConnection,

  /// The platform did not expose a path state.
  unknown,
}

/// Whether the local gateway responded at the network layer.
enum GatewayReachability {
  /// A TCP connection succeeded or the gateway actively refused it.
  reachable,

  /// Every configured TCP attempt timed out or failed before reaching the
  /// gateway.
  unreachable,
}

/// Result of probing the local Wi-Fi gateway.
final class GatewayReachabilityResult {
  /// Creates a gateway reachability result.
  GatewayReachabilityResult({
    required this.address,
    required List<int> testedPorts,
    required this.reachability,
    required this.duration,
  }) : testedPorts = List<int>.unmodifiable(testedPorts);

  /// Gateway address that was tested.
  final String address;

  /// TCP ports attempted in order.
  final List<int> testedPorts;

  /// Network-layer reachability classification.
  final GatewayReachability reachability;

  /// Total time spent testing the gateway.
  final Duration duration;

  /// Converts this value to JSON-compatible data.
  Map<String, Object?> toJson({bool redactNetworkAddresses = false}) =>
      <String, Object?>{
        'address': redactNetworkAddresses ? '<redacted>' : address,
        'testedPorts': testedPorts,
        'reachability': reachability.name,
        'durationMs': duration.inMicroseconds / 1000,
      };
}

/// Aggregated quality metrics from repeated network samples.
///
/// [packetLossPercent] is the percentage of failed TCP connection samples. It
/// is not an ICMP packet-loss measurement.
final class NetworkQualityResult {
  /// Creates a network quality result.
  NetworkQualityResult({
    required this.method,
    required this.targetHost,
    required this.targetPort,
    required this.sampleCount,
    required this.successfulSamples,
    required this.failedSamples,
    required this.packetLossPercent,
    required List<double?> samplesMs,
    this.minimumLatencyMs,
    this.averageLatencyMs,
    this.p95LatencyMs,
    this.maximumLatencyMs,
    this.jitterMs,
  }) : samplesMs = List<double?>.unmodifiable(samplesMs);

  /// Measurement transport.
  final NetworkQualityMeasurementMethod method;

  /// Host sampled by the measurement.
  final String targetHost;

  /// TCP port sampled by the measurement.
  final int targetPort;

  /// Number of requested samples.
  final int sampleCount;

  /// Number of samples that established a TCP connection.
  final int successfulSamples;

  /// Number of failed or timed-out samples.
  final int failedSamples;

  /// Percentage of failed TCP samples from 0 to 100.
  final double packetLossPercent;

  /// Per-sample connection latency in milliseconds; `null` marks a failure.
  final List<double?> samplesMs;

  /// Lowest successful connection latency in milliseconds.
  final double? minimumLatencyMs;

  /// Mean successful connection latency in milliseconds.
  final double? averageLatencyMs;

  /// Nearest-rank 95th percentile latency in milliseconds.
  final double? p95LatencyMs;

  /// Highest successful connection latency in milliseconds.
  final double? maximumLatencyMs;

  /// Mean absolute difference between consecutive successful samples.
  final double? jitterMs;

  /// Converts this value to JSON-compatible data.
  Map<String, Object?> toJson({bool redactNetworkAddresses = false}) =>
      <String, Object?>{
        'method': method.name,
        'targetHost': redactNetworkAddresses ? '<redacted>' : targetHost,
        'targetPort': targetPort,
        'sampleCount': sampleCount,
        'successfulSamples': successfulSamples,
        'failedSamples': failedSamples,
        'packetLossPercent': packetLossPercent,
        'minimumLatencyMs': minimumLatencyMs,
        'averageLatencyMs': averageLatencyMs,
        'p95LatencyMs': p95LatencyMs,
        'maximumLatencyMs': maximumLatencyMs,
        'jitterMs': jitterMs,
        'samplesMs': samplesMs,
      };
}

/// Result of one network diagnostic probe.
final class NetworkProbeResult {
  /// Creates a probe result.
  const NetworkProbeResult({
    required this.name,
    required this.status,
    this.duration,
    this.message,
    this.errorCode,
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

  /// Stable error category when [status] is [ProbeStatus.failure].
  final NetworkProbeErrorCode? errorCode;

  /// Structured result metadata.
  final Map<String, Object?> metadata;

  /// Whether this probe completed successfully.
  bool get isSuccess => status == ProbeStatus.success;

  /// Converts this result to JSON-compatible data.
  Map<String, Object?> toJson({bool redactNetworkAddresses = false}) =>
      <String, Object?>{
        'name': name,
        'status': status.name,
        'durationMs': duration?.inMilliseconds,
        'message': redactNetworkAddresses
            ? _redactProbeMessage(message, metadata)
            : message,
        'errorCode': errorCode?.name,
        'metadata': redactNetworkAddresses
            ? _redactProbeMetadata(metadata)
            : metadata,
      };
}

const _sensitiveProbeMetadataKeys = <String>{
  'address',
  'addresses',
  'host',
  'targetHost',
  'uri',
  'location',
  'dnsServers',
  'routes',
  'interfaceName',
  'proxy',
  'privateDnsServerName',
};

Map<String, Object?> _redactProbeMetadata(Map<String, Object?> metadata) =>
    metadata.map((String key, Object? value) {
      if (value != null && _sensitiveProbeMetadataKeys.contains(key)) {
        return MapEntry<String, Object?>(key, '<redacted>');
      }
      return MapEntry<String, Object?>(key, value);
    });

String? _redactProbeMessage(String? message, Map<String, Object?> metadata) {
  if (message == null) {
    return null;
  }
  final sensitiveValues = <String>[];
  for (final entry in metadata.entries) {
    if (_sensitiveProbeMetadataKeys.contains(entry.key)) {
      _collectStrings(entry.value, sensitiveValues);
    }
  }
  sensitiveValues.sort((String a, String b) => b.length.compareTo(a.length));
  return sensitiveValues.fold<String>(
    message,
    (String value, String sensitive) =>
        sensitive.isEmpty ? value : value.replaceAll(sensitive, '<redacted>'),
  );
}

void _collectStrings(Object? value, List<String> output) {
  if (value is String) {
    output.add(value);
  } else if (value is Iterable<Object?>) {
    for (final item in value) {
      _collectStrings(item, output);
    }
  }
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
  Map<String, Object?> toJson({
    bool redactIdentifiers = false,
    bool redactNetworkAddresses = false,
  }) => <String, Object?>{
    'ssid': redactIdentifiers && ssid != null ? '<redacted>' : ssid,
    'bssid': redactIdentifiers && bssid != null ? '<redacted>' : bssid,
    'ipv4': redactNetworkAddresses && ipv4 != null ? '<redacted>' : ipv4,
    'ipv6': redactNetworkAddresses && ipv6 != null ? '<redacted>' : ipv6,
    'subnetMask': redactNetworkAddresses && subnetMask != null
        ? '<redacted>'
        : subnetMask,
    'broadcast': redactNetworkAddresses && broadcast != null
        ? '<redacted>'
        : broadcast,
    'gateway': redactNetworkAddresses && gateway != null
        ? '<redacted>'
        : gateway,
  };
}

/// Android local-network permission readiness.
enum LocalNetworkPermissionStatus {
  /// The platform does not use Android's local-network permission model.
  unsupported,

  /// The permission is not required for the current OS/target SDK combination.
  notRequired,

  /// The permission is required and currently granted.
  granted,

  /// The permission is required and currently denied.
  denied,

  /// The platform could not determine the state.
  unknown,
}

/// Native network characteristics reported by the operating system.
final class PlatformNetworkInfo {
  /// Creates platform network information.
  const PlatformNetworkInfo({
    this.dnsServers = const <String>[],
    this.routes = const <String>[],
    this.interfaceName,
    this.mtu,
    this.proxy,
    this.privateDnsServerName,
    this.isMetered,
    this.isExpensive,
    this.isConstrained,
    this.isValidated,
    this.captivePortalDetected,
    this.supportsIpv4,
    this.supportsIpv6,
    this.supportsDns,
    this.pathStatus = NetworkPathStatus.unknown,
    this.localNetworkPermission = LocalNetworkPermissionStatus.unsupported,
  });

  /// DNS server addresses configured for the active link.
  final List<String> dnsServers;

  /// Routes reported for the active link.
  final List<String> routes;

  /// Active interface name, when exposed by the platform.
  final String? interfaceName;

  /// Active link MTU.
  final int? mtu;

  /// Recommended system proxy summary.
  final String? proxy;

  /// Active private DNS server name on Android.
  final String? privateDnsServerName;

  /// Whether the active network is metered.
  final bool? isMetered;

  /// Whether the active path is considered expensive.
  final bool? isExpensive;

  /// Whether background or low-data constraints apply.
  final bool? isConstrained;

  /// Whether the operating system validated the network.
  final bool? isValidated;

  /// Whether the operating system identified a captive portal.
  final bool? captivePortalDetected;

  /// Whether the active path supports IPv4.
  final bool? supportsIpv4;

  /// Whether the active path supports IPv6.
  final bool? supportsIpv6;

  /// Whether the active path has DNS support.
  final bool? supportsDns;

  /// Native path availability on Apple platforms.
  final NetworkPathStatus pathStatus;

  /// Android 17 local-network permission readiness.
  final LocalNetworkPermissionStatus localNetworkPermission;

  /// Converts this value to JSON-compatible data.
  Map<String, Object?> toJson({bool redactNetworkAddresses = false}) =>
      <String, Object?>{
        'dnsServers': redactNetworkAddresses && dnsServers.isNotEmpty
            ? <String>['<redacted>']
            : dnsServers,
        'routes': redactNetworkAddresses && routes.isNotEmpty
            ? <String>['<redacted>']
            : routes,
        'interfaceName': redactNetworkAddresses && interfaceName != null
            ? '<redacted>'
            : interfaceName,
        'mtu': mtu,
        'proxy': redactNetworkAddresses && proxy != null ? '<redacted>' : proxy,
        'privateDnsServerName':
            redactNetworkAddresses && privateDnsServerName != null
            ? '<redacted>'
            : privateDnsServerName,
        'isMetered': isMetered,
        'isExpensive': isExpensive,
        'isConstrained': isConstrained,
        'isValidated': isValidated,
        'captivePortalDetected': captivePortalDetected,
        'supportsIpv4': supportsIpv4,
        'supportsIpv6': supportsIpv6,
        'supportsDns': supportsDns,
        'pathStatus': pathStatus.name,
        'localNetworkPermission': localNetworkPermission.name,
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
    this.totalDuration,
    this.wifi,
    this.platform,
    this.gatewayReachability,
    this.networkQuality,
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

  /// Total duration of the diagnostic run.
  final Duration? totalDuration;

  /// Wi-Fi/LAN metadata, when available.
  final WifiNetworkInfo? wifi;

  /// Native platform network characteristics, when supported.
  final PlatformNetworkInfo? platform;

  /// Local Wi-Fi gateway reachability, when enabled and available.
  final GatewayReachabilityResult? gatewayReachability;

  /// Repeated TCP connection quality metrics, when enabled and supported.
  final NetworkQualityResult? networkQuality;

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
  Map<String, Object?> toJson({
    bool redactWifiIdentifiers = false,
    bool redactNetworkAddresses = false,
  }) => <String, Object?>{
    'schemaVersion': 1,
    'generatedAt': generatedAt.toUtc().toIso8601String(),
    'totalDurationMs': totalDuration?.inMilliseconds,
    'transports': transports.map((NetworkTransport e) => e.name).toList(),
    'hasInternet': hasInternet,
    'health': health.name,
    'ipv4Available': ipv4Available,
    'ipv6Available': ipv6Available,
    'captivePortalSuspected': captivePortalSuspected,
    'wifi': wifi?.toJson(
      redactIdentifiers: redactWifiIdentifiers,
      redactNetworkAddresses: redactNetworkAddresses,
    ),
    'platform': platform?.toJson(
      redactNetworkAddresses: redactNetworkAddresses,
    ),
    'gatewayReachability': gatewayReachability?.toJson(
      redactNetworkAddresses: redactNetworkAddresses,
    ),
    'networkQuality': networkQuality?.toJson(
      redactNetworkAddresses: redactNetworkAddresses,
    ),
    'probes': probes
        .map(
          (NetworkProbeResult e) =>
              e.toJson(redactNetworkAddresses: redactNetworkAddresses),
        )
        .toList(),
  };

  /// Returns a pretty-printed JSON representation suitable for support logs.
  String toPrettyJson({
    bool redactWifiIdentifiers = false,
    bool redactNetworkAddresses = false,
  }) => const JsonEncoder.withIndent('  ').convert(
    toJson(
      redactWifiIdentifiers: redactWifiIdentifiers,
      redactNetworkAddresses: redactNetworkAddresses,
    ),
  );
}
