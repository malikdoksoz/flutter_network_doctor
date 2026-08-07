import 'config.dart';

/// Configuration for a continuous network monitor.
///
/// A monitor works in two tiers. Every trigger runs the cheap check described
/// by [check]; only a trigger that lands on a changed, non-healthy state
/// escalates to the full diagnostic run described by [deepDiagnosis]. Keeping
/// the escalation rare is what makes continuous monitoring affordable in terms
/// of battery and data.
final class NetworkMonitorConfig {
  /// Creates a monitor configuration.
  NetworkMonitorConfig({
    NetworkCheckConfig? check,
    NetworkDoctorConfig? deepDiagnosis,
    this.debounce = const Duration(seconds: 1),
    this.periodicCheckInterval = const Duration(seconds: 30),
    this.runDeepDiagnosisOnFailure = true,
    this.pauseWhenApplicationIsInBackground = true,
  }) : check = check ?? NetworkCheckConfig(),
       deepDiagnosis = deepDiagnosis ?? _defaultDeepDiagnosis() {
    if (debounce < Duration.zero) {
      throw ArgumentError.value(debounce, 'debounce', 'Must not be negative.');
    }
    final interval = periodicCheckInterval;
    if (interval != null && interval <= Duration.zero) {
      throw ArgumentError.value(
        interval,
        'periodicCheckInterval',
        'Must be greater than zero, or null to disable periodic checks.',
      );
    }
  }

  static NetworkDoctorConfig _defaultDeepDiagnosis() => NetworkDoctorConfig(
    timeout: const Duration(seconds: 2),
    overallTimeout: const Duration(seconds: 6),
  );

  /// Configuration for the quick check run on every trigger.
  final NetworkCheckConfig check;

  /// Configuration for the deep diagnosis run after a failing quick check.
  ///
  /// Defaults to tighter deadlines than a standalone diagnostic run so a
  /// monitor reports a network change promptly.
  final NetworkDoctorConfig deepDiagnosis;

  /// Delay applied to operating-system connectivity changes before checking.
  ///
  /// Switching networks typically produces several connectivity notifications
  /// in quick succession; debouncing collapses them into a single check. The
  /// delay applies only to connectivity notifications — periodic checks,
  /// lifecycle resumes, and manual refreshes run immediately.
  final Duration debounce;

  /// Time to wait after a completed check before running the next one.
  ///
  /// Set to `null` to rely purely on connectivity changes and manual
  /// refreshes. The timer is re-armed after each check completes rather than
  /// running on a fixed schedule, so a connectivity-driven check also defers
  /// the next periodic one.
  final Duration? periodicCheckInterval;

  /// Whether a failing quick check escalates to a full diagnostic run.
  final bool runDeepDiagnosisOnFailure;

  /// Whether monitoring pauses while the application is in the background.
  ///
  /// Requires an initialized Flutter binding; when none is available the
  /// monitor keeps running instead of failing. Background monitoring is not
  /// supported, so a paused monitor performs no work at all until the
  /// application is resumed.
  final bool pauseWhenApplicationIsInBackground;
}
