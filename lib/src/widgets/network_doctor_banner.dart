import 'dart:async';

import 'package:flutter/material.dart';

import '../models.dart';
import '../monitor_config.dart';
import '../network_doctor_monitor.dart';
import '../network_status.dart';

/// Decides which observed states a [NetworkDoctorBanner] is visible for.
enum NetworkBannerVisibility {
  /// Visible only while internet reachability could not be verified.
  ///
  /// Covers [NetworkHealth.offline] and [NetworkHealth.localOnly].
  whenOffline,

  /// Visible whenever the network is not healthy.
  ///
  /// Covers [NetworkHealth.offline], [NetworkHealth.localOnly], and
  /// [NetworkHealth.degraded].
  whenNotHealthy,

  /// Visible as soon as any status has been observed, healthy included.
  ///
  /// Useful for debug builds and for applications that keep a permanent
  /// connection indicator on screen.
  always,
}

/// Text shown by a [NetworkDoctorBanner].
///
/// Supply a translated instance to localise the banner. Every field is a plain
/// string so applications can source them from any localisation mechanism.
final class NetworkDoctorBannerLabels {
  /// Creates banner labels.
  const NetworkDoctorBannerLabels({
    this.offline = 'No internet connection',
    this.localOnly = 'Connected, but the internet is unreachable',
    this.degraded = 'Your connection is unstable',
    this.captivePortal = 'Sign in to this network to continue',
    this.healthy = 'Back online',
    this.unknown = 'Network state is unknown',
    this.retry = 'Retry',
  });

  /// Shown when no transport carries traffic.
  final String offline;

  /// Shown when a transport is active but the internet is unreachable.
  final String localOnly;

  /// Shown when the internet is reachable but a diagnostic failed.
  final String degraded;

  /// Shown when probe redirects suggest a captive portal.
  final String captivePortal;

  /// Shown while the network is healthy.
  final String healthy;

  /// Shown when the observed state could not be classified.
  final String unknown;

  /// Label of the retry action.
  final String retry;

  /// Returns the message that describes [status].
  String messageFor(NetworkStatus status) {
    if (status.captivePortalSuspected) {
      return captivePortal;
    }
    return switch (status.health) {
      NetworkHealth.offline => offline,
      NetworkHealth.localOnly => localOnly,
      NetworkHealth.degraded => degraded,
      NetworkHealth.healthy => healthy,
      NetworkHealth.unknown => unknown,
    };
  }
}

/// State handed to a [NetworkDoctorBanner] custom builder.
final class NetworkDoctorBannerData {
  /// Creates banner data.
  const NetworkDoctorBannerData({
    required this.status,
    required this.message,
    required this.isRefreshing,
    required this.isRecoveryNotice,
    required this.retry,
  });

  /// Most recently observed status.
  final NetworkStatus status;

  /// Message selected from the configured labels for [status].
  final String message;

  /// Whether a manual refresh triggered by [retry] is still running.
  final bool isRefreshing;

  /// Whether the banner is showing the transient "back online" notice.
  final bool isRecoveryNotice;

  /// Runs an immediate monitor refresh.
  ///
  /// Does nothing while a refresh is already running.
  final VoidCallback retry;

  /// Overall health of [status].
  NetworkHealth get health => status.health;
}

/// Builds the visible content of a [NetworkDoctorBanner].
typedef NetworkDoctorBannerBuilder =
    Widget Function(BuildContext context, NetworkDoctorBannerData data);

/// Material banner that reflects live network state from a
/// [NetworkDoctorMonitor].
///
/// The banner occupies no space while it is hidden, so it composes directly
/// above application content:
///
/// ```dart
/// Column(
///   children: <Widget>[
///     const NetworkDoctorBanner(),
///     Expanded(child: content),
///   ],
/// )
/// ```
///
/// Without a [monitor] the banner creates one, starts it, and disposes it with
/// the widget. Pass an existing [monitor] to share one across the application;
/// a supplied monitor is never started, stopped, or disposed here, so start it
/// yourself.
///
/// Colours come from the ambient [ColorScheme]: the error colours for
/// unreachable states, the tertiary colours for a degraded connection, and the
/// primary colours for the recovery notice. Supply [builder] to replace the
/// content entirely while keeping the monitor wiring and show/hide animation.
class NetworkDoctorBanner extends StatefulWidget {
  /// Creates a connectivity banner.
  const NetworkDoctorBanner({
    super.key,
    this.monitor,
    this.monitorConfig,
    this.visibility = NetworkBannerVisibility.whenNotHealthy,
    this.labels = const NetworkDoctorBannerLabels(),
    this.showRetryAction = true,
    this.recoveryDisplayDuration = const Duration(seconds: 3),
    this.animationDuration = const Duration(milliseconds: 250),
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    this.onTap,
    this.builder,
  }) : assert(
         monitor == null || monitorConfig == null,
         'monitorConfig only applies to a monitor created by this widget.',
       );

  /// Monitor to observe, or `null` to create and own one.
  final NetworkDoctorMonitor? monitor;

  /// Configuration for the monitor this widget creates.
  ///
  /// Ignored when [monitor] is supplied.
  final NetworkMonitorConfig? monitorConfig;

  /// States this banner is visible for.
  final NetworkBannerVisibility visibility;

  /// Text shown for each state.
  final NetworkDoctorBannerLabels labels;

  /// Whether a retry action that refreshes the monitor is shown.
  ///
  /// The action is never shown on the recovery notice.
  final bool showRetryAction;

  /// How long a healthy "back online" notice stays visible after recovery.
  ///
  /// Set to [Duration.zero] to hide the banner immediately on recovery. Not
  /// used when [visibility] is [NetworkBannerVisibility.always], where a
  /// healthy banner stays visible anyway.
  final Duration recoveryDisplayDuration;

  /// Duration of the show and hide animation.
  final Duration animationDuration;

  /// Padding around the banner content.
  final EdgeInsetsGeometry padding;

  /// Called when the banner is tapped, for example to open a support panel.
  final VoidCallback? onTap;

  /// Replaces the default banner content.
  final NetworkDoctorBannerBuilder? builder;

  @override
  State<NetworkDoctorBanner> createState() => _NetworkDoctorBannerState();
}

class _NetworkDoctorBannerState extends State<NetworkDoctorBanner> {
  NetworkDoctorMonitor? _monitor;
  bool _ownsMonitor = false;
  StreamSubscription<NetworkStatus>? _subscription;
  Timer? _recoveryTimer;
  NetworkStatus? _status;
  bool _isRefreshing = false;
  bool _showsRecovery = false;

  @override
  void initState() {
    super.initState();
    _attach();
  }

  @override
  void didUpdateWidget(NetworkDoctorBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.monitor != oldWidget.monitor) {
      _detach();
      _attach();
    }
  }

  @override
  void dispose() {
    _detach();
    super.dispose();
  }

  void _attach() {
    final supplied = widget.monitor;
    final monitor =
        supplied ?? NetworkDoctorMonitor(config: widget.monitorConfig);
    _monitor = monitor;
    _ownsMonitor = supplied == null;
    _status = monitor.currentStatus;
    _showsRecovery = false;
    _subscription = monitor.status.listen(_handleStatus);
    if (_ownsMonitor) {
      unawaited(monitor.start());
    }
  }

  void _detach() {
    _recoveryTimer?.cancel();
    _recoveryTimer = null;
    unawaited(_subscription?.cancel());
    _subscription = null;
    final monitor = _monitor;
    _monitor = null;
    if (_ownsMonitor && monitor != null) {
      unawaited(monitor.dispose());
    }
  }

  void _handleStatus(NetworkStatus status) {
    final previous = _status;
    final recovered =
        previous != null &&
        _matchesVisibility(previous) &&
        !_matchesVisibility(status) &&
        status.health == NetworkHealth.healthy &&
        widget.recoveryDisplayDuration > Duration.zero;

    _recoveryTimer?.cancel();
    _recoveryTimer = null;
    if (recovered) {
      _recoveryTimer = Timer(widget.recoveryDisplayDuration, () {
        _recoveryTimer = null;
        if (mounted) {
          setState(() => _showsRecovery = false);
        }
      });
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _status = status;
      _showsRecovery = recovered;
    });
  }

  Future<void> _retry() async {
    final monitor = _monitor;
    if (_isRefreshing || monitor == null) {
      return;
    }
    setState(() => _isRefreshing = true);
    try {
      await monitor.refresh();
    } on Object {
      // A failed refresh leaves the last observed status in place; the next
      // monitor trigger retries.
    } finally {
      if (mounted) {
        setState(() => _isRefreshing = false);
      }
    }
  }

  bool _matchesVisibility(NetworkStatus status) => switch (widget.visibility) {
    NetworkBannerVisibility.always => true,
    NetworkBannerVisibility.whenOffline =>
      status.health == NetworkHealth.offline ||
          status.health == NetworkHealth.localOnly,
    NetworkBannerVisibility.whenNotHealthy =>
      status.health == NetworkHealth.offline ||
          status.health == NetworkHealth.localOnly ||
          status.health == NetworkHealth.degraded,
  };

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final visible =
        status != null && (_showsRecovery || _matchesVisibility(status));
    final message = status == null ? '' : widget.labels.messageFor(status);

    return AnimatedSwitcher(
      duration: widget.animationDuration,
      transitionBuilder: (Widget child, Animation<double> animation) =>
          FadeTransition(
            opacity: animation,
            child: AnimatedBuilder(
              animation: animation,
              // Grows and shrinks from the top edge, which keeps the banner
              // anchored to whatever it sits above.
              builder: (BuildContext context, Widget? built) => ClipRect(
                child: Align(
                  alignment: Alignment.topCenter,
                  heightFactor: animation.value.clamp(0.0, 1.0),
                  child: built,
                ),
              ),
              child: child,
            ),
          ),
      child: visible
          ? KeyedSubtree(
              key: ValueKey<String>(message),
              child: _buildBanner(context, status, message),
            )
          : const SizedBox(
              key: ValueKey<String>('hidden'),
              width: 0,
              height: 0,
            ),
    );
  }

  Widget _buildBanner(
    BuildContext context,
    NetworkStatus status,
    String message,
  ) {
    final data = NetworkDoctorBannerData(
      status: status,
      message: message,
      isRefreshing: _isRefreshing,
      isRecoveryNotice: _showsRecovery,
      retry: () => unawaited(_retry()),
    );
    final builder = widget.builder;
    if (builder != null) {
      return Semantics(
        container: true,
        liveRegion: true,
        child: builder(context, data),
      );
    }

    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final (Color background, Color foreground) = switch (status.health) {
      NetworkHealth.offline || NetworkHealth.localOnly => (
        colors.errorContainer,
        colors.onErrorContainer,
      ),
      NetworkHealth.degraded => (
        colors.tertiaryContainer,
        colors.onTertiaryContainer,
      ),
      NetworkHealth.healthy => (
        colors.primaryContainer,
        colors.onPrimaryContainer,
      ),
      NetworkHealth.unknown => (
        colors.surfaceContainerHighest,
        colors.onSurfaceVariant,
      ),
    };
    final icon = status.captivePortalSuspected
        ? Icons.lock_outline
        : switch (status.health) {
            NetworkHealth.offline => Icons.wifi_off_rounded,
            NetworkHealth.localOnly => Icons.cloud_off_rounded,
            NetworkHealth.degraded => Icons.warning_amber_rounded,
            NetworkHealth.healthy => Icons.check_circle_outline,
            NetworkHealth.unknown => Icons.help_outline,
          };
    final showRetry = widget.showRetryAction && !_showsRecovery;

    return Semantics(
      container: true,
      liveRegion: true,
      child: Material(
        color: background,
        child: InkWell(
          onTap: widget.onTap,
          child: Padding(
            padding: widget.padding,
            child: Row(
              children: <Widget>[
                Icon(icon, size: 20, color: foreground),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    message,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: foreground,
                    ),
                  ),
                ),
                if (showRetry) ...<Widget>[
                  const SizedBox(width: 8),
                  if (_isRefreshing)
                    SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: foreground,
                      ),
                    )
                  else
                    TextButton(
                      onPressed: data.retry,
                      style: TextButton.styleFrom(foregroundColor: foreground),
                      child: Text(widget.labels.retry),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
