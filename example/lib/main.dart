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
  NetworkDoctorReport? _report;
  NetworkDoctorCancellationToken? _cancellationToken;
  String _status = 'Ready';
  bool _running = false;

  @override
  void dispose() {
    _doctor.dispose();
    super.dispose();
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
