import 'models.dart';
import 'network_status.dart';

/// Transition observed by a continuous network monitor.
///
/// Events describe *changes* between observed states. The first status a
/// monitor observes establishes a baseline and produces no event; read
/// `NetworkDoctorMonitor.currentStatus` or the status stream for absolute
/// state.
///
/// This hierarchy is `sealed` so applications can switch over it exhaustively.
/// Adding a new event type therefore breaks existing switches and will only
/// happen in a major release.
sealed class NetworkMonitorEvent {
  /// Creates a monitor event.
  const NetworkMonitorEvent({required this.status, this.report});

  /// Status observed after the transition.
  final NetworkStatus status;

  /// Deep diagnostic report produced for this transition, when one was run.
  ///
  /// A monitor only runs a deep diagnosis when a state change lands on a
  /// non-healthy state and deep diagnosis is enabled.
  final NetworkDoctorReport? report;

  /// Time at which the new status was observed.
  DateTime get timestamp => status.timestamp;
}

/// Emitted when internet reachability was gained.
final class NetworkBecameOnline extends NetworkMonitorEvent {
  /// Creates an online transition event.
  const NetworkBecameOnline({required super.status, super.report});
}

/// Emitted when internet reachability was lost.
final class NetworkBecameOffline extends NetworkMonitorEvent {
  /// Creates an offline transition event.
  const NetworkBecameOffline({required super.status, super.report});
}

/// Emitted when the set of active transports changed.
///
/// A typical case is a device moving from Wi-Fi to mobile data while staying
/// online, which applications often want to react to independently of
/// reachability.
final class NetworkTransportChanged extends NetworkMonitorEvent {
  /// Creates a transport change event.
  const NetworkTransportChanged({
    required super.status,
    required this.previousTransports,
    super.report,
  });

  /// Transports that were active before this change.
  final List<NetworkTransport> previousTransports;

  /// Transports that are active after this change.
  List<NetworkTransport> get transports => status.transports;
}

/// Emitted when the network became reachable but unhealthy.
final class NetworkDegraded extends NetworkMonitorEvent {
  /// Creates a degradation event.
  const NetworkDegraded({required super.status, super.report});
}

/// Emitted when a degraded network became healthy again.
final class NetworkRecovered extends NetworkMonitorEvent {
  /// Creates a recovery event.
  const NetworkRecovered({required super.status, super.report});
}
