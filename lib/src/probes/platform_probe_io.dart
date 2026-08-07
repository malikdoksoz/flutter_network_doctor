import 'dart:async';
import 'dart:io';

import '../cancellation.dart';
import '../models.dart';
import '../run_cancellation.dart';
import 'platform_probe_interface.dart';

/// `dart:io` implementation of lower-level network probes.
final class PlatformNetworkProbeImpl implements PlatformNetworkProbe {
  @override
  Future<NetworkProbeResult> dns(
    String host,
    Duration timeout,
    NetworkDoctorRunCancellation cancellation,
  ) async {
    final stopwatch = Stopwatch()..start();
    try {
      final addresses = await cancellation.guard(
        InternetAddress.lookup(host).timeout(timeout),
      );
      stopwatch.stop();
      return NetworkProbeResult(
        name: 'dns',
        status: addresses.isEmpty ? ProbeStatus.failure : ProbeStatus.success,
        duration: stopwatch.elapsed,
        message: addresses.isEmpty
            ? 'No DNS records returned.'
            : 'DNS resolved.',
        errorCode: addresses.isEmpty ? NetworkProbeErrorCode.dnsLookup : null,
        metadata: <String, Object?>{
          'host': host,
          'addresses': addresses.map((InternetAddress e) => e.address).toList(),
        },
      );
    } on NetworkDoctorCancelledException {
      rethrow;
    } on NetworkDoctorTimeoutException {
      rethrow;
    } on Object catch (error) {
      stopwatch.stop();
      return NetworkProbeResult(
        name: 'dns',
        status: ProbeStatus.failure,
        duration: stopwatch.elapsed,
        message: error.toString(),
        errorCode: error is TimeoutException
            ? NetworkProbeErrorCode.timeout
            : NetworkProbeErrorCode.dnsLookup,
        metadata: <String, Object?>{'host': host},
      );
    }
  }

  @override
  Future<NetworkProbeResult> ipRoute(
    String name,
    String address,
    int port,
    Duration timeout,
    NetworkDoctorRunCancellation cancellation,
  ) async {
    final stopwatch = Stopwatch()..start();
    Socket? socket;
    try {
      socket = await cancellation.guard<Socket>(
        Socket.connect(address, port, timeout: timeout),
        onLateValue: (Socket value) => unawaited(value.close()),
      );
      stopwatch.stop();
      return NetworkProbeResult(
        name: name,
        status: ProbeStatus.success,
        duration: stopwatch.elapsed,
        message: 'Route verified with a TCP connection.',
        metadata: <String, Object?>{'address': address, 'port': port},
      );
    } on NetworkDoctorCancelledException {
      rethrow;
    } on NetworkDoctorTimeoutException {
      rethrow;
    } on Object catch (error) {
      stopwatch.stop();
      return NetworkProbeResult(
        name: name,
        status: ProbeStatus.failure,
        duration: stopwatch.elapsed,
        message: error.toString(),
        errorCode: error is TimeoutException
            ? NetworkProbeErrorCode.timeout
            : NetworkProbeErrorCode.connection,
        metadata: <String, Object?>{'address': address, 'port': port},
      );
    } finally {
      await socket?.close();
    }
  }

  @override
  Future<NetworkProbeResult> tcp(
    String host,
    int port,
    Duration timeout,
    NetworkDoctorRunCancellation cancellation,
  ) async {
    final stopwatch = Stopwatch()..start();
    Socket? socket;
    try {
      socket = await cancellation.guard<Socket>(
        Socket.connect(host, port, timeout: timeout),
        onLateValue: (Socket value) => unawaited(value.close()),
      );
      stopwatch.stop();
      return NetworkProbeResult(
        name: 'tcp',
        status: ProbeStatus.success,
        duration: stopwatch.elapsed,
        message: 'TCP connection established.',
        metadata: <String, Object?>{'host': host, 'port': port},
      );
    } on NetworkDoctorCancelledException {
      rethrow;
    } on NetworkDoctorTimeoutException {
      rethrow;
    } on Object catch (error) {
      stopwatch.stop();
      return NetworkProbeResult(
        name: 'tcp',
        status: ProbeStatus.failure,
        duration: stopwatch.elapsed,
        message: error.toString(),
        errorCode: error is TimeoutException
            ? NetworkProbeErrorCode.timeout
            : NetworkProbeErrorCode.connection,
        metadata: <String, Object?>{'host': host, 'port': port},
      );
    } finally {
      await socket?.close();
    }
  }

  @override
  Future<NetworkProbeResult> tls(
    String host,
    int port,
    Duration timeout,
    NetworkDoctorRunCancellation cancellation,
  ) async {
    final stopwatch = Stopwatch()..start();
    SecureSocket? socket;
    try {
      socket = await cancellation.guard<SecureSocket>(
        SecureSocket.connect(host, port, timeout: timeout),
        onLateValue: (SecureSocket value) => unawaited(value.close()),
      );
      stopwatch.stop();
      return NetworkProbeResult(
        name: 'tls',
        status: ProbeStatus.success,
        duration: stopwatch.elapsed,
        message: 'TLS connection established.',
        metadata: <String, Object?>{
          'host': host,
          'port': port,
          'selectedProtocol': socket.selectedProtocol,
        },
      );
    } on NetworkDoctorCancelledException {
      rethrow;
    } on NetworkDoctorTimeoutException {
      rethrow;
    } on Object catch (error) {
      stopwatch.stop();
      return NetworkProbeResult(
        name: 'tls',
        status: ProbeStatus.failure,
        duration: stopwatch.elapsed,
        message: error.toString(),
        errorCode: error is TimeoutException
            ? NetworkProbeErrorCode.timeout
            : NetworkProbeErrorCode.tlsHandshake,
        metadata: <String, Object?>{'host': host, 'port': port},
      );
    } finally {
      await socket?.close();
    }
  }
}
