/// Web plugin registration for `flutter_network_doctor`.
library;

import 'package:flutter_web_plugins/flutter_web_plugins.dart';

/// Web registration entry point.
///
/// Browser-safe diagnostics are implemented by the main Dart library.
abstract final class FlutterNetworkDoctorWeb {
  /// Registers the Web implementation.
  static void registerWith(Registrar registrar) {}
}
