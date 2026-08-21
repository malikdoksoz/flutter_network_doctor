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

  /// Whether subscribing to [onConnectivityChanged] fails asynchronously.
  ///
  /// Reproduces `connectivity_plus` on Linux, which reaches NetworkManager
  /// over D-Bus from an `async` `onListen` callback and discards the returned
  /// future. A machine without NetworkManager therefore reports the failure as
  /// an uncaught error in the subscribing zone rather than through the
  /// stream's `onError`.
  bool failStreamSetup = false;

  StreamController<List<ConnectivityResult>>? _failingController;

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
  Stream<List<ConnectivityResult>> get onConnectivityChanged {
    if (!failStreamSetup) {
      return controller.stream;
    }
    final failing = _failingController ??=
        StreamController<List<ConnectivityResult>>.broadcast(
          // The future is discarded here exactly as the Linux
          // implementation discards it, which is what turns the failure
          // into an uncaught zone error.
          onListen: () => unawaited(_failToSetUpStream()),
        );
    return failing.stream;
  }

  static Future<void> _failToSetUpStream() async {
    await Future<void>.delayed(Duration.zero);
    throw StateError('The connectivity service is unavailable.');
  }

  /// Reports a new transport set and notifies listeners.
  void emit(List<ConnectivityResult> results) {
    current = results;
    controller.add(results);
  }

  Future<void> close() async {
    await controller.close();
    await _failingController?.close();
  }
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
  addTearDown(() {
    ConnectivityPlatform.instance = previous;
    // Deliberately not awaited. Under `testWidgets` this controller belongs to
    // the test's fake async zone, which stops running before tear-down does, so
    // awaiting its close future would hang the test forever.
    unawaited(fake.close());
  });
  return fake;
}
