import 'dart:math' as math;

import 'models.dart';

/// Builds public quality metrics from ordered TCP sample durations.
NetworkQualityResult calculateNetworkQuality({
  required String host,
  required int port,
  required List<Duration?> samples,
}) {
  if (samples.isEmpty) {
    throw ArgumentError.value(samples, 'samples', 'Must not be empty.');
  }

  final samplesMs = samples
      .map((Duration? value) => value == null ? null : _milliseconds(value))
      .toList(growable: false);
  final successful = samplesMs.whereType<double>().toList(growable: false);
  final sorted = List<double>.of(successful)..sort();
  final failedSamples = samples.length - successful.length;

  double? minimum;
  double? average;
  double? p95;
  double? maximum;
  double? jitter;
  if (sorted.isNotEmpty) {
    minimum = sorted.first;
    maximum = sorted.last;
    average =
        successful.reduce((double a, double b) => a + b) / successful.length;
    final p95Index = math.max(0, (sorted.length * 0.95).ceil() - 1);
    p95 = sorted[p95Index];

    if (successful.length == 1) {
      jitter = 0;
    } else {
      var totalVariation = 0.0;
      for (var index = 1; index < successful.length; index += 1) {
        totalVariation += (successful[index] - successful[index - 1]).abs();
      }
      jitter = totalVariation / (successful.length - 1);
    }
  }

  return NetworkQualityResult(
    method: NetworkQualityMeasurementMethod.tcpConnect,
    targetHost: host,
    targetPort: port,
    sampleCount: samples.length,
    successfulSamples: successful.length,
    failedSamples: failedSamples,
    packetLossPercent: failedSamples * 100 / samples.length,
    minimumLatencyMs: minimum,
    averageLatencyMs: average,
    p95LatencyMs: p95,
    maximumLatencyMs: maximum,
    jitterMs: jitter,
    samplesMs: samplesMs,
  );
}

double _milliseconds(Duration duration) => duration.inMicroseconds / 1000;

/// Whether an operating-system error code represents an active TCP refusal.
///
/// A refusal proves that the target host was reached even though the selected
/// service port was closed.
bool isConnectionRefusedErrorCode(int? code) =>
    code == 61 || code == 111 || code == 10061;
