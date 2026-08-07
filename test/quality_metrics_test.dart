import 'package:flutter_network_doctor/flutter_network_doctor.dart';
import 'package:flutter_network_doctor/src/quality_metrics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('quality metrics retain failures and calculate ordered statistics', () {
    final result = calculateNetworkQuality(
      host: 'quality.example',
      port: 443,
      samples: const <Duration?>[
        Duration(milliseconds: 10),
        Duration(milliseconds: 20),
        null,
        Duration(milliseconds: 40),
        Duration(milliseconds: 30),
      ],
    );

    expect(result.method, NetworkQualityMeasurementMethod.tcpConnect);
    expect(result.sampleCount, 5);
    expect(result.successfulSamples, 4);
    expect(result.failedSamples, 1);
    expect(result.packetLossPercent, 20);
    expect(result.minimumLatencyMs, 10);
    expect(result.averageLatencyMs, 25);
    expect(result.p95LatencyMs, 40);
    expect(result.maximumLatencyMs, 40);
    expect(result.jitterMs, closeTo(40 / 3, 0.0001));
    expect(result.samplesMs, <double?>[10, 20, null, 40, 30]);
  });

  test('quality metrics represent a completely unreachable target', () {
    final result = calculateNetworkQuality(
      host: 'quality.example',
      port: 443,
      samples: const <Duration?>[null, null, null],
    );

    expect(result.packetLossPercent, 100);
    expect(result.successfulSamples, 0);
    expect(result.minimumLatencyMs, isNull);
    expect(result.averageLatencyMs, isNull);
    expect(result.p95LatencyMs, isNull);
    expect(result.maximumLatencyMs, isNull);
    expect(result.jitterMs, isNull);
  });

  test('quality metrics reject an empty sample set', () {
    expect(
      () => calculateNetworkQuality(
        host: 'quality.example',
        port: 443,
        samples: const <Duration?>[],
      ),
      throwsArgumentError,
    );
  });

  test('connection refusal codes cover supported desktop and mobile OSes', () {
    expect(isConnectionRefusedErrorCode(61), isTrue);
    expect(isConnectionRefusedErrorCode(111), isTrue);
    expect(isConnectionRefusedErrorCode(10061), isTrue);
    expect(isConnectionRefusedErrorCode(null), isFalse);
    expect(isConnectionRefusedErrorCode(65), isFalse);
  });
}
