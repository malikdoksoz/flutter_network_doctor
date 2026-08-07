import 'dart:async';
import 'dart:io';

import '../cancellation.dart';
import '../models.dart';
import '../quality_metrics.dart';
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
  Future<GatewayProbeOutcome> gateway(
    String? address,
    List<int> ports,
    Duration timeout,
    NetworkDoctorRunCancellation cancellation,
  ) async {
    if (address == null || address.trim().isEmpty) {
      return const GatewayProbeOutcome(
        probe: NetworkProbeResult(
          name: 'gateway',
          status: ProbeStatus.skipped,
          message: 'No local Wi-Fi gateway address is available.',
        ),
      );
    }

    final stopwatch = Stopwatch()..start();
    final testedPorts = <int>[];
    Object? lastError;
    for (final port in ports) {
      cancellation.throwIfCancelled();
      testedPorts.add(port);
      Socket? socket;
      try {
        socket = await cancellation.guard<Socket>(
          Socket.connect(address, port, timeout: timeout),
          onLateValue: (Socket value) => unawaited(value.close()),
        );
        stopwatch.stop();
        return _reachableGatewayOutcome(
          address: address,
          testedPorts: testedPorts,
          duration: stopwatch.elapsed,
          message: 'Gateway accepted a TCP connection.',
        );
      } on NetworkDoctorCancelledException {
        rethrow;
      } on NetworkDoctorTimeoutException {
        rethrow;
      } on SocketException catch (error) {
        lastError = error;
        if (isConnectionRefusedErrorCode(error.osError?.errorCode)) {
          stopwatch.stop();
          return _reachableGatewayOutcome(
            address: address,
            testedPorts: testedPorts,
            duration: stopwatch.elapsed,
            message: 'Gateway actively refused a TCP connection.',
          );
        }
      } on Object catch (error) {
        lastError = error;
      } finally {
        await socket?.close();
      }
    }

    stopwatch.stop();
    final result = GatewayReachabilityResult(
      address: address,
      testedPorts: testedPorts,
      reachability: GatewayReachability.unreachable,
      duration: stopwatch.elapsed,
    );
    return GatewayProbeOutcome(
      result: result,
      probe: NetworkProbeResult(
        name: 'gateway',
        status: ProbeStatus.failure,
        duration: stopwatch.elapsed,
        message: lastError?.toString() ?? 'Gateway did not respond.',
        errorCode: NetworkProbeErrorCode.connection,
        metadata: result.toJson(),
      ),
    );
  }

  @override
  Future<NetworkQualityProbeOutcome> networkQuality(
    String host,
    int port,
    int sampleCount,
    Duration sampleTimeout,
    Duration sampleInterval,
    NetworkDoctorRunCancellation cancellation,
  ) async {
    final totalStopwatch = Stopwatch()..start();
    final samples = <Duration?>[];

    for (var index = 0; index < sampleCount; index += 1) {
      cancellation.throwIfCancelled();
      final sampleStopwatch = Stopwatch()..start();
      Socket? socket;
      try {
        socket = await cancellation.guard<Socket>(
          Socket.connect(host, port, timeout: sampleTimeout),
          onLateValue: (Socket value) => unawaited(value.close()),
        );
        sampleStopwatch.stop();
        samples.add(sampleStopwatch.elapsed);
      } on NetworkDoctorCancelledException {
        rethrow;
      } on NetworkDoctorTimeoutException {
        rethrow;
      } on Object {
        sampleStopwatch.stop();
        samples.add(null);
      } finally {
        await socket?.close();
      }

      if (index + 1 < sampleCount && sampleInterval > Duration.zero) {
        await cancellation.guard(Future<void>.delayed(sampleInterval));
      }
    }

    totalStopwatch.stop();
    final result = calculateNetworkQuality(
      host: host,
      port: port,
      samples: samples,
    );
    final success = result.successfulSamples > 0;
    return NetworkQualityProbeOutcome(
      result: result,
      probe: NetworkProbeResult(
        name: 'networkQuality',
        status: success ? ProbeStatus.success : ProbeStatus.failure,
        duration: totalStopwatch.elapsed,
        message: success
            ? 'TCP connection quality samples collected.'
            : 'Every TCP connection quality sample failed.',
        errorCode: success ? null : NetworkProbeErrorCode.connection,
        metadata: result.toJson(),
      ),
    );
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

  static GatewayProbeOutcome _reachableGatewayOutcome({
    required String address,
    required List<int> testedPorts,
    required Duration duration,
    required String message,
  }) {
    final result = GatewayReachabilityResult(
      address: address,
      testedPorts: testedPorts,
      reachability: GatewayReachability.reachable,
      duration: duration,
    );
    return GatewayProbeOutcome(
      result: result,
      probe: NetworkProbeResult(
        name: 'gateway',
        status: ProbeStatus.success,
        duration: duration,
        message: message,
        metadata: result.toJson(),
      ),
    );
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
