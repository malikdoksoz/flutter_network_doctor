# flutter_network_doctor

[![CI](https://github.com/malikdoksoz/flutter_network_doctor/actions/workflows/ci.yml/badge.svg?branch=main&event=push&v=0.3.5)](https://github.com/malikdoksoz/flutter_network_doctor/actions/workflows/ci.yml)
[![pub package](https://img.shields.io/pub/v/flutter_network_doctor.svg)](https://pub.dev/packages/flutter_network_doctor)
[![pub points](https://img.shields.io/pub/points/flutter_network_doctor)](https://pub.dev/packages/flutter_network_doctor/score)
[![likes](https://img.shields.io/pub/likes/flutter_network_doctor)](https://pub.dev/packages/flutter_network_doctor/score)
[![publisher](https://img.shields.io/pub/publisher/flutter_network_doctor)](https://pub.dev/publishers/malikdoksoz.com)
[![license: MIT](https://img.shields.io/github/license/malikdoksoz/flutter_network_doctor)](LICENSE)

<p align="center">
  <img src="https://raw.githubusercontent.com/malikdoksoz/flutter_network_doctor/main/screenshots/banner.png" width="100%" alt="flutter_network_doctor — diagnose network issues, build better connections">
</p>

Production-grade network diagnostics for Flutter applications.

Instead of only answering “Wi-Fi or mobile?”, `flutter_network_doctor` builds a structured support report from operating-system connectivity state, real HTTP reachability, Wi-Fi/LAN metadata, DNS timing, TCP/TLS connection timing, and separate IPv4/IPv6 route checks.

## See it in action

<p align="center">
  <a href="https://raw.githubusercontent.com/malikdoksoz/flutter_network_doctor/main/screenshots/network-doctor-overview.png">
    <img src="https://raw.githubusercontent.com/malikdoksoz/flutter_network_doctor/main/screenshots/network-doctor-overview.png" width="240" alt="Network health and route overview">
  </a>
  <a href="https://raw.githubusercontent.com/malikdoksoz/flutter_network_doctor/main/screenshots/network-doctor-quality.png">
    <img src="https://raw.githubusercontent.com/malikdoksoz/flutter_network_doctor/main/screenshots/network-doctor-quality.png" width="240" alt="TCP quality and gateway measurements">
  </a>
  <a href="https://raw.githubusercontent.com/malikdoksoz/flutter_network_doctor/main/screenshots/network-doctor-support-json.png">
    <img src="https://raw.githubusercontent.com/malikdoksoz/flutter_network_doctor/main/screenshots/network-doctor-support-json.png" width="240" alt="Redacted JSON support report">
  </a>
</p>

The screenshots come from a real iOS Simulator diagnostic run. Network addresses are redacted; measured timings vary by device and connection.

## Features

- Active transport detection: Wi-Fi, mobile, Ethernet, VPN, Bluetooth, satellite, and other
- Real internet verification using a configurable quorum of HTTP endpoints
- Sub-second quick checks that produce no network traffic on a disconnected device
- Continuous monitoring with online, offline, transport-change, degraded, and recovered events
- Two-tier monitoring: cheap checks on every change, full diagnostics only when something breaks
- Ready-made Material connectivity banner and support panel widgets
- Wi-Fi/LAN metadata: SSID, BSSID, local IPv4/IPv6, subnet, broadcast, and gateway
- DNS lookup, TCP connection, and TLS handshake timing on `dart:io` platforms
- Separate IPv4 and IPv6 route checks
- Optional local-gateway reachability checks
- Optional TCP quality sampling with latency, jitter, and failed-sample rate
- Native DNS server, route, interface, MTU, proxy, and path characteristics
- Metered, expensive, constrained, validated, and captive-portal state where supported
- Android 17 local-network permission readiness
- Overall deadlines, cancellation, and progress callbacks
- Balanced, strict, and internet-only health policies
- Versioned JSON support reports with two levels of privacy redaction
- Web and WebAssembly-safe behavior: unavailable socket probes return
  `unsupported` instead of throwing
- No analytics, telemetry, or automatic permission prompts

## Requirements

- Flutter 3.38.1 or later
- Dart 3.10.0 or later, below Dart 4.0.0
- Android API 21 or later
- iOS 13.0 or later
- macOS 10.15 or later
- Java 17, Kotlin 2.2.0, Android Gradle Plugin 8.12.1 or later, and Gradle 8.13 or later for Android consumers

The effective platform minimums come from the package's current `network_info_plus` dependency.

## Quick start

```dart
import 'package:flutter_network_doctor/flutter_network_doctor.dart';

final doctor = FlutterNetworkDoctor();

try {
  final report = await doctor.diagnose();

  print(report.health);
  print(report.hasInternet);
  print(report.transports);
  print(report.wifi?.gateway);
  print(report.platform?.dnsServers);
  print(report.platform?.isMetered);

  final supportReport = report.toPrettyJson(
    redactWifiIdentifiers: true,
    redactNetworkAddresses: true,
  );
  print(supportReport);
} finally {
  doctor.dispose();
}
```

Call `dispose()` when the doctor is no longer needed. A caller-supplied `http.Client` remains owned by the caller and is not closed by the package.

## Customize probes

```dart
final report = await doctor.diagnose(
  config: NetworkDoctorConfig(
    timeout: const Duration(seconds: 3),
    overallTimeout: const Duration(seconds: 12),
    internetEndpoints: <Uri>[
      Uri.https('one.one.one.one'),
      Uri.https('icanhazip.com'),
    ],
    minimumInternetSuccesses: 1,
    dnsHost: 'example.com',
    tcpHost: '1.1.1.1',
    tcpPort: 443,
    tlsHost: 'cloudflare.com',
    tlsPort: 443,
    ipv4Host: '1.1.1.1',
    ipv6Host: '2606:4700:4700::1111',
    includeGatewayProbe: true,
    gatewayPorts: <int>[53, 80, 443],
    includeNetworkQualityProbe: true,
    networkQualityHost: '1.1.1.1',
    networkQualityPort: 443,
    networkQualitySampleCount: 5,
    healthPolicy: NetworkHealthPolicy.balanced,
  ),
);
```

Each enabled probe is isolated. A failed DNS, socket, TLS, HTTP, or Wi-Fi metadata operation is represented in the report and does not abort the whole diagnostic run.

Gateway and quality probes are disabled by default because they add network traffic and diagnostic time. When enabled, `report.gatewayReachability` distinguishes a reachable local router from an unavailable gateway, while `report.networkQuality` contains the individual TCP connection samples and their aggregate metrics.

## Progress and cancellation

```dart
final cancellationToken = NetworkDoctorCancellationToken();

final diagnosis = doctor.diagnose(
  cancellationToken: cancellationToken,
  onProgress: (progress) {
    print(
      '${progress.stage.name}: '
      '${progress.completedProbes}/${progress.totalProbes}',
    );
  },
);

// Call from a cancel button or application lifecycle handler when needed.
cancellationToken.cancel();

try {
  final report = await diagnosis;
  print(report.totalDuration);
} on NetworkDoctorCancelledException {
  // The caller cancelled the run.
} on NetworkDoctorTimeoutException {
  // The complete run exceeded overallTimeout.
}
```

## Quick checks and continuous monitoring

`diagnose()` answers *why* the network is broken. Two lighter APIs answer *whether* it is:

```dart
final report = await doctor.diagnose();   // deep analysis
final status = await doctor.check();      // quick check
final monitor = doctor.monitor();         // continuous watch
```

A quick check verifies HTTP reachability against a single endpoint with a 1.5 second timeout. When the operating system reports no active transport it returns immediately, producing **no network traffic at all**:

```dart
final status = await doctor.check();

print(status.health);       // healthy | degraded | localOnly | offline
print(status.hasInternet);  // true | false
print(status.transports);   // [wifi], [mobile], [none], ...
```

A monitor turns that into a stream. It runs a quick check on every operating-system connectivity change, on a periodic timer, and on every application resume — and escalates to a full `diagnose()` only when a check observes a *changed*, non-healthy state:

```
Network change / periodic tick / app resume
     │
     ▼
Quick check ── unchanged ──► nothing emitted
     │
  changed
     │
     ├── healthy ──────────────────────────────► emit status + events
     │
     └── degraded / localOnly / offline
                │
                ▼
        Deep diagnosis (gateway, DNS, TCP, TLS, IPv4, IPv6, quality)
                │
                ├── confirms the change ────────► emit status + events + report
                └── contradicts it ─────────────► nothing emitted
```

```dart
final monitor = doctor.monitor(
  config: NetworkMonitorConfig(
    debounce: const Duration(seconds: 1),
    periodicCheckInterval: const Duration(seconds: 30),
    runDeepDiagnosisOnFailure: true,
  ),
);

final subscription = monitor.events.listen((event) {
  switch (event) {
    case NetworkBecameOnline():
      resumeUploads();
    case NetworkBecameOffline():
      showOfflineBanner();
    case NetworkTransportChanged(:final previousTransports):
      adjustQualityFor(previousTransports, event.status.transports);
    case NetworkDegraded(:final report):
      attachToSupportTicket(report?.toPrettyJson(redactNetworkAddresses: true));
    case NetworkRecovered():
      hideOfflineBanner();
  }
});

await monitor.start();

// Later
await monitor.stop();
await subscription.cancel();
await monitor.dispose();
```

`monitor.status` carries the absolute state as a broadcast stream. It does not replay, so pair it with `monitor.currentStatus`:

```dart
StreamBuilder<NetworkStatus>(
  initialData: monitor.currentStatus,
  stream: monitor.status,
  builder: (context, snapshot) => Text(snapshot.data?.health.name ?? 'unknown'),
)
```

Things worth knowing:

- **`events` describes transitions.** The first observed status establishes a baseline and emits no event. Use `status` or `currentStatus` for absolute state, or the value returned by `await monitor.start()`.
- **Nothing is emitted while the network is unchanged.** A status is compared on health, internet reachability, captive-portal suspicion, and its set of transports.
- **The streams never emit errors.** A cycle that fails or is cancelled is retried by the next trigger.
- **Checks never overlap.** A trigger that arrives while a check is running is coalesced into a single follow-up rather than queued or dropped.
- **Monitoring pauses in the background.** Timers stop and connectivity notifications are ignored until the application is resumed, at which point a check runs immediately. Background monitoring is not supported.
- **`NetworkDoctorMonitor` must be disposed.** `dispose()` releases timers, subscriptions, and streams. A monitor created by `doctor.monitor()` borrows the doctor and never disposes it.

Continuous monitoring costs battery and mobile data. `periodicCheckInterval` accepts `null` to rely purely on connectivity changes and manual `refresh()` calls.

## Ready-made widgets

Two Material widgets cover the cases most applications build by hand. Both are optional: importing the package does not force them into an application that only wants the diagnostic API.

### Connectivity banner

`NetworkDoctorBanner` renders live monitor state. It occupies no space while it is hidden, so it composes directly above application content:

```dart
Column(
  children: <Widget>[
    const NetworkDoctorBanner(),
    Expanded(child: content),
  ],
)
```

Without a monitor the banner creates one, starts it, and disposes it with the widget. Pass an existing monitor to share one across the application; a supplied monitor is never started or disposed by the banner, so start it yourself.

```dart
NetworkDoctorBanner(
  monitor: monitor,
  visibility: NetworkBannerVisibility.whenNotHealthy,
  labels: const NetworkDoctorBannerLabels(
    offline: 'İnternet bağlantısı yok',
    retry: 'Yeniden dene',
  ),
  recoveryDisplayDuration: const Duration(seconds: 3),
  onTap: () => NetworkDoctorPanel.showAsBottomSheet(context),
)
```

| Option | Effect |
|---|---|
| `visibility` | `whenOffline`, `whenNotHealthy` (default), or `always`. |
| `labels` | Every string the banner renders, for localisation. |
| `showRetryAction` | Whether the retry action, which refreshes the monitor, is shown. |
| `recoveryDisplayDuration` | How long the healthy "back online" notice stays visible. `Duration.zero` hides it immediately. |
| `builder` | Replaces the content entirely while keeping the monitor wiring and the show/hide animation. |

Colours come from the ambient `ColorScheme`: error colours for unreachable states, tertiary colours for a degraded connection, and primary colours for the recovery notice.

### Support panel

`NetworkDoctorPanel` runs a diagnosis, renders the report as readable sections, and produces the JSON a support ticket needs:

```dart
NetworkDoctorPanel(
  config: NetworkDoctorConfig(includeGatewayProbe: true),
  onShare: (String json) => shareWithSupport(json),
)
```

Or as a modal sheet from anywhere:

```dart
await NetworkDoctorPanel.showAsBottomSheet(context, doctor: doctor);
```

The panel runs a diagnosis as soon as it is inserted (`runOnStart: false` waits for the run action), shows progress, allows cancelling a run, copies the report JSON to the clipboard, and hands the same JSON to `onShare` when that callback is supplied. Pass `initialReport: monitor.latestReport` to show the deep diagnosis a monitor already produced.

`redactWifiIdentifiers` and `redactNetworkAddresses` default to `true` and apply to the copied and shared JSON. Values are rendered unredacted on screen, because the panel runs on the device whose network it describes; keep that in mind before asking users for screenshots.

## Health classification

| Value | Meaning |
|---|---|
| `healthy` | Internet reachability was verified and the selected health policy passed. |
| `degraded` | Internet works, but a policy-relevant probe failed or a captive portal was reported. |
| `localOnly` | A local transport exists, but the configured HTTP quorum did not verify internet access. |
| `offline` | No usable transport was reported and internet access was not verified. |
| `unknown` | Reserved for states that cannot be classified reliably. |

Direct HTTP reachability takes precedence over a stale or unavailable operating-system transport result. This prevents a successful connection from being mislabeled as offline.

The default `balanced` policy treats DNS, TCP, and TLS as health signals while keeping missing IPv6 and redundant HTTP endpoint failures informational. Use `strict` when every supported probe must pass, or `internetOnly` when only the HTTP quorum should determine health.

## Platform support

The public API is usable on Android, iOS, macOS, Windows, Linux, and Web. Capability availability differs by platform:

| Capability | Android | iOS | macOS | Windows | Linux | Web |
|---|---:|---:|---:|---:|---:|---:|
| Transport detection | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Transport change stream | ✅ | ✅ | ✅ | ✅ | ✅ | ✅** |
| Quick check | ✅ | ✅ | ✅ | ✅ | ✅ | ✅* |
| Continuous monitoring | ✅ | ✅ | ✅ | ✅ | ✅ | ✅* |
| HTTP reachability | ✅ | ✅ | ✅ | ✅ | ✅ | ✅* |
| Wi-Fi/LAN metadata | ✅ | ✅ | ✅ | ✅ | ✅ | — |
| DNS timing | ✅ | ✅ | ✅ | ✅ | ✅ | — |
| TCP timing | ✅ | ✅ | ✅ | ✅ | ✅ | — |
| TLS timing | ✅ | ✅ | ✅ | ✅ | ✅ | — |
| IPv4/IPv6 route check | ✅ | ✅ | ✅ | ✅ | ✅ | — |
| Gateway reachability | ✅ | ✅ | ✅ | ✅ | ✅ | — |
| TCP quality sampling | ✅ | ✅ | ✅ | ✅ | ✅ | — |
| Native path characteristics | ✅ | ✅ | ✅ | — | — | — |
| Metered/expensive/constrained | ✅ | ✅ | ✅ | — | — | — |
| Android 17 permission readiness | ✅ | — | — | — | — | — |

`*` Browser CORS and Content Security Policy rules apply to configured HTTP endpoints.

`**` Browsers report only online and offline, so the web transport set is either `wifi` or `none`.

Web returns `ProbeStatus.unsupported` for raw DNS, TCP, TLS, IP-route, and native platform checks. Linux and Windows use the complete Dart probe set but currently return `unsupported` for the additional native platform snapshot. Unsupported capabilities never cause a crash or degrade balanced health.

## Wi-Fi and local-network permissions

This package never requests permissions on its own. The host application controls when and why a permission prompt is shown.

### Android

Apps performing HTTP or socket diagnostics normally declare:

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
```

SSID/BSSID access can require additional Wi-Fi or location-related permissions depending on the Android version and target SDK. Follow the current `network_info_plus` setup guidance for the metadata your application uses.

Android 17 enforces local-network protection for applications targeting SDK 37 or later. Direct LAN access then requires a suitable system-mediated picker or the `ACCESS_LOCAL_NETWORK` runtime permission. The package reports `notRequired`, `granted`, or `denied` through `report.platform?.localNetworkPermission`, but deliberately does not declare or request this host-application permission.

### Apple platforms

On iOS, SSID/BSSID access requires the **Access WiFi Information** capability and one of Apple's permitted access conditions. Core Location authorization may also be required for the application's use case. macOS sandboxed applications must include the network entitlements appropriate to their inbound or outbound connections.

An enabled gateway probe makes a direct local-network connection. The host application remains responsible for the Apple local-network privacy description and authorization behavior required by its deployment target and use case.

## Captive portal detection

`captivePortalSuspected` is a heuristic, not proof. It becomes true when the configured HTTP quorum fails and an endpoint responds with an unexpected redirect containing a location header. Captive portals that block requests, intercept TLS, or return a normal success page may not be detected.

## Privacy

The package contains no analytics or telemetry. Network probes necessarily contact the configured endpoints, so those servers can observe the application's public IP address like any normal network request. Use first-party endpoints when required by your privacy policy.

Before sharing a report, prefer:

```dart
final safeReport = report.toPrettyJson(
  redactWifiIdentifiers: true,
  redactNetworkAddresses: true,
);
```

`redactWifiIdentifiers` masks SSID and BSSID. `redactNetworkAddresses` additionally masks local IP, subnet, broadcast, gateway, DNS server, route, interface, proxy, private-DNS, and probe address fields.

Every JSON report includes `schemaVersion` and `totalDurationMs` so support systems can evolve parsers safely and track complete diagnostic latency.

## Measurement notes

- DNS latency measures a host lookup through the operating system resolver; it is not a direct query to every configured DNS server.
- TCP and TLS latency measure connection setup, not bandwidth or application request latency.
- IPv4/IPv6 checks establish TCP connections to the configured literal addresses; they are not ICMP ping tests.
- Gateway reachability tries the configured TCP ports. A successful connection or an active refusal both prove that the gateway responded at the network layer.
- Quality latency measures repeated TCP connection setup. `packetLossPercent` is the percentage of failed or timed-out TCP samples, not an ICMP packet-loss measurement.
- Jitter is the mean absolute latency difference between consecutive successful TCP samples.
- A quick check measures HTTP reachability only. It reports `offline` from the operating-system transport state without probing, so it proves the absence of a route, not the absence of internet.
- Monitor events describe transitions between observed states, not raw operating-system notifications. Several notifications can collapse into one event, and a notification that changes nothing produces none.
- A connectivity read reporting no transport is confirmed by a second read before it is trusted. Apple platforms restart their network path monitor after the last connectivity listener is cancelled and briefly report `none` on a device that is online.
- Timings can be influenced by DNS caches, connection policy, VPNs, proxies, firewalls, and platform scheduling.

## Development

```bash
flutter pub get
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
flutter test --platform chrome
cd example
flutter test
flutter test integration_test/network_doctor_integration_test.dart -d macos
cd ..
dart pub publish --dry-run
```

CI uses three tiers. Pull requests run formatting, analysis, VM/Web browser
tests, the publish dry-run, and Android, iOS, and WebAssembly builds for fast
feedback. The `main` workflow adds Linux, macOS, and Windows integration smoke
tests. Version tags build all six release targets. Manual workflows additionally
run Android and iOS emulator integration tests. Documentation-only changes skip
the heavy jobs, and new commits cancel stale runs automatically.

Integration and performance regression tests use deterministic local clients
and sockets. They verify registered platform plugins, concurrent HTTP probe
scheduling, and bounded deadlines without relying on external services.

### Testing an application that uses a monitor

`testWidgets` runs a test body inside a fake async zone whose clock stops before
tear-down runs. A stream whose listener was created inside that zone can no
longer deliver anything afterwards, so dispose a monitor **inside** the test body
rather than from `addTearDown`, or drive its lifecycle through
`tester.runAsync(monitor.dispose)` while the body is still executing. A monitor
configured without `periodicCheckInterval` arms no timer, so leaving it
undisposed in a test leaves nothing pending either.

See [CONTRIBUTING.md](CONTRIBUTING.md) for the contribution workflow.

## Roadmap

- Native Windows and Linux path characteristics
- Cupertino variants of the bundled widgets

## Maintainer

[Malik](https://github.com/malikdoksoz)

## License

MIT © 2026 Malik. See [LICENSE](LICENSE).
