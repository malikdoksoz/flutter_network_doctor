// ignore_for_file: public_member_api_docs

import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';

/// Reads operating-system connectivity through the registered platform
/// implementation.
///
/// `ConnectivityPlatform.instance` is resolved on every call so a platform
/// implementation registered after this object was created is still honoured.
final class ConnectivitySource {
  const ConnectivitySource();

  Future<List<ConnectivityResult>> checkConnectivity() =>
      ConnectivityPlatform.instance.checkConnectivity();

  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      ConnectivityPlatform.instance.onConnectivityChanged;
}
