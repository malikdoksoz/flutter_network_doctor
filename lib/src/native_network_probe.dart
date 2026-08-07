// ignore_for_file: public_member_api_docs

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'cancellation.dart';
import 'models.dart';
import 'run_cancellation.dart';

/// Platform information and its associated probe result.
final class NativeNetworkProbeOutcome {
  const NativeNetworkProbeOutcome({required this.probe, this.info});

  final NetworkProbeResult probe;
  final PlatformNetworkInfo? info;
}

/// Collects network characteristics exposed by native platform APIs.
final class NativeNetworkProbe {
  const NativeNetworkProbe();

  static const MethodChannel _channel = MethodChannel(
    'flutter_network_doctor/native',
  );

  Future<NativeNetworkProbeOutcome> collect(
    Duration timeout,
    NetworkDoctorRunCancellation cancellation,
  ) async {
    if (!_supportsNativeSnapshot) {
      return const NativeNetworkProbeOutcome(
        probe: NetworkProbeResult(
          name: 'platform',
          status: ProbeStatus.unsupported,
          message:
              'Native network information is unavailable on this platform.',
        ),
      );
    }

    final stopwatch = Stopwatch()..start();
    try {
      final data = await cancellation.guard(
        _channel
            .invokeMapMethod<String, Object?>('getNetworkSnapshot')
            .timeout(timeout),
      );
      stopwatch.stop();
      if (data == null) {
        return NativeNetworkProbeOutcome(
          probe: NetworkProbeResult(
            name: 'platform',
            status: ProbeStatus.failure,
            duration: stopwatch.elapsed,
            message: 'Native platform returned no network information.',
            errorCode: NetworkProbeErrorCode.unavailable,
          ),
        );
      }

      final info = _decode(data);
      return NativeNetworkProbeOutcome(
        info: info,
        probe: NetworkProbeResult(
          name: 'platform',
          status: ProbeStatus.success,
          duration: stopwatch.elapsed,
          message: 'Native network information collected.',
          metadata: info.toJson(),
        ),
      );
    } on NetworkDoctorCancelledException {
      rethrow;
    } on NetworkDoctorTimeoutException {
      rethrow;
    } on Object catch (error) {
      cancellation.throwIfCancelled();
      stopwatch.stop();
      return NativeNetworkProbeOutcome(
        probe: NetworkProbeResult(
          name: 'platform',
          status: ProbeStatus.failure,
          duration: stopwatch.elapsed,
          message: error.toString(),
          errorCode: error is TimeoutException
              ? NetworkProbeErrorCode.timeout
              : error is PlatformException && error.code == 'permission_denied'
              ? NetworkProbeErrorCode.permissionDenied
              : NetworkProbeErrorCode.unavailable,
        ),
      );
    }
  }

  static bool get _supportsNativeSnapshot =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  static PlatformNetworkInfo _decode(Map<String, Object?> data) =>
      PlatformNetworkInfo(
        dnsServers: List<String>.unmodifiable(_strings(data['dnsServers'])),
        routes: List<String>.unmodifiable(_strings(data['routes'])),
        interfaceName: _string(data['interfaceName']),
        mtu: data['mtu'] is int ? data['mtu']! as int : null,
        proxy: _string(data['proxy']),
        privateDnsServerName: _string(data['privateDnsServerName']),
        isMetered: _bool(data['isMetered']),
        isExpensive: _bool(data['isExpensive']),
        isConstrained: _bool(data['isConstrained']),
        isValidated: _bool(data['isValidated']),
        captivePortalDetected: _bool(data['captivePortalDetected']),
        supportsIpv4: _bool(data['supportsIpv4']),
        supportsIpv6: _bool(data['supportsIpv6']),
        supportsDns: _bool(data['supportsDns']),
        localNetworkPermission: _permission(
          _string(data['localNetworkPermission']),
        ),
      );

  static List<String> _strings(Object? value) => value is List<Object?>
      ? value.whereType<String>().toList(growable: false)
      : const <String>[];

  static String? _string(Object? value) => value is String ? value : null;

  static bool? _bool(Object? value) => value is bool ? value : null;

  static LocalNetworkPermissionStatus _permission(String? value) {
    for (final status in LocalNetworkPermissionStatus.values) {
      if (status.name == value) {
        return status;
      }
    }
    return LocalNetworkPermissionStatus.unknown;
  }
}
