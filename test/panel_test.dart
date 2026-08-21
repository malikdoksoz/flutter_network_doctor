import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_network_doctor/flutter_network_doctor.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_connectivity.dart';
import 'monitor_harness.dart';

/// Configuration that keeps a panel run to mocked HTTP endpoints only.
NetworkDoctorConfig panelConfig() => NetworkDoctorConfig(
  internetEndpoints: <Uri>[Uri.https('probe.example')],
  timeout: const Duration(milliseconds: 400),
  overallTimeout: const Duration(seconds: 5),
  includeWifiInfo: false,
  includeDnsProbe: false,
  includeTcpProbe: false,
  includeTlsProbe: false,
  includeIpVersionProbes: false,
  includePlatformInfo: false,
);

/// A complete report, used to exercise rendering without running a diagnosis.
NetworkDoctorReport buildReport() => NetworkDoctorReport(
  generatedAt: DateTime.utc(2026, 8, 21, 12),
  transports: const <NetworkTransport>[NetworkTransport.wifi],
  hasInternet: true,
  health: NetworkHealth.healthy,
  probes: const <NetworkProbeResult>[
    NetworkProbeResult(
      name: 'http:probe.example',
      status: ProbeStatus.success,
      duration: Duration(milliseconds: 12),
      message: 'HTTP endpoint reachable.',
    ),
  ],
  ipv4Available: true,
  ipv6Available: false,
  totalDuration: const Duration(milliseconds: 40),
  wifi: const WifiNetworkInfo(
    ssid: 'Office Wi-Fi',
    bssid: 'aa:bb:cc:dd:ee:ff',
    ipv4: '192.168.1.20',
    gateway: '192.168.1.1',
  ),
  platform: const PlatformNetworkInfo(
    dnsServers: <String>['192.168.1.1'],
    interfaceName: 'en0',
    mtu: 1500,
    isMetered: false,
    pathStatus: NetworkPathStatus.satisfied,
  ),
  gatewayReachability: GatewayReachabilityResult(
    address: '192.168.1.1',
    testedPorts: const <int>[53, 443],
    reachability: GatewayReachability.reachable,
    duration: const Duration(milliseconds: 8),
  ),
  networkQuality: NetworkQualityResult(
    method: NetworkQualityMeasurementMethod.tcpConnect,
    targetHost: '1.1.1.1',
    targetPort: 443,
    sampleCount: 5,
    successfulSamples: 5,
    failedSamples: 0,
    packetLossPercent: 0,
    samplesMs: const <double?>[10, 11, 12, 13, 14],
    minimumLatencyMs: 10,
    averageLatencyMs: 12,
    p95LatencyMs: 14,
    maximumLatencyMs: 14,
    jitterMs: 1,
  ),
);

Future<void> pumpPanel(WidgetTester tester, Widget panel) =>
    tester.pumpWidget(MaterialApp(home: Scaffold(body: panel)));

/// Records platform channel calls so clipboard writes can be inspected.
List<MethodCall> recordPlatformCalls(WidgetTester tester) {
  final calls = <MethodCall>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (MethodCall call) async {
      calls.add(call);
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return calls;
}

void main() {
  testWidgets('runs a diagnosis on start and renders its result', (
    WidgetTester tester,
  ) async {
    installFakeConnectivity(addTearDown);
    final endpoints = FakeEndpoints();
    final doctor = FlutterNetworkDoctor(httpClient: endpoints.client());
    addTearDown(doctor.dispose);

    await pumpPanel(
      tester,
      NetworkDoctorPanel(doctor: doctor, config: panelConfig()),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(endpoints.requests, 1);
    // The health chip and the summary row both report the classification.
    expect(find.text('healthy'), findsNWidgets(2));
    expect(find.textContaining('http:probe.example'), findsOneWidget);
  });

  testWidgets('waits for the run action when runOnStart is disabled', (
    WidgetTester tester,
  ) async {
    installFakeConnectivity(addTearDown);
    final endpoints = FakeEndpoints();
    final doctor = FlutterNetworkDoctor(httpClient: endpoints.client());
    addTearDown(doctor.dispose);

    await pumpPanel(
      tester,
      NetworkDoctorPanel(
        doctor: doctor,
        config: panelConfig(),
        runOnStart: false,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No report yet.'), findsOneWidget);
    expect(endpoints.requests, 0);

    await tester.tap(find.text('Run diagnostics'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(endpoints.requests, 1);
    expect(find.text('No report yet.'), findsNothing);
    expect(find.text('healthy'), findsNWidgets(2));
  });

  testWidgets('renders every section of a complete report', (
    WidgetTester tester,
  ) async {
    final doctor = FlutterNetworkDoctor(httpClient: FakeEndpoints().client());
    addTearDown(doctor.dispose);

    await pumpPanel(
      tester,
      NetworkDoctorPanel(
        doctor: doctor,
        initialReport: buildReport(),
        runOnStart: false,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Summary'), findsOneWidget);
    expect(find.text('Wi-Fi and LAN'), findsOneWidget);
    expect(find.text('Platform'), findsOneWidget);
    // The section heading and the Wi-Fi gateway row share this label.
    expect(find.text('Gateway'), findsNWidgets(2));
    expect(find.text('Connection quality'), findsOneWidget);
    expect(find.text('Probes'), findsOneWidget);
    expect(find.text('Office Wi-Fi'), findsOneWidget);
    expect(find.text('reachable'), findsOneWidget);
    expect(find.text('12.0 ms'), findsOneWidget);
  });

  testWidgets('copies a redacted report to the clipboard', (
    WidgetTester tester,
  ) async {
    final calls = recordPlatformCalls(tester);
    final doctor = FlutterNetworkDoctor(httpClient: FakeEndpoints().client());
    addTearDown(doctor.dispose);

    await pumpPanel(
      tester,
      NetworkDoctorPanel(
        doctor: doctor,
        initialReport: buildReport(),
        runOnStart: false,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Copy report'));
    await tester.pumpAndSettle();

    final clipboardCall = calls.firstWhere(
      (MethodCall call) => call.method == 'Clipboard.setData',
    );
    final text =
        (clipboardCall.arguments as Map<Object?, Object?>)['text']! as String;
    expect(text, contains('"health": "healthy"'));
    expect(text, isNot(contains('Office Wi-Fi')));
    expect(text, isNot(contains('192.168.1.1')));
    expect(text, contains('<redacted>'));
    expect(find.text('Copied'), findsOneWidget);
  });

  testWidgets('shares the report JSON without redaction when asked', (
    WidgetTester tester,
  ) async {
    String? shared;
    final doctor = FlutterNetworkDoctor(httpClient: FakeEndpoints().client());
    addTearDown(doctor.dispose);

    await pumpPanel(
      tester,
      NetworkDoctorPanel(
        doctor: doctor,
        initialReport: buildReport(),
        runOnStart: false,
        redactWifiIdentifiers: false,
        redactNetworkAddresses: false,
        onShare: (String json) => shared = json,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Share report'));
    await tester.pumpAndSettle();

    expect(shared, isNotNull);
    expect(shared, contains('Office Wi-Fi'));
    expect(shared, contains('192.168.1.1'));
  });
}
