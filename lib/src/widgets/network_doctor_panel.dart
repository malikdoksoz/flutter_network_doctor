import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../cancellation.dart';
import '../config.dart';
import '../flutter_network_doctor_base.dart';
import '../models.dart';

/// Text shown by a [NetworkDoctorPanel].
///
/// Supply a translated instance to localise the panel.
final class NetworkDoctorPanelLabels {
  /// Creates panel labels.
  const NetworkDoctorPanelLabels({
    this.title = 'Network diagnostics',
    this.run = 'Run diagnostics',
    this.running = 'Running…',
    this.cancel = 'Cancel',
    this.copy = 'Copy report',
    this.copied = 'Copied',
    this.share = 'Share report',
    this.empty = 'No report yet.',
    this.cancelled = 'Diagnostics cancelled.',
    this.summary = 'Summary',
    this.wifi = 'Wi-Fi and LAN',
    this.platform = 'Platform',
    this.gateway = 'Gateway',
    this.quality = 'Connection quality',
    this.probes = 'Probes',
  });

  /// Panel heading.
  final String title;

  /// Label of the action that starts a diagnostic run.
  final String run;

  /// Label of the run action while a run is in progress.
  final String running;

  /// Label of the action that cancels a running diagnosis.
  final String cancel;

  /// Label of the action that copies the report JSON.
  final String copy;

  /// Label shown briefly after the report JSON was copied.
  final String copied;

  /// Label of the action that shares the report JSON.
  final String share;

  /// Shown before the first report is available.
  final String empty;

  /// Shown after a run was cancelled.
  final String cancelled;

  /// Heading of the summary section.
  final String summary;

  /// Heading of the Wi-Fi and LAN section.
  final String wifi;

  /// Heading of the native platform section.
  final String platform;

  /// Heading of the gateway section.
  final String gateway;

  /// Heading of the connection quality section.
  final String quality;

  /// Heading of the probe list.
  final String probes;
}

/// Material support panel that runs diagnostics and presents the result.
///
/// The panel renders a full [NetworkDoctorReport] as readable sections, copies
/// the report as JSON to the clipboard, and hands the same JSON to [onShare]
/// when a share action is wanted.
///
/// ```dart
/// NetworkDoctorPanel(
///   config: NetworkDoctorConfig(includeGatewayProbe: true),
///   onShare: (String json) => Share.share(json),
/// )
/// ```
///
/// Without a [doctor] the panel creates one and disposes it with the widget.
/// A supplied [doctor] stays owned by the caller.
///
/// [redactWifiIdentifiers] and [redactNetworkAddresses] apply to the copied and
/// shared JSON only. Values are rendered unredacted on screen, because the
/// panel runs on the device whose network it describes; keep that in mind
/// before asking users for screenshots.
class NetworkDoctorPanel extends StatefulWidget {
  /// Creates a diagnostics panel.
  const NetworkDoctorPanel({
    super.key,
    this.doctor,
    this.config,
    this.initialReport,
    this.runOnStart = true,
    this.redactWifiIdentifiers = true,
    this.redactNetworkAddresses = true,
    this.labels = const NetworkDoctorPanelLabels(),
    this.onShare,
    this.padding = const EdgeInsets.all(16),
    this.scrollable = true,
  });

  /// Shows a panel in a modal bottom sheet.
  ///
  /// Returns when the sheet is dismissed.
  static Future<void> showAsBottomSheet(
    BuildContext context, {
    FlutterNetworkDoctor? doctor,
    NetworkDoctorConfig? config,
    NetworkDoctorReport? initialReport,
    bool runOnStart = true,
    bool redactWifiIdentifiers = true,
    bool redactNetworkAddresses = true,
    NetworkDoctorPanelLabels labels = const NetworkDoctorPanelLabels(),
    void Function(String reportJson)? onShare,
    double heightFactor = 0.9,
  }) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (BuildContext context) => FractionallySizedBox(
      heightFactor: heightFactor,
      child: NetworkDoctorPanel(
        doctor: doctor,
        config: config,
        initialReport: initialReport,
        runOnStart: runOnStart,
        redactWifiIdentifiers: redactWifiIdentifiers,
        redactNetworkAddresses: redactNetworkAddresses,
        labels: labels,
        onShare: onShare,
      ),
    ),
  );

  /// Doctor used for diagnostic runs, or `null` to create and own one.
  final FlutterNetworkDoctor? doctor;

  /// Configuration applied to every run started by this panel.
  final NetworkDoctorConfig? config;

  /// Report shown before the first run completes.
  ///
  /// Pass `monitor.latestReport` to reuse the deep diagnosis a monitor already
  /// produced.
  final NetworkDoctorReport? initialReport;

  /// Whether a diagnostic run starts as soon as the panel is inserted.
  final bool runOnStart;

  /// Whether SSID and BSSID are redacted in the copied and shared JSON.
  final bool redactWifiIdentifiers;

  /// Whether network addresses are redacted in the copied and shared JSON.
  final bool redactNetworkAddresses;

  /// Text shown by the panel.
  final NetworkDoctorPanelLabels labels;

  /// Receives the report JSON when the share action is used.
  ///
  /// The share action is hidden while this is `null`.
  final void Function(String reportJson)? onShare;

  /// Padding around the panel content.
  final EdgeInsetsGeometry padding;

  /// Whether the panel scrolls its own content.
  ///
  /// Set to `false` when the panel is already inside a scroll view.
  final bool scrollable;

  @override
  State<NetworkDoctorPanel> createState() => _NetworkDoctorPanelState();
}

class _NetworkDoctorPanelState extends State<NetworkDoctorPanel> {
  late FlutterNetworkDoctor _doctor;
  late bool _ownsDoctor;
  NetworkDoctorReport? _report;
  NetworkDoctorProgress? _progress;
  NetworkDoctorCancellationToken? _cancellationToken;
  Timer? _copyResetTimer;
  String? _error;
  bool _running = false;
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    _ownsDoctor = widget.doctor == null;
    _doctor = widget.doctor ?? FlutterNetworkDoctor();
    _report = widget.initialReport;
    if (widget.runOnStart) {
      unawaited(_run());
    }
  }

  @override
  void didUpdateWidget(NetworkDoctorPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.doctor != oldWidget.doctor) {
      if (_ownsDoctor) {
        _doctor.dispose();
      }
      _ownsDoctor = widget.doctor == null;
      _doctor = widget.doctor ?? FlutterNetworkDoctor();
    }
  }

  @override
  void dispose() {
    _copyResetTimer?.cancel();
    _cancellationToken?.cancel();
    if (_ownsDoctor) {
      _doctor.dispose();
    }
    super.dispose();
  }

  Future<void> _run() async {
    if (_running) {
      return;
    }
    final token = NetworkDoctorCancellationToken();
    setState(() {
      _running = true;
      _error = null;
      _progress = null;
      _cancellationToken = token;
    });
    try {
      final report = await _doctor.diagnose(
        config: widget.config,
        cancellationToken: token,
        onProgress: (NetworkDoctorProgress progress) {
          if (mounted) {
            setState(() => _progress = progress);
          }
        },
      );
      if (mounted) {
        setState(() => _report = report);
      }
    } on NetworkDoctorCancelledException {
      if (mounted) {
        setState(() => _error = widget.labels.cancelled);
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() {
          _running = false;
          _progress = null;
          _cancellationToken = null;
        });
      }
    }
  }

  String? _reportJson() => _report?.toPrettyJson(
    redactWifiIdentifiers: widget.redactWifiIdentifiers,
    redactNetworkAddresses: widget.redactNetworkAddresses,
  );

  Future<void> _copy() async {
    final json = _reportJson();
    if (json == null) {
      return;
    }
    try {
      await Clipboard.setData(ClipboardData(text: json));
    } on Object {
      // A platform without clipboard support must not break the panel.
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() => _copied = true);
    _copyResetTimer?.cancel();
    _copyResetTimer = Timer(const Duration(seconds: 2), () {
      _copyResetTimer = null;
      if (mounted) {
        setState(() => _copied = false);
      }
    });
  }

  void _share() {
    final json = _reportJson();
    if (json != null) {
      widget.onShare?.call(json);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labels = widget.labels;
    final report = _report;
    final progress = _progress;
    final error = _error;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(labels.title, style: theme.textTheme.titleLarge),
            ),
            if (report != null) _HealthChip(health: report.health),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            FilledButton.icon(
              onPressed: _running ? null : () => unawaited(_run()),
              icon: const Icon(Icons.network_check),
              label: Text(_running ? labels.running : labels.run),
            ),
            if (_running)
              OutlinedButton.icon(
                onPressed: _cancellationToken?.cancel,
                icon: const Icon(Icons.cancel_outlined),
                label: Text(labels.cancel),
              ),
            TextButton.icon(
              onPressed: report == null ? null : () => unawaited(_copy()),
              icon: Icon(_copied ? Icons.check : Icons.copy_all_outlined),
              label: Text(_copied ? labels.copied : labels.copy),
            ),
            if (widget.onShare != null)
              TextButton.icon(
                onPressed: report == null ? null : _share,
                icon: const Icon(Icons.ios_share),
                label: Text(labels.share),
              ),
          ],
        ),
        if (progress != null) ...<Widget>[
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: progress.totalProbes == 0
                ? null
                : progress.completedProbes / progress.totalProbes,
          ),
          const SizedBox(height: 4),
          Text(
            '${progress.stage.name} · '
            '${progress.completedProbes}/${progress.totalProbes}',
            style: theme.textTheme.bodySmall,
          ),
        ],
        if (error != null) ...<Widget>[
          const SizedBox(height: 12),
          Text(
            error,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
        const SizedBox(height: 12),
        if (report == null)
          Text(labels.empty, style: theme.textTheme.bodyMedium)
        else
          ..._buildReportSections(context, report),
      ],
    );

    final padded = Padding(padding: widget.padding, child: content);
    return widget.scrollable ? SingleChildScrollView(child: padded) : padded;
  }

  List<Widget> _buildReportSections(
    BuildContext context,
    NetworkDoctorReport report,
  ) {
    final labels = widget.labels;
    final wifi = report.wifi;
    final platform = report.platform;
    final gateway = report.gatewayReachability;
    final quality = report.networkQuality;

    return <Widget>[
      _Section(
        title: labels.summary,
        rows: <_Row>[
          _Row('Health', report.health.name),
          _Row('Internet', _yesNo(report.hasInternet)),
          _Row('Transports', _describeTransports(report.transports)),
          _Row('IPv4 route', _yesNo(report.ipv4Available)),
          _Row('IPv6 route', _yesNo(report.ipv6Available)),
          if (report.captivePortalSuspected)
            const _Row('Captive portal', 'suspected'),
          _Row('Duration', _describeDuration(report.totalDuration)),
          _Row('Generated', report.generatedAt.toLocal().toString()),
        ],
      ),
      if (wifi != null)
        _Section(
          title: labels.wifi,
          rows: <_Row>[
            _Row('SSID', wifi.ssid),
            _Row('BSSID', wifi.bssid),
            _Row('IPv4', wifi.ipv4),
            _Row('IPv6', wifi.ipv6),
            _Row('Subnet mask', wifi.subnetMask),
            _Row('Broadcast', wifi.broadcast),
            _Row('Gateway', wifi.gateway),
          ],
        ),
      if (platform != null)
        _Section(
          title: labels.platform,
          rows: <_Row>[
            _Row('Interface', platform.interfaceName),
            _Row(
              'DNS servers',
              platform.dnsServers.isEmpty
                  ? null
                  : platform.dnsServers.join(', '),
            ),
            _Row(
              'Routes',
              platform.routes.isEmpty ? null : platform.routes.join(', '),
            ),
            _Row('MTU', platform.mtu?.toString()),
            _Row('Proxy', platform.proxy),
            _Row('Private DNS', platform.privateDnsServerName),
            _Row('Metered', _optionalYesNo(platform.isMetered)),
            _Row('Expensive', _optionalYesNo(platform.isExpensive)),
            _Row('Constrained', _optionalYesNo(platform.isConstrained)),
            _Row('Validated', _optionalYesNo(platform.isValidated)),
            _Row(
              'Captive portal',
              _optionalYesNo(platform.captivePortalDetected),
            ),
            _Row('Path status', platform.pathStatus.name),
            _Row('Local network', platform.localNetworkPermission.name),
          ],
        ),
      if (gateway != null)
        _Section(
          title: labels.gateway,
          rows: <_Row>[
            _Row('Address', gateway.address),
            _Row('Reachability', gateway.reachability.name),
            _Row('Tested ports', gateway.testedPorts.join(', ')),
            _Row('Duration', _describeDuration(gateway.duration)),
          ],
        ),
      if (quality != null)
        _Section(
          title: labels.quality,
          rows: <_Row>[
            _Row('Method', quality.method.name),
            _Row('Target', '${quality.targetHost}:${quality.targetPort}'),
            _Row(
              'Samples',
              '${quality.successfulSamples}/${quality.sampleCount} succeeded',
            ),
            _Row('Minimum', _describeMs(quality.minimumLatencyMs)),
            _Row('Average', _describeMs(quality.averageLatencyMs)),
            _Row('p95', _describeMs(quality.p95LatencyMs)),
            _Row('Maximum', _describeMs(quality.maximumLatencyMs)),
            _Row('Jitter', _describeMs(quality.jitterMs)),
            _Row('Failed samples', '${quality.packetLossPercent.round()}%'),
          ],
        ),
      _ProbeSection(title: labels.probes, probes: report.probes),
    ];
  }

  static String _yesNo(bool value) => value ? 'yes' : 'no';

  static String? _optionalYesNo(bool? value) =>
      value == null ? null : _yesNo(value);

  static String _describeTransports(List<NetworkTransport> transports) =>
      transports.isEmpty
      ? NetworkTransport.none.name
      : transports.map((NetworkTransport e) => e.name).join(', ');

  static String? _describeDuration(Duration? value) =>
      value == null ? null : '${value.inMilliseconds} ms';

  static String? _describeMs(double? value) =>
      value == null ? null : '${value.toStringAsFixed(1)} ms';
}

class _HealthChip extends StatelessWidget {
  const _HealthChip({required this.health});

  final NetworkHealth health;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final (Color background, Color foreground) = switch (health) {
      NetworkHealth.healthy => (
        colors.primaryContainer,
        colors.onPrimaryContainer,
      ),
      NetworkHealth.degraded => (
        colors.tertiaryContainer,
        colors.onTertiaryContainer,
      ),
      NetworkHealth.localOnly ||
      NetworkHealth.offline => (colors.errorContainer, colors.onErrorContainer),
      NetworkHealth.unknown => (
        colors.surfaceContainerHighest,
        colors.onSurfaceVariant,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        health.name,
        style: Theme.of(
          context,
        ).textTheme.labelLarge?.copyWith(color: foreground),
      ),
    );
  }
}

class _Row {
  const _Row(this.label, this.value);

  final String label;
  final String? value;
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.rows});

  final String title;
  final List<_Row> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visible = rows
        .where((_Row row) => row.value != null && row.value!.isNotEmpty)
        .toList(growable: false);
    if (visible.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          for (final row in visible)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SizedBox(
                    width: 132,
                    child: Text(
                      row.label,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Expanded(
                    child: SelectableText(
                      row.value!,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ProbeSection extends StatelessWidget {
  const _ProbeSection({required this.title, required this.probes});

  final String title;
  final List<NetworkProbeResult> probes;

  @override
  Widget build(BuildContext context) {
    if (probes.isEmpty) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(title, style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        for (final probe in probes)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(
                  switch (probe.status) {
                    ProbeStatus.success => Icons.check_circle_outline,
                    ProbeStatus.failure => Icons.error_outline,
                    ProbeStatus.unsupported => Icons.block_outlined,
                    ProbeStatus.skipped => Icons.remove_circle_outline,
                  },
                  size: 18,
                  color: switch (probe.status) {
                    ProbeStatus.success => colors.primary,
                    ProbeStatus.failure => colors.error,
                    ProbeStatus.unsupported ||
                    ProbeStatus.skipped => colors.onSurfaceVariant,
                  },
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        probe.duration == null
                            ? probe.name
                            : '${probe.name} · ${probe.duration!.inMilliseconds} ms',
                        style: theme.textTheme.bodyMedium,
                      ),
                      if (probe.message != null)
                        Text(
                          probe.message!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
