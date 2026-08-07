import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_network_doctor/flutter_network_doctor.dart';

void main() {
  runApp(const NetworkDoctorExampleApp());
}

class NetworkDoctorExampleApp extends StatelessWidget {
  const NetworkDoctorExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Flutter Network Doctor',
    theme: ThemeData(useMaterial3: true),
    home: const _NetworkDoctorPage(),
  );
}

class _NetworkDoctorPage extends StatefulWidget {
  const _NetworkDoctorPage();

  @override
  State<_NetworkDoctorPage> createState() => _NetworkDoctorPageState();
}

class _NetworkDoctorPageState extends State<_NetworkDoctorPage> {
  final FlutterNetworkDoctor _doctor = FlutterNetworkDoctor();
  late final NetworkDoctorMonitor _monitor = _doctor.monitor();
  final List<String> _events = <String>[];
  NetworkDoctorReport? _report;
  NetworkDoctorCancellationToken? _cancellationToken;
  String _status = 'Ready';
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _monitor.events.listen(_recordEvent);
  }

  @override
  void dispose() {
    unawaited(_monitor.dispose());
    _doctor.dispose();
    super.dispose();
  }

  void _recordEvent(NetworkMonitorEvent event) {
    final description = switch (event) {
      NetworkBecameOnline() => 'online',
      NetworkBecameOffline() => 'offline',
      NetworkTransportChanged(:final previousTransports) =>
        'transport ${_describeTransports(previousTransports)} → '
            '${_describeTransports(event.status.transports)}',
      NetworkDegraded(:final report) =>
        'degraded (${report?.probes.length ?? 0} probes diagnosed)',
      NetworkRecovered() => 'recovered',
    };
    if (mounted) {
      setState(() {
        _events.insert(0, '${_formatTime(event.timestamp)}  $description');
        if (_events.length > 10) {
          _events.removeLast();
        }
      });
    }
  }

  Future<void> _toggleMonitor() async {
    if (_monitor.isRunning) {
      await _monitor.stop();
    } else {
      await _monitor.start();
    }
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _run() async {
    final cancellationToken = NetworkDoctorCancellationToken();
    setState(() {
      _running = true;
      _cancellationToken = cancellationToken;
      _status = 'Starting…';
    });

    try {
      final report = await _doctor.diagnose(
        config: NetworkDoctorConfig(
          includeGatewayProbe: true,
          includeNetworkQualityProbe: true,
        ),
        cancellationToken: cancellationToken,
        onProgress: (NetworkDoctorProgress progress) {
          if (mounted) {
            setState(() {
              _status =
                  '${progress.stage.name}: '
                  '${progress.completedProbes}/${progress.totalProbes}';
            });
          }
        },
      );
      if (mounted) {
        setState(() => _report = report);
      }
    } on NetworkDoctorCancelledException {
      if (mounted) {
        setState(() => _status = 'Cancelled');
      }
    } finally {
      if (mounted) {
        setState(() {
          _running = false;
          _cancellationToken = null;
        });
      }
    }
  }

  static String _describeTransports(List<NetworkTransport> transports) =>
      transports.map((NetworkTransport e) => e.name).join(', ');

  static String _formatTime(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}:'
      '${value.second.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Network Doctor')),
    body: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          FilledButton.icon(
            onPressed: _running ? null : _run,
            icon: const Icon(Icons.network_check),
            label: Text(_running ? 'Running…' : 'Run diagnostics'),
          ),
          if (_running) ...<Widget>[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _cancellationToken?.cancel,
              icon: const Icon(Icons.cancel_outlined),
              label: const Text('Cancel'),
            ),
          ],
          const SizedBox(height: 8),
          Text(_status),
          const SizedBox(height: 16),
          _MonitorPanel(
            monitor: _monitor,
            events: _events,
            onToggle: _toggleMonitor,
          ),
          const SizedBox(height: 16),
          Expanded(
            child: SingleChildScrollView(
              child: SelectableText(
                _report?.toPrettyJson(
                      redactWifiIdentifiers: true,
                      redactNetworkAddresses: true,
                    ) ??
                    'No report yet.',
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _MonitorPanel extends StatelessWidget {
  const _MonitorPanel({
    required this.monitor,
    required this.events,
    required this.onToggle,
  });

  final NetworkDoctorMonitor monitor;
  final List<String> events;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: StreamBuilder<NetworkStatus>(
                  initialData: monitor.currentStatus,
                  stream: monitor.status,
                  builder:
                      (
                        BuildContext context,
                        AsyncSnapshot<NetworkStatus> snapshot,
                      ) {
                        final status = snapshot.data;
                        if (status == null) {
                          return const Text('Monitor idle');
                        }
                        return Text(
                          '${status.health.name} · '
                          '${status.transports.map((NetworkTransport e) => e.name).join(', ')}',
                          style: Theme.of(context).textTheme.titleMedium,
                        );
                      },
                ),
              ),
              OutlinedButton(
                onPressed: onToggle,
                child: Text(
                  monitor.isRunning ? 'Stop monitor' : 'Start monitor',
                ),
              ),
            ],
          ),
          if (events.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            for (final event in events)
              Text(event, style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      ),
    ),
  );
}
