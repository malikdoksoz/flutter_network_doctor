import '../models.dart';
import '../run_cancellation.dart';

/// Runs lower-level network probes supported by the current Dart platform.
abstract interface class PlatformNetworkProbe {
  /// Resolves [host] and records DNS lookup latency.
  Future<NetworkProbeResult> dns(
    String host,
    Duration timeout,
    NetworkDoctorRunCancellation cancellation,
  );

  /// Opens a TCP connection to [host]:[port].
  Future<NetworkProbeResult> tcp(
    String host,
    int port,
    Duration timeout,
    NetworkDoctorRunCancellation cancellation,
  );

  /// Opens a TLS connection to [host]:[port].
  Future<NetworkProbeResult> tls(
    String host,
    int port,
    Duration timeout,
    NetworkDoctorRunCancellation cancellation,
  );

  /// Verifies routing to a literal IP address and port.
  Future<NetworkProbeResult> ipRoute(
    String name,
    String address,
    int port,
    Duration timeout,
    NetworkDoctorRunCancellation cancellation,
  );
}
