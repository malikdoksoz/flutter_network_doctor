import 'dart:async';
import 'dart:io';

import '../models.dart';
import 'platform_probe_interface.dart';

/// `dart:io` implementation of lower-level network probes.
final class PlatformNetworkProbeImpl implements PlatformNetworkProbe {
  @override
  Future<NetworkProbeResult> dns(String host, Duration timeout) async {
    final stopwatch = Stopwatch()..start();
    try {
      final addresses = await InternetAddress.lookup(host).timeout(timeout);
      stopwatch.stop();
      return NetworkProbeResult(
        name: 'dns',
        status: addresses.isEmpty ? ProbeStatus.failure : ProbeStatus.success,
        duration: stopwatch.elapsed,
        message: addresses.isEmpty
            ? 'No DNS records returned.'
            : 'DNS resolved.',
        metadata: <String, Object?>{
          'host': host,
          'addresses': addresses.map((InternetAddress e) => e.address).toList(),
        },
      );
    } on Object catch (error) {
      stopwatch.stop();
      return NetworkProbeResult(
        name: 'dns',
        status: ProbeStatus.failure,
        duration: stopwatch.elapsed,
        message: error.toString(),
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
  ) async {
    final stopwatch = Stopwatch()..start();
    Socket? socket;
    try {
      socket = await Socket.connect(address, port, timeout: timeout);
      stopwatch.stop();
      return NetworkProbeResult(
        name: name,
        status: ProbeStatus.success,
        duration: stopwatch.elapsed,
        message: 'Route verified with a TCP connection.',
        metadata: <String, Object?>{'address': address, 'port': port},
      );
    } on Object catch (error) {
      stopwatch.stop();
      return NetworkProbeResult(
        name: name,
        status: ProbeStatus.failure,
        duration: stopwatch.elapsed,
        message: error.toString(),
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
  ) async {
    final stopwatch = Stopwatch()..start();
    Socket? socket;
    try {
      socket = await Socket.connect(host, port, timeout: timeout);
      stopwatch.stop();
      return NetworkProbeResult(
        name: 'tcp',
        status: ProbeStatus.success,
        duration: stopwatch.elapsed,
        message: 'TCP connection established.',
        metadata: <String, Object?>{'host': host, 'port': port},
      );
    } on Object catch (error) {
      stopwatch.stop();
      return NetworkProbeResult(
        name: 'tcp',
        status: ProbeStatus.failure,
        duration: stopwatch.elapsed,
        message: error.toString(),
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
  ) async {
    final stopwatch = Stopwatch()..start();
    SecureSocket? socket;
    try {
      socket = await SecureSocket.connect(host, port, timeout: timeout);
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
    } on Object catch (error) {
      stopwatch.stop();
      return NetworkProbeResult(
        name: 'tls',
        status: ProbeStatus.failure,
        duration: stopwatch.elapsed,
        message: error.toString(),
        metadata: <String, Object?>{'host': host, 'port': port},
      );
    } finally {
      await socket?.close();
    }
  }
}
