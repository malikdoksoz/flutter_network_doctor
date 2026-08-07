/// Configuration for a network diagnostic run.
final class NetworkDoctorConfig {
  /// Creates a configuration.
  NetworkDoctorConfig({
    List<Uri>? internetEndpoints,
    this.timeout = const Duration(seconds: 4),
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
  }) : internetEndpoints = List<Uri>.unmodifiable(
         internetEndpoints ??
             <Uri>[Uri.https('one.one.one.one'), Uri.https('icanhazip.com')],
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
    if (minimumInternetSuccesses < 1 ||
        minimumInternetSuccesses > this.internetEndpoints.length) {
      throw ArgumentError.value(
        minimumInternetSuccesses,
        'minimumInternetSuccesses',
        'Must be between 1 and internetEndpoints.length.',
      );
    }
    if (tcpPort < 1 || tcpPort > 65535) {
      throw ArgumentError.value(tcpPort, 'tcpPort', 'Invalid TCP port.');
    }
    if (tlsPort < 1 || tlsPort > 65535) {
      throw ArgumentError.value(tlsPort, 'tlsPort', 'Invalid TLS port.');
    }
    _validateHost(dnsHost, 'dnsHost');
    _validateHost(tcpHost, 'tcpHost');
    _validateHost(tlsHost, 'tlsHost');
    _validateHost(ipv4Host, 'ipv4Host');
    _validateHost(ipv6Host, 'ipv6Host');
  }

  static void _validateHost(String value, String name) {
    if (value.trim().isEmpty) {
      throw ArgumentError.value(value, name, 'Must not be empty.');
    }
  }

  /// Endpoints used to verify real internet reachability.
  final List<Uri> internetEndpoints;

  /// Timeout applied to each individual probe.
  final Duration timeout;

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
}
