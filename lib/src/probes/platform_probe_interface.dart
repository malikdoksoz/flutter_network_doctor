import '../models.dart';
import '../run_cancellation.dart';

/// Gateway probe data and its generic probe representation.
final class GatewayProbeOutcome {
  /// Creates a gateway probe outcome.
  const GatewayProbeOutcome({required this.probe, this.result});

  /// Generic probe result included in the report probe list.
  final NetworkProbeResult probe;

  /// Structured gateway result, when a gateway could be tested.
  final GatewayReachabilityResult? result;
}

/// Network quality data and its generic probe representation.
final class NetworkQualityProbeOutcome {
  /// Creates a network quality probe outcome.
  const NetworkQualityProbeOutcome({required this.probe, this.result});

  /// Generic probe result included in the report probe list.
  final NetworkProbeResult probe;

  /// Structured quality metrics, when sampling is supported.
  final NetworkQualityResult? result;
}

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

  /// Tests whether [address] responds at the TCP network layer.
  Future<GatewayProbeOutcome> gateway(
    String? address,
    List<int> ports,
    Duration timeout,
    NetworkDoctorRunCancellation cancellation,
  );

  /// Collects repeated TCP connection samples for quality metrics.
  Future<NetworkQualityProbeOutcome> networkQuality(
    String host,
    int port,
    int sampleCount,
    Duration sampleTimeout,
    Duration sampleInterval,
    NetworkDoctorRunCancellation cancellation,
  );
}
