/// Production-grade network diagnostics for Flutter applications.
library;

export 'src/cancellation.dart';
export 'src/config.dart';
export 'src/flutter_network_doctor_base.dart';
export 'src/models.dart';
export 'src/monitor_config.dart';
export 'src/monitor_events.dart';
export 'src/network_doctor_monitor.dart';
export 'src/network_status.dart';
export 'src/widgets/network_doctor_banner.dart';
export 'src/widgets/network_doctor_panel.dart';

/// No-op registration entry point for Dart-only desktop implementations.
///
/// Linux and Windows use the package's `dart:io` probes directly and do not
/// require a native registration channel.
abstract final class FlutterNetworkDoctorDartPlugin {
  /// Registers the Dart-only implementation.
  static void registerWith() {}
}
