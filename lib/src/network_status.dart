import 'models.dart';

/// Lightweight snapshot of network state.
///
/// A status is produced by a quick check and carries only the values needed to
/// decide what an application should do right now. Rich context such as Wi-Fi
/// metadata, native platform characteristics, gateway reachability, and quality
/// metrics belongs to [NetworkDoctorReport].
final class NetworkStatus {
  /// Creates a status snapshot.
  const NetworkStatus({
    required this.timestamp,
    required this.transports,
    required this.hasInternet,
    required this.health,
    required this.probes,
    this.duration,
    this.captivePortalSuspected = false,
  });

  /// Derives a status snapshot from a complete diagnostic report.
  factory NetworkStatus.fromReport(NetworkDoctorReport report) => NetworkStatus(
    timestamp: report.generatedAt,
    transports: report.transports,
    hasInternet: report.hasInternet,
    health: report.health,
    probes: report.probes,
    duration: report.totalDuration,
    captivePortalSuspected: report.captivePortalSuspected,
  );

  /// Time at which the status was observed.
  final DateTime timestamp;

  /// Active network transports reported by the operating system.
  final List<NetworkTransport> transports;

  /// Whether internet reachability was verified.
  final bool hasInternet;

  /// Overall health classification.
  final NetworkHealth health;

  /// Probes that produced this status.
  ///
  /// Empty when the check short-circuited because the operating system
  /// reported no active transport.
  final List<NetworkProbeResult> probes;

  /// Time spent producing this status.
  final Duration? duration;

  /// Heuristic indication that HTTP probes were redirected unexpectedly.
  final bool captivePortalSuspected;

  /// Whether at least one non-`none` network transport is active.
  bool get hasNetworkTransport => transports.any(
    (NetworkTransport value) => value != NetworkTransport.none,
  );

  /// Whether [other] reports the same set of transports.
  ///
  /// Transport order is not significant.
  bool sameTransportsAs(NetworkStatus other) {
    if (transports.length != other.transports.length) {
      return false;
    }
    for (final transport in transports) {
      if (!other.transports.contains(transport)) {
        return false;
      }
    }
    return true;
  }

  /// Whether [other] describes the same observable network state.
  ///
  /// Compares [health], [hasInternet], [captivePortalSuspected], and the set of
  /// [transports]. [timestamp], [duration], and [probes] are deliberately
  /// excluded so repeated observations of an unchanged network compare equal.
  bool sameStateAs(NetworkStatus other) =>
      health == other.health &&
      hasInternet == other.hasInternet &&
      captivePortalSuspected == other.captivePortalSuspected &&
      sameTransportsAs(other);

  /// Converts this status to JSON-compatible data.
  Map<String, Object?> toJson({bool redactNetworkAddresses = false}) =>
      <String, Object?>{
        'schemaVersion': 1,
        'timestamp': timestamp.toUtc().toIso8601String(),
        'durationMs': duration?.inMilliseconds,
        'transports': transports.map((NetworkTransport e) => e.name).toList(),
        'hasInternet': hasInternet,
        'health': health.name,
        'captivePortalSuspected': captivePortalSuspected,
        'probes': probes
            .map(
              (NetworkProbeResult e) =>
                  e.toJson(redactNetworkAddresses: redactNetworkAddresses),
            )
            .toList(),
      };
}
