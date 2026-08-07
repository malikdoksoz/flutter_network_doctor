import 'dart:async';

import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:network_info_plus_platform_interface/network_info_plus_platform_interface.dart';

import 'cancellation.dart';
import 'config.dart';
import 'models.dart';
import 'native_network_probe.dart';
import 'probes/platform_probe.dart';
import 'run_cancellation.dart';

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
      _connectivity = const _ConnectivityReader(),
      _networkInfo = const _NetworkInfoReader(),
      _platformProbe = createPlatformNetworkProbe();

  final http.Client _httpClient;
  final bool _ownsHttpClient;
  final _ConnectivityReader _connectivity;
  final _NetworkInfoReader _networkInfo;
  final PlatformNetworkProbe _platformProbe;
  final NativeNetworkProbe _nativeNetworkProbe = const NativeNetworkProbe();

  /// Runs all enabled checks and produces a single immutable report.
  ///
  /// The run throws [NetworkDoctorCancelledException] when [cancellationToken]
  /// is cancelled and [NetworkDoctorTimeoutException] when the configured
  /// overall deadline is exceeded. Exceptions thrown by [onProgress] are
  /// ignored so observers cannot interrupt diagnostics accidentally.
  Future<NetworkDoctorReport> diagnose({
    NetworkDoctorConfig? config,
    NetworkDoctorCancellationToken? cancellationToken,
    NetworkDoctorProgressCallback? onProgress,
  }) async {
    final effectiveConfig = config ?? NetworkDoctorConfig();
    final totalProbes = _probeCount(effectiveConfig);
    final stopwatch = Stopwatch()..start();
    final cancellation = NetworkDoctorRunCancellation(
      overallTimeout: effectiveConfig.overallTimeout,
      externalToken: cancellationToken,
    );

    _emitProgress(
      onProgress,
      NetworkDoctorProgress(
        stage: NetworkDoctorProgressStage.starting,
        completedProbes: 0,
        totalProbes: totalProbes,
      ),
    );

    try {
      final report = await _diagnose(
        config: effectiveConfig,
        cancellation: cancellation,
        onProgress: onProgress,
        totalProbes: totalProbes,
        stopwatch: stopwatch,
      );
      _emitProgress(
        onProgress,
        NetworkDoctorProgress(
          stage: NetworkDoctorProgressStage.completed,
          completedProbes: totalProbes,
          totalProbes: totalProbes,
        ),
      );
      return report;
    } on Object {
      _emitProgress(
        onProgress,
        NetworkDoctorProgress(
          stage: NetworkDoctorProgressStage.failed,
          completedProbes: 0,
          totalProbes: totalProbes,
        ),
      );
      cancellation.throwIfCancelled();
      rethrow;
    } finally {
      stopwatch.stop();
      await cancellation.finish();
    }
  }

  Future<NetworkDoctorReport> _diagnose({
    required NetworkDoctorConfig config,
    required NetworkDoctorRunCancellation cancellation,
    required NetworkDoctorProgressCallback? onProgress,
    required int totalProbes,
    required Stopwatch stopwatch,
  }) async {
    _emitProgress(
      onProgress,
      NetworkDoctorProgress(
        stage: NetworkDoctorProgressStage.collectingContext,
        completedProbes: 0,
        totalProbes: totalProbes,
      ),
    );

    final connectivityFuture = _safeConnectivityCheck(
      config.timeout,
      cancellation,
    );
    final wifiFuture = config.includeWifiInfo
        ? _collectWifiInfo(config.timeout, cancellation)
        : Future<WifiNetworkInfo?>.value();
    final (connectivityResults, wifi) = await (
      connectivityFuture,
      wifiFuture,
    ).wait;

    final transportSet = connectivityResults.map(_mapTransport).toSet();
    if (transportSet.length > 1) {
      transportSet.remove(NetworkTransport.none);
    }
    final transports = List<NetworkTransport>.unmodifiable(transportSet);

    final probeFutures = <Future<NetworkProbeResult>>[];
    Future<NativeNetworkProbeOutcome>? nativeOutcomeFuture;
    Future<GatewayProbeOutcome>? gatewayOutcomeFuture;
    Future<NetworkQualityProbeOutcome>? networkQualityOutcomeFuture;

    for (final endpoint in config.internetEndpoints) {
      probeFutures.add(_httpProbe(endpoint, config.timeout, cancellation));
    }

    if (config.includeDnsProbe) {
      probeFutures.add(
        _platformProbe.dns(config.dnsHost, config.timeout, cancellation),
      );
    }
    if (config.includeTcpProbe) {
      probeFutures.add(
        _platformProbe.tcp(
          config.tcpHost,
          config.tcpPort,
          config.timeout,
          cancellation,
        ),
      );
    }
    if (config.includeTlsProbe) {
      probeFutures.add(
        _platformProbe.tls(
          config.tlsHost,
          config.tlsPort,
          config.timeout,
          cancellation,
        ),
      );
    }
    if (config.includeIpVersionProbes) {
      probeFutures
        ..add(
          _platformProbe.ipRoute(
            'ipv4',
            config.ipv4Host,
            443,
            config.timeout,
            cancellation,
          ),
        )
        ..add(
          _platformProbe.ipRoute(
            'ipv6',
            config.ipv6Host,
            443,
            config.timeout,
            cancellation,
          ),
        );
    }
    if (config.includePlatformInfo) {
      nativeOutcomeFuture = _nativeNetworkProbe.collect(
        config.timeout,
        cancellation,
      );
      probeFutures.add(
        nativeOutcomeFuture.then(
          (NativeNetworkProbeOutcome outcome) => outcome.probe,
        ),
      );
    }
    if (config.includeGatewayProbe) {
      gatewayOutcomeFuture = _platformProbe.gateway(
        wifi?.gateway,
        config.gatewayPorts,
        config.gatewayProbeTimeout,
        cancellation,
      );
      probeFutures.add(
        gatewayOutcomeFuture.then(
          (GatewayProbeOutcome outcome) => outcome.probe,
        ),
      );
    }
    if (config.includeNetworkQualityProbe) {
      networkQualityOutcomeFuture = _platformProbe.networkQuality(
        config.networkQualityHost,
        config.networkQualityPort,
        config.networkQualitySampleCount,
        config.networkQualitySampleTimeout,
        config.networkQualitySampleInterval,
        cancellation,
      );
      probeFutures.add(
        networkQualityOutcomeFuture.then(
          (NetworkQualityProbeOutcome outcome) => outcome.probe,
        ),
      );
    }

    var completedProbes = 0;
    final trackedProbes = probeFutures.map((Future<NetworkProbeResult> future) {
      return future.then((NetworkProbeResult result) {
        completedProbes += 1;
        _emitProgress(
          onProgress,
          NetworkDoctorProgress(
            stage: NetworkDoctorProgressStage.probing,
            completedProbes: completedProbes,
            totalProbes: totalProbes,
            latestProbe: result,
          ),
        );
        return result;
      });
    });

    final probes = await Future.wait(trackedProbes);
    final platformInfo = (await nativeOutcomeFuture)?.info;
    final gatewayReachability = (await gatewayOutcomeFuture)?.result;
    final networkQuality = (await networkQualityOutcomeFuture)?.result;
    final httpProbes = probes.where(
      (NetworkProbeResult result) => result.name.startsWith('http:'),
    );
    final successfulHttpProbes = httpProbes
        .where((NetworkProbeResult result) => result.isSuccess)
        .length;
    final hasInternet = successfulHttpProbes >= config.minimumInternetSuccesses;

    final ipv4Result = _findProbe(probes, 'ipv4');
    final ipv6Result = _findProbe(probes, 'ipv6');
    final captivePortalSuspected =
        (platformInfo?.captivePortalDetected ?? false) ||
        (!hasInternet &&
            httpProbes.any((NetworkProbeResult result) {
              final statusCode = result.metadata['statusCode'];
              final location = result.metadata['location'];
              return statusCode is int &&
                  statusCode >= 300 &&
                  statusCode < 400 &&
                  location is String &&
                  location.isNotEmpty;
            }));

    final hasTransport = transports.any(
      (NetworkTransport transport) => transport != NetworkTransport.none,
    );
    final health = _evaluateHealth(
      hasTransport: hasTransport,
      hasInternet: hasInternet,
      captivePortalSuspected: captivePortalSuspected,
      probes: probes,
      policy: config.healthPolicy,
    );

    stopwatch.stop();
    return NetworkDoctorReport(
      generatedAt: DateTime.now(),
      transports: transports,
      hasInternet: hasInternet,
      health: health,
      probes: List<NetworkProbeResult>.unmodifiable(probes),
      ipv4Available:
          ipv4Result?.isSuccess ?? platformInfo?.supportsIpv4 ?? false,
      ipv6Available:
          ipv6Result?.isSuccess ?? platformInfo?.supportsIpv6 ?? false,
      totalDuration: stopwatch.elapsed,
      wifi: (wifi?.hasData ?? false) ? wifi : null,
      platform: platformInfo,
      gatewayReachability: gatewayReachability,
      networkQuality: networkQuality,
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

  Future<List<ConnectivityResult>> _safeConnectivityCheck(
    Duration timeout,
    NetworkDoctorRunCancellation cancellation,
  ) async {
    try {
      return await cancellation.guard(
        _connectivity.checkConnectivity().timeout(timeout),
      );
    } on NetworkDoctorCancelledException {
      rethrow;
    } on NetworkDoctorTimeoutException {
      rethrow;
    } on Object {
      return const <ConnectivityResult>[ConnectivityResult.none];
    }
  }

  Future<WifiNetworkInfo?> _collectWifiInfo(
    Duration timeout,
    NetworkDoctorRunCancellation cancellation,
  ) async {
    if (kIsWeb) {
      return null;
    }

    final reads = <Future<String?>>[
      _safeWifiValue(_networkInfo.getWifiName, timeout, cancellation),
      _safeWifiValue(_networkInfo.getWifiBSSID, timeout, cancellation),
      _safeWifiValue(_networkInfo.getWifiIP, timeout, cancellation),
      _safeWifiValue(_networkInfo.getWifiIPv6, timeout, cancellation),
      _safeWifiValue(_networkInfo.getWifiSubmask, timeout, cancellation),
      _safeWifiValue(_networkInfo.getWifiBroadcast, timeout, cancellation),
      _safeWifiValue(_networkInfo.getWifiGatewayIP, timeout, cancellation),
    ];
    final values = await Future.wait(reads);

    return WifiNetworkInfo(
      ssid: _normalizeSsid(values[0]),
      bssid: values[1],
      ipv4: values[2],
      ipv6: values[3],
      subnetMask: values[4],
      broadcast: values[5],
      gateway: values[6],
    );
  }

  static Future<String?> _safeWifiValue(
    Future<String?> Function() read,
    Duration timeout,
    NetworkDoctorRunCancellation cancellation,
  ) async {
    try {
      return await cancellation.guard(read().timeout(timeout));
    } on NetworkDoctorCancelledException {
      rethrow;
    } on NetworkDoctorTimeoutException {
      rethrow;
    } on Object {
      return null;
    }
  }

  Future<NetworkProbeResult> _httpProbe(
    Uri uri,
    Duration timeout,
    NetworkDoctorRunCancellation cancellation,
  ) async {
    final stopwatch = Stopwatch()..start();
    try {
      final individualAbort = Completer<void>();
      final request =
          http.AbortableRequest(
              'GET',
              uri,
              abortTrigger: Future.any<void>(<Future<void>>[
                cancellation.whenCancelled,
                individualAbort.future,
              ]),
            )
            ..followRedirects = false
            ..maxRedirects = 0;
      final response = await cancellation.guard(
        (() async {
          final streamedResponse = await _httpClient.send(request);
          await streamedResponse.stream.drain<void>();
          return streamedResponse;
        })().timeout(
          timeout,
          onTimeout: () {
            individualAbort.complete();
            throw TimeoutException('HTTP probe timed out.', timeout);
          },
        ),
      );
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
        errorCode: success ? null : NetworkProbeErrorCode.httpStatus,
        metadata: <String, Object?>{
          'uri': uri.toString(),
          'statusCode': statusCode,
          'location': response.headers['location'],
        },
      );
    } on NetworkDoctorCancelledException {
      rethrow;
    } on NetworkDoctorTimeoutException {
      rethrow;
    } on Object catch (error) {
      cancellation.throwIfCancelled();
      stopwatch.stop();
      return NetworkProbeResult(
        name: 'http:${uri.host}',
        status: ProbeStatus.failure,
        duration: stopwatch.elapsed,
        message: error.toString(),
        errorCode: error is TimeoutException
            ? NetworkProbeErrorCode.timeout
            : NetworkProbeErrorCode.connection,
        metadata: <String, Object?>{'uri': uri.toString()},
      );
    }
  }

  static NetworkHealth _evaluateHealth({
    required bool hasTransport,
    required bool hasInternet,
    required bool captivePortalSuspected,
    required List<NetworkProbeResult> probes,
    required NetworkHealthPolicy policy,
  }) {
    if (!hasInternet) {
      return hasTransport ? NetworkHealth.localOnly : NetworkHealth.offline;
    }
    if (captivePortalSuspected) {
      return NetworkHealth.degraded;
    }
    if (policy == NetworkHealthPolicy.internetOnly) {
      return NetworkHealth.healthy;
    }

    final relevant = probes.where((NetworkProbeResult result) {
      if (result.status == ProbeStatus.unsupported ||
          result.status == ProbeStatus.skipped) {
        return false;
      }
      if (policy == NetworkHealthPolicy.strict) {
        return true;
      }
      return result.name == 'dns' ||
          result.name == 'tcp' ||
          result.name == 'tls';
    });
    return relevant.any(
          (NetworkProbeResult result) => result.status == ProbeStatus.failure,
        )
        ? NetworkHealth.degraded
        : NetworkHealth.healthy;
  }

  static int _probeCount(NetworkDoctorConfig config) =>
      config.internetEndpoints.length +
      (config.includeDnsProbe ? 1 : 0) +
      (config.includeTcpProbe ? 1 : 0) +
      (config.includeTlsProbe ? 1 : 0) +
      (config.includeIpVersionProbes ? 2 : 0) +
      (config.includePlatformInfo ? 1 : 0) +
      (config.includeGatewayProbe ? 1 : 0) +
      (config.includeNetworkQualityProbe ? 1 : 0);

  static void _emitProgress(
    NetworkDoctorProgressCallback? callback,
    NetworkDoctorProgress progress,
  ) {
    try {
      callback?.call(progress);
    } on Object {
      // Progress observers must not change diagnostic behavior.
    }
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

/// Keeps platform-specific `network_info_plus` exports out of the package's
/// public import graph while preserving its registered plugin implementations.
final class _ConnectivityReader {
  const _ConnectivityReader();

  Future<List<ConnectivityResult>> checkConnectivity() =>
      ConnectivityPlatform.instance.checkConnectivity();
}

final class _NetworkInfoReader {
  const _NetworkInfoReader();

  Future<String?> getWifiName() => NetworkInfoPlatform.instance.getWifiName();

  Future<String?> getWifiBSSID() => NetworkInfoPlatform.instance.getWifiBSSID();

  Future<String?> getWifiIP() => NetworkInfoPlatform.instance.getWifiIP();

  Future<String?> getWifiIPv6() => NetworkInfoPlatform.instance.getWifiIPv6();

  Future<String?> getWifiSubmask() =>
      NetworkInfoPlatform.instance.getWifiSubmask();

  Future<String?> getWifiBroadcast() =>
      NetworkInfoPlatform.instance.getWifiBroadcast();

  Future<String?> getWifiGatewayIP() =>
      NetworkInfoPlatform.instance.getWifiGatewayIP();
}
