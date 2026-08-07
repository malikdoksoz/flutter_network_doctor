import 'dart:async';

import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';

/// Replaces the registered connectivity platform implementation for a test.
///
/// `extends ConnectivityPlatform` (rather than `implements`) is required so the
/// platform interface token check accepts this instance.
final class FakeConnectivity extends ConnectivityPlatform {
  FakeConnectivity([
    this.current = const <ConnectivityResult>[ConnectivityResult.wifi],
  ]);

  final StreamController<List<ConnectivityResult>> controller =
      StreamController<List<ConnectivityResult>>.broadcast();

  /// Results returned by the next reads, ahead of [current].
  ///
  /// Used to reproduce a platform whose first read reports no transport before
  /// its path monitor has settled.
  final List<List<ConnectivityResult>> scriptedReads =
      <List<ConnectivityResult>>[];

  List<ConnectivityResult> current;
  bool failCheck = false;
  int checkCount = 0;

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async {
    checkCount += 1;
    if (failCheck) {
      throw StateError('Connectivity is unavailable in this test.');
    }
    if (scriptedReads.isNotEmpty) {
      return scriptedReads.removeAt(0);
    }
    return current;
  }

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      controller.stream;

  /// Reports a new transport set and notifies listeners.
  void emit(List<ConnectivityResult> results) {
    current = results;
    controller.add(results);
  }

  Future<void> close() => controller.close();
}

/// Installs [fake] as the connectivity platform and restores the previous
/// implementation when the test ends.
FakeConnectivity installFakeConnectivity(
  void Function(dynamic Function()) addTearDown, [
  List<ConnectivityResult> initial = const <ConnectivityResult>[
    ConnectivityResult.wifi,
  ],
]) {
  final previous = ConnectivityPlatform.instance;
  final fake = FakeConnectivity(initial);
  ConnectivityPlatform.instance = fake;
  addTearDown(() async {
    ConnectivityPlatform.instance = previous;
    await fake.close();
  });
  return fake;
}
