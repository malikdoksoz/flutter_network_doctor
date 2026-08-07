import '../models.dart';
import 'platform_probe_interface.dart';

/// Stub implementation used on platforms without `dart:io` sockets.
final class PlatformNetworkProbeImpl implements PlatformNetworkProbe {
  @override
  Future<NetworkProbeResult> dns(String host, Duration timeout) async =>
      NetworkProbeResult(
        name: 'dns',
        status: ProbeStatus.unsupported,
        message: 'Raw DNS timing is not supported on this platform.',
        metadata: <String, Object?>{'host': host},
      );

  @override
  Future<NetworkProbeResult> ipRoute(
    String name,
    String address,
    int port,
    Duration timeout,
  ) async => NetworkProbeResult(
    name: name,
    status: ProbeStatus.unsupported,
    message: 'Raw socket routing checks are not supported on this platform.',
    metadata: <String, Object?>{'address': address, 'port': port},
  );

  @override
  Future<NetworkProbeResult> tcp(
    String host,
    int port,
    Duration timeout,
  ) async => NetworkProbeResult(
    name: 'tcp',
    status: ProbeStatus.unsupported,
    message: 'Raw TCP timing is not supported on this platform.',
    metadata: <String, Object?>{'host': host, 'port': port},
  );

  @override
  Future<NetworkProbeResult> tls(
    String host,
    int port,
    Duration timeout,
  ) async => NetworkProbeResult(
    name: 'tls',
    status: ProbeStatus.unsupported,
    message: 'Raw TLS timing is not supported on this platform.',
    metadata: <String, Object?>{'host': host, 'port': port},
  );
}
