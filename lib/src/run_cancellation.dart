// ignore_for_file: public_member_api_docs

import 'dart:async';

import 'cancellation.dart';

/// Cancellation and deadline state owned by one diagnostic run.
final class NetworkDoctorRunCancellation {
  NetworkDoctorRunCancellation({
    required Duration overallTimeout,
    NetworkDoctorCancellationToken? externalToken,
  }) {
    _timer = Timer(
      overallTimeout,
      () => cancel(NetworkDoctorTimeoutException(overallTimeout)),
    );
    if (externalToken != null) {
      if (externalToken.isCancelled) {
        cancel(const NetworkDoctorCancelledException());
      } else {
        _externalSubscription = externalToken.onCancel.listen(
          (_) => cancel(const NetworkDoctorCancelledException()),
        );
      }
    }
  }

  final Completer<void> _cancelled = Completer<void>();
  Timer? _timer;
  StreamSubscription<void>? _externalSubscription;
  Object? _reason;
  bool _finished = false;

  Future<void> get whenCancelled => _cancelled.future;

  bool get isCancelled => _reason != null;

  void cancel(Object reason) {
    if (_finished || isCancelled) {
      return;
    }
    _reason = reason;
    _cancelled.complete();
  }

  void throwIfCancelled() {
    final reason = _reason;
    if (reason != null) {
      throw reason;
    }
  }

  Future<T> guard<T>(
    Future<T> operation, {
    void Function(T value)? onLateValue,
  }) {
    throwIfCancelled();
    final completer = Completer<T>();

    operation.then(
      (T value) {
        if (completer.isCompleted) {
          onLateValue?.call(value);
        } else {
          completer.complete(value);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      },
    );
    whenCancelled.then((_) {
      if (!completer.isCompleted) {
        try {
          throwIfCancelled();
        } on Object catch (error, stackTrace) {
          completer.completeError(error, stackTrace);
        }
      }
    });

    return completer.future;
  }

  Future<void> finish() async {
    _finished = true;
    _timer?.cancel();
    // Cancelling takes effect immediately; the returned future is deliberately
    // not awaited. `Future.asStream` completes its cancel future in the root
    // zone, which never runs while a `testWidgets` fake async zone controls the
    // clock, so awaiting it would hang every widget test that runs a
    // diagnosis with a cancellation token.
    unawaited(_externalSubscription?.cancel());
    _externalSubscription = null;
  }
}
