import 'package:flutter/material.dart';
import 'package:flutter_network_doctor/flutter_network_doctor.dart';

void main() {
  runApp(const _NetworkDoctorExampleApp());
}

class _NetworkDoctorExampleApp extends StatelessWidget {
  const _NetworkDoctorExampleApp();

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
  bool _running = false;

  @override
  void dispose() {
    _doctor.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    setState(() => _running = true);
    final report = await _doctor.diagnose();
    if (!mounted) {
      return;
    }
    setState(() {
      _report = report;
      _running = false;
    });
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
          const SizedBox(height: 16),
          Expanded(
            child: SingleChildScrollView(
              child: SelectableText(
                _report?.toPrettyJson() ?? 'No report yet.',
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
