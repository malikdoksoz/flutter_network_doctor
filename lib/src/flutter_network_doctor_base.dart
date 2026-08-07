import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:network_info_plus/network_info_plus.dart';

import 'config.dart';
import 'models.dart';
import 'probes/platform_probe.dart';

/// Runs a structured set of network diagnostics and returns one report.
final class FlutterNetworkDoctor {
  /// Creates a network doctor.
  ///
  /// Supplying an [httpClient] is useful when the host application has custom
  /// proxy, certificate, or testing requirements. The client remains owned by
  /// the caller and is never closed by this class.
  FlutterNetworkDoctor({http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client(),
      _ownsHttpClient = httpClient == null,
      _connectivity = Connectivity(),
      _networkInfo = NetworkInfo(),
      _platformProbe = createPlatformNetworkProbe();

  final http.Client _httpClient;
  final bool _ownsHttpClient;
  final Connectivity _connectivity;
  final NetworkInfo _networkInfo;
  final PlatformNetworkProbe _platformProbe;

  /// Runs all enabled checks and produces a single immutable report.
  Future<NetworkDoctorReport> diagnose({NetworkDoctorConfig? config}) async {
    final effectiveConfig = config ?? NetworkDoctorConfig();

    final connectivityResults = await _safeConnectivityCheck();
    final transportSet = connectivityResults.map(_mapTransport).toSet();
    if (transportSet.length > 1) {
      transportSet.remove(NetworkTransport.none);
    }
    final transports = List<NetworkTransport>.unmodifiable(transportSet);

    final wifi = effectiveConfig.includeWifiInfo
        ? await _collectWifiInfo()
        : null;

    final probeFutures = <Future<NetworkProbeResult>>[];

    for (final endpoint in effectiveConfig.internetEndpoints) {
      probeFutures.add(_httpProbe(endpoint, effectiveConfig.timeout));
    }

    if (effectiveConfig.includeDnsProbe) {
      probeFutures.add(
        _platformProbe.dns(effectiveConfig.dnsHost, effectiveConfig.timeout),
      );
    }
    if (effectiveConfig.includeTcpProbe) {
      probeFutures.add(
        _platformProbe.tcp(
          effectiveConfig.tcpHost,
          effectiveConfig.tcpPort,
          effectiveConfig.timeout,
        ),
      );
    }
    if (effectiveConfig.includeTlsProbe) {
      probeFutures.add(
        _platformProbe.tls(
          effectiveConfig.tlsHost,
          effectiveConfig.tlsPort,
          effectiveConfig.timeout,
        ),
      );
    }
    if (effectiveConfig.includeIpVersionProbes) {
      probeFutures
        ..add(
          _platformProbe.ipRoute(
            'ipv4',
            effectiveConfig.ipv4Host,
            443,
            effectiveConfig.timeout,
          ),
        )
        ..add(
          _platformProbe.ipRoute(
            'ipv6',
            effectiveConfig.ipv6Host,
            443,
            effectiveConfig.timeout,
          ),
        );
    }

    final probes = await Future.wait(probeFutures);
    final httpProbes = probes.where(
      (NetworkProbeResult result) => result.name.startsWith('http:'),
    );
    final successfulHttpProbes = httpProbes
        .where((NetworkProbeResult result) => result.isSuccess)
        .length;
    final hasInternet =
        successfulHttpProbes >= effectiveConfig.minimumInternetSuccesses;

    final ipv4Result = _findProbe(probes, 'ipv4');
    final ipv6Result = _findProbe(probes, 'ipv6');
    final captivePortalSuspected =
        !hasInternet &&
        httpProbes.any((NetworkProbeResult result) {
          final statusCode = result.metadata['statusCode'];
          final location = result.metadata['location'];
          return statusCode is int &&
              statusCode >= 300 &&
              statusCode < 400 &&
              location is String &&
              location.isNotEmpty;
        });

    final hasTransport = transports.any(
      (NetworkTransport transport) => transport != NetworkTransport.none,
    );

    final health = _evaluateHealth(
      hasTransport: hasTransport,
      hasInternet: hasInternet,
      probes: probes,
    );

    return NetworkDoctorReport(
      generatedAt: DateTime.now(),
      transports: transports,
      hasInternet: hasInternet,
      health: health,
      probes: List<NetworkProbeResult>.unmodifiable(probes),
      ipv4Available: ipv4Result?.isSuccess ?? false,
      ipv6Available: ipv6Result?.isSuccess ?? false,
      wifi: (wifi?.hasData ?? false) ? wifi : null,
      captivePortalSuspected: captivePortalSuspected,
    );
  }

  /// Releases resources owned by this instance.
  ///
  /// A caller-supplied HTTP client is never closed.
  void dispose() {
    if (_ownsHttpClient) {
      _httpClient.close();
    }
  }

  Future<List<ConnectivityResult>> _safeConnectivityCheck() async {
    try {
      return await _connectivity.checkConnectivity();
    } on Object {
      return const <ConnectivityResult>[ConnectivityResult.none];
    }
  }

  Future<WifiNetworkInfo?> _collectWifiInfo() async {
    if (kIsWeb) {
      return null;
    }

    final ssid = _normalizeSsid(await _safeWifiValue(_networkInfo.getWifiName));
    final bssid = await _safeWifiValue(_networkInfo.getWifiBSSID);
    final ipv4 = await _safeWifiValue(_networkInfo.getWifiIP);
    final ipv6 = await _safeWifiValue(_networkInfo.getWifiIPv6);
    final subnetMask = await _safeWifiValue(_networkInfo.getWifiSubmask);
    final broadcast = await _safeWifiValue(_networkInfo.getWifiBroadcast);
    final gateway = await _safeWifiValue(_networkInfo.getWifiGatewayIP);

    return WifiNetworkInfo(
      ssid: ssid,
      bssid: bssid,
      ipv4: ipv4,
      ipv6: ipv6,
      subnetMask: subnetMask,
      broadcast: broadcast,
      gateway: gateway,
    );
  }

  static Future<String?> _safeWifiValue(Future<String?> Function() read) async {
    try {
      return await read();
    } on Object {
      return null;
    }
  }

  Future<NetworkProbeResult> _httpProbe(Uri uri, Duration timeout) async {
    final stopwatch = Stopwatch()..start();
    try {
      final request = http.Request('GET', uri)
        ..followRedirects = false
        ..maxRedirects = 0;
      final response = await (() async {
        final streamedResponse = await _httpClient.send(request);
        await streamedResponse.stream.drain<void>();
        return streamedResponse;
      })().timeout(timeout);
      stopwatch.stop();

      final statusCode = response.statusCode;
      final success = statusCode >= 200 && statusCode < 300;
      return NetworkProbeResult(
        name: 'http:${uri.host}',
        status: success ? ProbeStatus.success : ProbeStatus.failure,
        duration: stopwatch.elapsed,
        message: success
            ? 'HTTP endpoint reachable.'
            : 'Unexpected HTTP status $statusCode.',
        metadata: <String, Object?>{
          'uri': uri.toString(),
          'statusCode': statusCode,
          'location': response.headers['location'],
        },
      );
    } on Object catch (error) {
      stopwatch.stop();
      return NetworkProbeResult(
        name: 'http:${uri.host}',
        status: ProbeStatus.failure,
        duration: stopwatch.elapsed,
        message: error.toString(),
        metadata: <String, Object?>{'uri': uri.toString()},
      );
    }
  }

  static NetworkHealth _evaluateHealth({
    required bool hasTransport,
    required bool hasInternet,
    required List<NetworkProbeResult> probes,
  }) {
    if (!hasInternet) {
      return hasTransport ? NetworkHealth.localOnly : NetworkHealth.offline;
    }

    final relevant = probes.where(
      (NetworkProbeResult result) =>
          result.status != ProbeStatus.unsupported &&
          result.status != ProbeStatus.skipped,
    );
    if (relevant.any(
      (NetworkProbeResult result) => result.status == ProbeStatus.failure,
    )) {
      return NetworkHealth.degraded;
    }
    return NetworkHealth.healthy;
  }

  static NetworkProbeResult? _findProbe(
    List<NetworkProbeResult> probes,
    String name,
  ) {
    for (final probe in probes) {
      if (probe.name == name) {
        return probe;
      }
    }
    return null;
  }

  static NetworkTransport _mapTransport(ConnectivityResult result) =>
      switch (result) {
        ConnectivityResult.wifi => NetworkTransport.wifi,
        ConnectivityResult.mobile => NetworkTransport.mobile,
        ConnectivityResult.ethernet => NetworkTransport.ethernet,
        ConnectivityResult.vpn => NetworkTransport.vpn,
        ConnectivityResult.bluetooth => NetworkTransport.bluetooth,
        ConnectivityResult.satellite => NetworkTransport.satellite,
        ConnectivityResult.other => NetworkTransport.other,
        ConnectivityResult.none => NetworkTransport.none,
      };

  static String? _normalizeSsid(String? value) {
    if (value == null || value.length < 2) {
      return value;
    }
    if (value.startsWith('"') && value.endsWith('"')) {
      return value.substring(1, value.length - 1);
    }
    return value;
  }
}
