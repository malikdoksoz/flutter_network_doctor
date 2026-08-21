import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import 'cancellation.dart';
import 'connectivity_source.dart';
import 'flutter_network_doctor_base.dart';
import 'models.dart';
import 'monitor_config.dart';
import 'monitor_events.dart';
import 'network_status.dart';

/// Watches network state continuously and reports changes as streams.
///
/// A monitor runs in two tiers so continuous watching stays affordable. Every
/// trigger — an operating-system connectivity change, the periodic timer, an
/// application resume, or [refresh] — runs a cheap quick check. Only a check
/// that observes a *changed*, non-healthy state escalates to a full diagnostic
/// run, whose report is attached to the resulting events.
///
/// ```dart
/// final monitor = doctor.monitor();
/// final subscription = monitor.events.listen((NetworkMonitorEvent event) {
///   switch (event) {
///     case NetworkBecameOnline():
///       resumeUploads();
///     case NetworkBecameOffline():
///       showOfflineBanner();
///     case NetworkTransportChanged():
///       adjustQualityForTransport(event.status.transports);
///     case NetworkDegraded(:final report):
///       reportToSupport(report?.toPrettyJson());
///     case NetworkRecovered():
///       hideOfflineBanner();
///   }
/// });
///
/// await monitor.start();
/// ```
///
/// [events] describes *transitions*: the first observed status establishes a
/// baseline and emits no event. Read [currentStatus] or [status] for absolute
/// state. Neither stream ever emits an error; a failed cycle is retried by the
/// next trigger.
///
/// Background monitoring is not supported. When
/// [NetworkMonitorConfig.pauseWhenApplicationIsInBackground] is enabled the
/// monitor performs no work at all while the application is backgrounded.
final class NetworkDoctorMonitor {
  /// Creates a monitor that owns its own [FlutterNetworkDoctor].
  ///
  /// The internal doctor is disposed by [dispose].
  NetworkDoctorMonitor({NetworkMonitorConfig? config, http.Client? httpClient})
    : _doctor = FlutterNetworkDoctor(httpClient: httpClient),
      _ownsDoctor = true,
      config = config ?? NetworkMonitorConfig();

  /// Creates a monitor that reuses an existing [FlutterNetworkDoctor].
  ///
  /// The supplied doctor stays owned by the caller and is never disposed by
  /// this monitor. This is what [FlutterNetworkDoctor.monitor] returns.
  NetworkDoctorMonitor.attached(
    FlutterNetworkDoctor doctor, {
    NetworkMonitorConfig? config,
  }) : _doctor = doctor,
       _ownsDoctor = false,
       config = config ?? NetworkMonitorConfig();

  /// Configuration used by this monitor.
  final NetworkMonitorConfig config;

  final FlutterNetworkDoctor _doctor;
  final bool _ownsDoctor;
  final ConnectivitySource _connectivity = const ConnectivitySource();
  final StreamController<NetworkStatus> _statusController =
      StreamController<NetworkStatus>.broadcast();
  final StreamController<NetworkMonitorEvent> _eventController =
      StreamController<NetworkMonitorEvent>.broadcast();

  StreamSubscription<void>? _connectivitySubscription;
  _MonitorLifecycleObserver? _lifecycleObserver;
  Timer? _debounceTimer;
  Timer? _periodicTimer;
  NetworkDoctorCancellationToken? _cycleToken;
  Future<void>? _cycleFuture;
  Future<NetworkStatus?>? _startFuture;
  NetworkStatus? _lastStatus;
  NetworkDoctorReport? _latestReport;
  bool _running = false;
  bool _paused = false;
  bool _disposed = false;
  bool _cycleRunning = false;
  bool _pendingCycle = false;

  /// Emits a snapshot whenever the observed network state changes.
  ///
  /// This is a broadcast stream that does not replay the current value. Pair it
  /// with [currentStatus] when building widgets:
  ///
  /// ```dart
  /// StreamBuilder<NetworkStatus>(
  ///   initialData: monitor.currentStatus,
  ///   stream: monitor.status,
  ///   builder: (BuildContext context, AsyncSnapshot<NetworkStatus> snapshot) {
  ///     ...
  ///   },
  /// )
  /// ```
  Stream<NetworkStatus> get status => _statusController.stream;

  /// Emits transitions between observed network states.
  Stream<NetworkMonitorEvent> get events => _eventController.stream;

  /// Most recently observed status, or `null` before the first check completed.
  NetworkStatus? get currentStatus => _lastStatus;

  /// Most recent deep diagnostic report, when one has been produced.
  NetworkDoctorReport? get latestReport => _latestReport;

  /// Whether this monitor is currently watching for changes.
  bool get isRunning => _running;

  /// Starts watching and returns the first observed status.
  ///
  /// Returns `null` when the initial check could not complete, for example
  /// because it exceeded its deadline; monitoring still starts and the next
  /// trigger retries. Calling this while already running does not start a
  /// second watch and resolves to the latest known status.
  ///
  /// Throws [StateError] when this monitor has been disposed.
  Future<NetworkStatus?> start() {
    if (_disposed) {
      throw StateError('This NetworkDoctorMonitor has been disposed.');
    }
    final pending = _startFuture;
    if (pending != null) {
      return pending.then((NetworkStatus? _) => _lastStatus);
    }
    return _startFuture = _start();
  }

  /// Stops watching without releasing this monitor.
  ///
  /// Timers are cancelled, the connectivity subscription is released, and any
  /// in-flight check is cancelled and awaited. The streams stay open and
  /// [currentStatus] is retained, so [start] can be called again later and
  /// resumes comparing against the last known state.
  Future<void> stop() async {
    _running = false;
    _paused = false;
    _pendingCycle = false;
    _startFuture = null;
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _periodicTimer?.cancel();
    _periodicTimer = null;
    _removeLifecycleObserver();

    final subscription = _connectivitySubscription;
    _connectivitySubscription = null;
    _cycleToken?.cancel();
    if (subscription != null) {
      try {
        // Not awaited. Events that still arrive are already suppressed by the
        // `_running` flag cleared above, while awaiting the cancellation of a
        // broadcast subscription hangs inside a `testWidgets` fake async zone,
        // where the root zone that completes it never runs.
        unawaited(subscription.cancel());
      } on Object {
        // A platform implementation that fails to tear its own stream down
        // must not stop this monitor from releasing everything else.
      }
    }
    await _awaitCycle();
  }

  /// Runs a check immediately, bypassing the debounce delay.
  ///
  /// Returns the status observed afterwards, which is unchanged when the check
  /// found no difference. Does nothing while the monitor is stopped.
  Future<NetworkStatus?> refresh() async {
    if (_disposed || !_running) {
      return _lastStatus;
    }
    _debounceTimer?.cancel();
    _debounceTimer = null;
    await _runCycle();
    return _lastStatus;
  }

  /// Releases every resource owned by this monitor.
  ///
  /// Stops watching, closes both streams, and disposes the internal doctor when
  /// this monitor created it. Calling this more than once has no effect.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    await stop();
    await _statusController.close();
    await _eventController.close();
    if (_ownsDoctor) {
      _doctor.dispose();
    }
  }

  Future<NetworkStatus?> _start() async {
    _running = true;
    _paused = false;
    _listenToConnectivity();
    _addLifecycleObserver();
    await _runCycle();
    return _lastStatus;
  }

  void _listenToConnectivity() {
    if (_connectivitySubscription != null) {
      return;
    }
    // A platform implementation can also fail *while setting the stream up*,
    // after `listen` has already returned. `connectivity_plus` on Linux
    // reaches NetworkManager over D-Bus from its controller's `onListen`
    // callback and discards the resulting future, so a machine without
    // NetworkManager surfaces the failure as an uncaught error in whichever
    // zone subscribed. Neither the `catch` below nor `onError` can observe
    // that, so the subscription is created in a guarded zone that absorbs it.
    runZonedGuarded(
      () {
        try {
          _connectivitySubscription = _connectivity.onConnectivityChanged
              .listen(
                (_) => _handleConnectivityEvent(),
                onError: (Object _, StackTrace _) {
                  // A failing connectivity stream must not stop monitoring;
                  // periodic checks and manual refreshes keep working.
                },
                cancelOnError: false,
              );
        } on Object {
          // Platforms without a connectivity stream fall back to periodic
          // checks.
          _connectivitySubscription = null;
        }
      },
      (Object _, StackTrace _) {
        // Monitoring degrades to periodic checks and manual refreshes.
      },
    );
  }

  void _handleConnectivityEvent() {
    if (_disposed || !_running || _paused) {
      return;
    }
    final debounce = config.debounce;
    if (debounce <= Duration.zero) {
      unawaited(_runCycle());
      return;
    }
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounce, () {
      _debounceTimer = null;
      unawaited(_runCycle());
    });
  }

  void _rearmPeriodicTimer() {
    _periodicTimer?.cancel();
    _periodicTimer = null;
    final interval = config.periodicCheckInterval;
    if (interval == null || _disposed || !_running || _paused) {
      return;
    }
    _periodicTimer = Timer(interval, () {
      _periodicTimer = null;
      unawaited(_runCycle());
    });
  }

  Future<void> _runCycle() {
    if (_disposed || !_running) {
      return Future<void>.value();
    }
    if (_cycleRunning) {
      // Coalesce: never probe concurrently, but never drop a trigger either.
      _pendingCycle = true;
      return _cycleFuture ?? Future<void>.value();
    }
    _cycleRunning = true;
    final future = _cycle();
    _cycleFuture = future;
    return future;
  }

  Future<void> _cycle() async {
    final token = NetworkDoctorCancellationToken();
    _cycleToken = token;
    NetworkDoctorReport? report;
    try {
      final quickStatus = await _doctor.check(
        config: config.check,
        cancellationToken: token,
      );
      final previous = _lastStatus;
      if (previous != null && quickStatus.sameStateAs(previous)) {
        return;
      }

      var current = quickStatus;
      if (config.runDeepDiagnosisOnFailure &&
          quickStatus.health != NetworkHealth.healthy) {
        report = await _doctor.diagnose(
          config: config.deepDiagnosis,
          cancellationToken: token,
        );
        _latestReport = report;
        current = NetworkStatus.fromReport(report);
        if (previous != null && current.sameStateAs(previous)) {
          // The quick check was a false positive; the network never changed.
          return;
        }
      }

      _lastStatus = current;
      _emit(current, _transitions(previous, current, report));
    } on NetworkDoctorCancelledException {
      // Cancelled cycles are never reported.
    } on NetworkDoctorTimeoutException {
      // Deadline overruns are retried by the next trigger.
    } on Object {
      // Unexpected failures never reach subscribers.
    } finally {
      if (identical(_cycleToken, token)) {
        _cycleToken = null;
      }
      _cycleRunning = false;
      _rearmPeriodicTimer();
      if (_pendingCycle) {
        _pendingCycle = false;
        if (_running && !_paused && !_disposed) {
          unawaited(_runCycle());
        }
      }
    }
  }

  void _emit(NetworkStatus status, List<NetworkMonitorEvent> events) {
    if (_disposed) {
      return;
    }
    if (!_statusController.isClosed) {
      _statusController.add(status);
    }
    if (_eventController.isClosed) {
      return;
    }
    for (final event in events) {
      _eventController.add(event);
    }
  }

  Future<void> _awaitCycle() async {
    final cycle = _cycleFuture;
    if (cycle == null) {
      return;
    }
    try {
      await cycle;
    } on Object {
      // Cycle failures are never surfaced to callers.
    }
  }

  void _addLifecycleObserver() {
    if (!config.pauseWhenApplicationIsInBackground ||
        _lifecycleObserver != null) {
      return;
    }
    final observer = _MonitorLifecycleObserver(
      onPause: _handleApplicationPaused,
      onResume: _handleApplicationResumed,
    );
    try {
      WidgetsBinding.instance.addObserver(observer);
      _lifecycleObserver = observer;
    } on Object {
      // Without an initialized Flutter binding there is nothing to observe;
      // the monitor keeps running instead of failing.
      _lifecycleObserver = null;
    }
  }

  void _removeLifecycleObserver() {
    final observer = _lifecycleObserver;
    _lifecycleObserver = null;
    if (observer == null) {
      return;
    }
    try {
      WidgetsBinding.instance.removeObserver(observer);
    } on Object {
      // The binding is already gone; nothing to remove.
    }
  }

  void _handleApplicationPaused() {
    if (_disposed || !_running || _paused) {
      return;
    }
    _paused = true;
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _periodicTimer?.cancel();
    _periodicTimer = null;
  }

  void _handleApplicationResumed() {
    if (_disposed || !_running || !_paused) {
      return;
    }
    _paused = false;
    unawaited(_runCycle());
  }

  static List<NetworkMonitorEvent> _transitions(
    NetworkStatus? previous,
    NetworkStatus current,
    NetworkDoctorReport? report,
  ) {
    if (previous == null) {
      // The first observation is a baseline, not a transition.
      return const <NetworkMonitorEvent>[];
    }

    final events = <NetworkMonitorEvent>[];
    if (!previous.hasInternet && current.hasInternet) {
      events.add(NetworkBecameOnline(status: current, report: report));
    } else if (previous.hasInternet && !current.hasInternet) {
      events.add(NetworkBecameOffline(status: current, report: report));
    }
    if (!previous.sameTransportsAs(current)) {
      events.add(
        NetworkTransportChanged(
          status: current,
          previousTransports: previous.transports,
          report: report,
        ),
      );
    }
    if (current.health == NetworkHealth.degraded &&
        previous.health != NetworkHealth.degraded) {
      events.add(NetworkDegraded(status: current, report: report));
    } else if (previous.health == NetworkHealth.degraded &&
        current.health == NetworkHealth.healthy) {
      events.add(NetworkRecovered(status: current, report: report));
    }
    return List<NetworkMonitorEvent>.unmodifiable(events);
  }
}

/// Forwards application lifecycle transitions without exposing
/// [WidgetsBindingObserver] on the monitor's public surface.
final class _MonitorLifecycleObserver with WidgetsBindingObserver {
  _MonitorLifecycleObserver({required this.onPause, required this.onResume});

  final VoidCallback onPause;
  final VoidCallback onResume;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        onPause();
      case AppLifecycleState.resumed:
        onResume();
      case AppLifecycleState.inactive:
        // Transient; a notification shade or app switcher must not stop work.
        break;
    }
  }
}
