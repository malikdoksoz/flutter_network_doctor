import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_network_doctor/flutter_network_doctor.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_connectivity.dart';
import 'monitor_harness.dart';

/// Pumps [banner] inside a minimal Material application.
Future<void> pumpBanner(WidgetTester tester, Widget banner) =>
    tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: <Widget>[
              banner,
              const Expanded(child: SizedBox()),
            ],
          ),
        ),
      ),
    );

/// Advances the connectivity settle delays, the monitor's asynchronous work,
/// and the banner's show/hide animation.
Future<void> settle(WidgetTester tester) async {
  // A check that observes no transport confirms it behind three settle delays,
  // and an escalation to a deep diagnosis repeats them, so the clock is
  // advanced generously before the animation is allowed to finish.
  for (var round = 0; round < 5; round++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
  await tester.pumpAndSettle();
}

// The monitors below are deliberately never disposed. Disposing one closes its
// broadcast status stream, and the done event of a stream whose listener was
// created inside the fake async zone of `testWidgets` can no longer be
// delivered once that zone stops running at tear-down. The harness
// configuration arms no periodic timer, so an undisposed monitor leaves nothing
// pending behind.

const String offlineMessage = 'No internet connection';
const String localOnlyMessage = 'Connected, but the internet is unreachable';
const String degradedMessage = 'Your connection is unstable';
const String recoveredMessage = 'Back online';

void main() {
  testWidgets('stays hidden while healthy and appears when the internet '
      'becomes unreachable', (WidgetTester tester) async {
    installFakeConnectivity(addTearDown);
    final endpoints = FakeEndpoints();
    final monitor = NetworkDoctorMonitor(
      config: monitorConfig(debounce: Duration.zero),
      httpClient: endpoints.client(),
    );
    await tester.runAsync(monitor.start);

    await pumpBanner(tester, NetworkDoctorBanner(monitor: monitor));
    await settle(tester);
    expect(find.text(localOnlyMessage), findsNothing);

    endpoints.statusCodes['probe.example'] = 500;
    await tester.runAsync(monitor.refresh);
    await settle(tester);

    expect(find.text(localOnlyMessage), findsOneWidget);
  });

  testWidgets('shows a recovery notice that disappears after its duration', (
    WidgetTester tester,
  ) async {
    installFakeConnectivity(addTearDown);
    final endpoints = FakeEndpoints()..statusCodes['probe.example'] = 500;
    final monitor = NetworkDoctorMonitor(
      config: monitorConfig(debounce: Duration.zero),
      httpClient: endpoints.client(),
    );
    await tester.runAsync(monitor.start);

    await pumpBanner(
      tester,
      NetworkDoctorBanner(
        monitor: monitor,
        recoveryDisplayDuration: const Duration(seconds: 3),
      ),
    );
    await settle(tester);
    expect(find.text(localOnlyMessage), findsOneWidget);

    endpoints.statusCodes['probe.example'] = 204;
    await tester.runAsync(monitor.refresh);
    await settle(tester);
    expect(find.text(recoveredMessage), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text(recoveredMessage), findsNothing);
  });

  testWidgets(
    'a degraded connection is shown only by the matching visibility',
    (WidgetTester tester) async {
      installFakeConnectivity(addTearDown);
      final endpoints = FakeEndpoints()..statusCodes['second.example'] = 500;
      final monitor = NetworkDoctorMonitor(
        config: monitorConfig(
          endpoints: <Uri>[
            Uri.https('probe.example'),
            Uri.https('second.example'),
          ],
          debounce: Duration.zero,
          checkPolicy: NetworkHealthPolicy.strict,
          // The deep run overrules the quick check, so it must classify the
          // failing endpoint the same way.
          deepPolicy: NetworkHealthPolicy.strict,
        ),
        httpClient: endpoints.client(),
      );
      await tester.runAsync(monitor.start);
      expect(monitor.currentStatus?.health, NetworkHealth.degraded);

      await pumpBanner(
        tester,
        NetworkDoctorBanner(
          monitor: monitor,
          visibility: NetworkBannerVisibility.whenOffline,
        ),
      );
      await settle(tester);
      expect(find.text(degradedMessage), findsNothing);

      await pumpBanner(tester, NetworkDoctorBanner(monitor: monitor));
      await settle(tester);
      expect(find.text(degradedMessage), findsOneWidget);
    },
  );

  testWidgets('the retry action refreshes the monitor', (
    WidgetTester tester,
  ) async {
    installFakeConnectivity(addTearDown);
    final endpoints = FakeEndpoints()..statusCodes['probe.example'] = 500;
    final monitor = NetworkDoctorMonitor(
      config: monitorConfig(debounce: Duration.zero),
      httpClient: endpoints.client(),
    );
    await tester.runAsync(monitor.start);

    await pumpBanner(tester, NetworkDoctorBanner(monitor: monitor));
    await settle(tester);
    final requestsBeforeRetry = endpoints.requests;

    await tester.tap(find.text('Retry'));
    await settle(tester);

    expect(endpoints.requests, greaterThan(requestsBeforeRetry));
  });

  testWidgets('creates and starts its own monitor when none is supplied', (
    WidgetTester tester,
  ) async {
    installFakeConnectivity(addTearDown, <ConnectivityResult>[
      ConnectivityResult.none,
    ]);

    await pumpBanner(
      tester,
      NetworkDoctorBanner(
        // Without a deep run the quick check's offline verdict stands, which
        // keeps this test free of any network traffic: an offline check never
        // issues a request.
        monitorConfig: monitorConfig(
          debounce: Duration.zero,
          runDeepDiagnosisOnFailure: false,
        ),
      ),
    );
    await settle(tester);

    expect(find.text(offlineMessage), findsOneWidget);

    // Removing the banner disposes the monitor it owns; a leaked timer or a
    // build after disposal fails the test.
    await tester.pumpWidget(const SizedBox.shrink());
    await settle(tester);
  });

  testWidgets('a custom builder replaces the default content', (
    WidgetTester tester,
  ) async {
    installFakeConnectivity(addTearDown, <ConnectivityResult>[
      ConnectivityResult.none,
    ]);
    final endpoints = FakeEndpoints();
    final monitor = NetworkDoctorMonitor(
      // A deep run would reach the fake endpoints, which answer regardless of
      // the reported transport, and overrule the offline quick check.
      config: monitorConfig(
        debounce: Duration.zero,
        runDeepDiagnosisOnFailure: false,
      ),
      httpClient: endpoints.client(),
    );
    await tester.runAsync(monitor.start);

    await pumpBanner(
      tester,
      NetworkDoctorBanner(
        monitor: monitor,
        builder: (BuildContext context, NetworkDoctorBannerData data) =>
            Text('custom ${data.health.name}'),
      ),
    );
    await settle(tester);

    expect(find.text('custom offline'), findsOneWidget);
    expect(find.text(offlineMessage), findsNothing);
  });
}
