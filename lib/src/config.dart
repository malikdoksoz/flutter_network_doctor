/// Configuration for a network diagnostic run.
final class NetworkDoctorConfig {
  /// Creates a configuration.
  NetworkDoctorConfig({
    List<Uri>? internetEndpoints,
    List<int>? gatewayPorts,
    this.timeout = const Duration(seconds: 4),
    this.overallTimeout = const Duration(seconds: 15),
    this.dnsHost = 'example.com',
    this.tcpHost = '1.1.1.1',
    this.tcpPort = 443,
    this.tlsHost = 'cloudflare.com',
    this.tlsPort = 443,
    this.ipv4Host = '1.1.1.1',
    this.ipv6Host = '2606:4700:4700::1111',
    this.minimumInternetSuccesses = 1,
    this.includeWifiInfo = true,
    this.includeDnsProbe = true,
    this.includeTcpProbe = true,
    this.includeTlsProbe = true,
    this.includeIpVersionProbes = true,
    this.includePlatformInfo = true,
    this.includeGatewayProbe = false,
    this.gatewayProbeTimeout = const Duration(milliseconds: 750),
    this.includeNetworkQualityProbe = false,
    this.networkQualityHost = '1.1.1.1',
    this.networkQualityPort = 443,
    this.networkQualitySampleCount = 5,
    this.networkQualitySampleTimeout = const Duration(seconds: 1),
    this.networkQualitySampleInterval = const Duration(milliseconds: 100),
    this.healthPolicy = NetworkHealthPolicy.balanced,
  }) : internetEndpoints = List<Uri>.unmodifiable(
         internetEndpoints ??
             <Uri>[Uri.https('one.one.one.one'), Uri.https('icanhazip.com')],
       ),
       gatewayPorts = List<int>.unmodifiable(
         gatewayPorts ?? <int>[53, 80, 443],
       ) {
    if (this.internetEndpoints.isEmpty) {
      throw ArgumentError.value(
        this.internetEndpoints,
        'internetEndpoints',
        'At least one endpoint is required.',
      );
    }
    for (final endpoint in this.internetEndpoints) {
      if (!endpoint.hasScheme ||
          !endpoint.hasAuthority ||
          (endpoint.scheme != 'http' && endpoint.scheme != 'https')) {
        throw ArgumentError.value(
          endpoint,
          'internetEndpoints',
          'Every endpoint must be an absolute HTTP or HTTPS URI.',
        );
      }
    }
    if (timeout <= Duration.zero) {
      throw ArgumentError.value(
        timeout,
        'timeout',
        'Must be greater than zero.',
      );
    }
    if (overallTimeout <= Duration.zero) {
      throw ArgumentError.value(
        overallTimeout,
        'overallTimeout',
        'Must be greater than zero.',
      );
    }
    if (gatewayProbeTimeout <= Duration.zero) {
      throw ArgumentError.value(
        gatewayProbeTimeout,
        'gatewayProbeTimeout',
        'Must be greater than zero.',
      );
    }
    if (this.gatewayPorts.isEmpty) {
      throw ArgumentError.value(
        this.gatewayPorts,
        'gatewayPorts',
        'At least one gateway port is required.',
      );
    }
    for (final port in this.gatewayPorts) {
      _validatePort(port, 'gatewayPorts');
    }
    if (minimumInternetSuccesses < 1 ||
        minimumInternetSuccesses > this.internetEndpoints.length) {
      throw ArgumentError.value(
        minimumInternetSuccesses,
        'minimumInternetSuccesses',
        'Must be between 1 and internetEndpoints.length.',
      );
    }
    _validatePort(tcpPort, 'tcpPort');
    _validatePort(tlsPort, 'tlsPort');
    _validatePort(networkQualityPort, 'networkQualityPort');
    if (networkQualitySampleCount < 2 || networkQualitySampleCount > 20) {
      throw ArgumentError.value(
        networkQualitySampleCount,
        'networkQualitySampleCount',
        'Must be between 2 and 20.',
      );
    }
    if (networkQualitySampleTimeout <= Duration.zero) {
      throw ArgumentError.value(
        networkQualitySampleTimeout,
        'networkQualitySampleTimeout',
        'Must be greater than zero.',
      );
    }
    if (networkQualitySampleInterval < Duration.zero) {
      throw ArgumentError.value(
        networkQualitySampleInterval,
        'networkQualitySampleInterval',
        'Must not be negative.',
      );
    }
    _validateHost(dnsHost, 'dnsHost');
    _validateHost(tcpHost, 'tcpHost');
    _validateHost(tlsHost, 'tlsHost');
    _validateHost(ipv4Host, 'ipv4Host');
    _validateHost(ipv6Host, 'ipv6Host');
    _validateHost(networkQualityHost, 'networkQualityHost');
  }

  static void _validateHost(String value, String name) {
    if (value.trim().isEmpty) {
      throw ArgumentError.value(value, name, 'Must not be empty.');
    }
  }

  static void _validatePort(int value, String name) {
    if (value < 1 || value > 65535) {
      throw ArgumentError.value(value, name, 'Invalid TCP port.');
    }
  }

  /// Endpoints used to verify real internet reachability.
  final List<Uri> internetEndpoints;

  /// TCP ports attempted when checking local gateway reachability.
  final List<int> gatewayPorts;

  /// Timeout applied to each individual probe.
  final Duration timeout;

  /// Maximum duration of the complete diagnostic run.
  final Duration overallTimeout;

  /// Host used for the DNS resolution probe.
  final String dnsHost;

  /// Host used for the TCP connection probe.
  final String tcpHost;

  /// Port used for the TCP connection probe.
  final int tcpPort;

  /// Host used for the TLS connection probe.
  final String tlsHost;

  /// Port used for the TLS connection probe.
  final int tlsPort;

  /// IPv4 address used to verify IPv4 routing.
  final String ipv4Host;

  /// IPv6 address used to verify IPv6 routing.
  final String ipv6Host;

  /// Number of successful HTTP probes required to consider internet available.
  final int minimumInternetSuccesses;

  /// Whether Wi-Fi/LAN metadata should be collected when supported.
  final bool includeWifiInfo;

  /// Whether to run a DNS lookup probe.
  final bool includeDnsProbe;

  /// Whether to run a TCP connection probe.
  final bool includeTcpProbe;

  /// Whether to run a TLS connection probe.
  final bool includeTlsProbe;

  /// Whether to probe IPv4 and IPv6 routing separately.
  final bool includeIpVersionProbes;

  /// Whether native platform network metadata should be collected.
  final bool includePlatformInfo;

  /// Whether to test the local Wi-Fi gateway with short TCP attempts.
  ///
  /// Disabled by default because it adds local-network traffic and can require
  /// host-application permission on newer operating systems.
  final bool includeGatewayProbe;

  /// Timeout applied to each gateway port attempt.
  final Duration gatewayProbeTimeout;

  /// Whether to collect repeated TCP connection quality samples.
  ///
  /// Disabled by default because it adds network traffic and diagnostic time.
  final bool includeNetworkQualityProbe;

  /// Host used for repeated TCP quality samples.
  final String networkQualityHost;

  /// Port used for repeated TCP quality samples.
  final int networkQualityPort;

  /// Number of repeated quality samples, from 2 to 20.
  final int networkQualitySampleCount;

  /// Timeout applied to each quality sample.
  final Duration networkQualitySampleTimeout;

  /// Delay between consecutive quality samples.
  final Duration networkQualitySampleInterval;

  /// Policy used to derive the overall [NetworkHealth] value.
  final NetworkHealthPolicy healthPolicy;
}

/// Controls which failed probes degrade an otherwise reachable network.
enum NetworkHealthPolicy {
  /// DNS, TCP, and TLS failures degrade health; IP-version and redundant HTTP
  /// endpoint failures remain informational.
  balanced,

  /// Every supported and enabled probe must succeed.
  strict,

  /// Only the configured HTTP reachability quorum affects overall health.
  internetOnly,
}
