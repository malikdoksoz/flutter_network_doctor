import 'dart:async';

import 'models.dart';

/// Cancels an in-progress network diagnostic run.
final class NetworkDoctorCancellationToken {
  /// Creates a cancellation token for one or more diagnostic runs.
  NetworkDoctorCancellationToken();

  final Completer<void> _cancelled = Completer<void>();

  /// Whether cancellation has already been requested.
  bool get isCancelled => _cancelled.isCompleted;

  /// Completes when cancellation is requested.
  Future<void> get whenCancelled => _cancelled.future;

  /// Emits once when cancellation is requested.
  Stream<void> get onCancel => whenCancelled.asStream();

  /// Requests cancellation. Calling this more than once has no effect.
  void cancel() {
    if (isCancelled) {
      return;
    }
    _cancelled.complete();
  }
}

/// Thrown when a diagnostic run is cancelled by its caller.
final class NetworkDoctorCancelledException implements Exception {
  /// Creates a cancellation exception.
  const NetworkDoctorCancelledException();

  @override
  String toString() => 'Network diagnosis was cancelled.';
}

/// Thrown when a diagnostic run exceeds its overall deadline.
final class NetworkDoctorTimeoutException implements Exception {
  /// Creates an overall timeout exception.
  const NetworkDoctorTimeoutException(this.timeout);

  /// Configured overall timeout.
  final Duration timeout;

  @override
  String toString() =>
      'Network diagnosis exceeded ${timeout.inMilliseconds} ms.';
}

/// Stages emitted while a diagnostic run is in progress.
enum NetworkDoctorProgressStage {
  /// The run has started.
  starting,

  /// Operating-system connectivity and Wi-Fi context is being collected.
  collectingContext,

  /// Diagnostic probes are running.
  probing,

  /// The report was completed successfully.
  completed,

  /// The run was cancelled or failed before a report was produced.
  failed,
}

/// Progress update for a diagnostic run.
final class NetworkDoctorProgress {
  /// Creates a progress update.
  const NetworkDoctorProgress({
    required this.stage,
    required this.completedProbes,
    required this.totalProbes,
    this.latestProbe,
  });

  /// Current diagnostic stage.
  final NetworkDoctorProgressStage stage;

  /// Number of probes that have completed.
  final int completedProbes;

  /// Total number of probes scheduled for this run.
  final int totalProbes;

  /// Most recently completed probe, when applicable.
  final NetworkProbeResult? latestProbe;
}

/// Receives progress updates from a diagnostic run.
typedef NetworkDoctorProgressCallback =
    void Function(NetworkDoctorProgress progress);
