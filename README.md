# flutter_network_doctor

[![CI](https://github.com/malikdoksoz/flutter_network_doctor/actions/workflows/ci.yml/badge.svg)](https://github.com/malikdoksoz/flutter_network_doctor/actions/workflows/ci.yml)
[![pub package](https://img.shields.io/pub/v/flutter_network_doctor.svg)](https://pub.dev/packages/flutter_network_doctor)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Production-grade network diagnostics for Flutter applications, maintained by [Malik](https://github.com/malikdoksoz).

Instead of only answering “Wi-Fi or mobile?”, `flutter_network_doctor` builds a structured support report from operating-system connectivity state, real HTTP reachability, Wi-Fi/LAN metadata, DNS timing, TCP/TLS connection timing, and separate IPv4/IPv6 route checks.

## Features

- Active transport detection: Wi-Fi, mobile, Ethernet, VPN, Bluetooth, satellite, and other
- Real internet verification using a configurable quorum of HTTP endpoints
- Wi-Fi/LAN metadata: SSID, BSSID, local IPv4/IPv6, subnet, broadcast, and gateway
- DNS lookup, TCP connection, and TLS handshake timing on `dart:io` platforms
- Separate IPv4 and IPv6 route checks
- Captive-portal redirect heuristic
- Structured JSON support reports with optional SSID/BSSID redaction
- Web-safe behavior: unavailable socket probes return `unsupported` instead of throwing
- No analytics, telemetry, or automatic permission prompts

## Requirements

- Flutter 3.38.1 or later
- Dart 3.10.0 or later, below Dart 4.0.0
- iOS 13.0 or later
- macOS 10.15 or later
- Java 17, Kotlin 2.2.0, Android Gradle Plugin 8.12.1 or later, and Gradle 8.13 or later for Android consumers

The effective platform minimums come from the package's current `network_info_plus` dependency.

## Installation

```yaml
dependencies:
  flutter_network_doctor: ^0.1.0
```

Then install dependencies:

```bash
flutter pub get
```

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

  final supportReport = report.toPrettyJson(
    redactWifiIdentifiers: true,
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
  ),
);
```

Each enabled probe is isolated. A failed DNS, socket, TLS, HTTP, or Wi-Fi metadata operation is represented in the report and does not abort the whole diagnostic run.

## Health classification

| Value | Meaning |
|---|---|
| `healthy` | Internet reachability was verified and every supported, enabled probe succeeded. |
| `degraded` | Internet works, but at least one supported, enabled probe failed. |
| `localOnly` | A local transport exists, but the configured HTTP quorum did not verify internet access. |
| `offline` | No usable transport was reported and internet access was not verified. |
| `unknown` | Reserved for states that cannot be classified reliably. |

Direct HTTP reachability takes precedence over a stale or unavailable operating-system transport result. This prevents a successful connection from being mislabeled as offline.

## Platform support

The public API is usable on Android, iOS, macOS, Windows, Linux, and Web. Capability availability differs by platform:

| Capability | Android | iOS | macOS | Windows | Linux | Web |
|---|---:|---:|---:|---:|---:|---:|
| Transport detection | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| HTTP reachability | ✅ | ✅ | ✅ | ✅ | ✅ | ✅* |
| Wi-Fi/LAN metadata | ✅ | ✅ | ✅ | ✅ | ✅ | — |
| DNS timing | ✅ | ✅ | ✅ | ✅ | ✅ | — |
| TCP timing | ✅ | ✅ | ✅ | ✅ | ✅ | — |
| TLS timing | ✅ | ✅ | ✅ | ✅ | ✅ | — |
| IPv4/IPv6 route check | ✅ | ✅ | ✅ | ✅ | ✅ | — |

`*` Browser CORS and Content Security Policy rules apply to configured HTTP endpoints.

Web returns `ProbeStatus.unsupported` for raw DNS, TCP, TLS, and IP-route checks. It does not emulate results that the browser cannot measure. Individual transport values can also depend on what the operating system exposes.

## Wi-Fi and local-network permissions

This package never requests permissions on its own. The host application controls when and why a permission prompt is shown.

### Android

Apps performing HTTP or socket diagnostics normally declare:

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
```

SSID/BSSID access can require additional Wi-Fi or location-related permissions depending on the Android version and target SDK. Follow the current `network_info_plus` setup guidance for the metadata your application uses.

Android 17 enforces local-network protection for applications targeting SDK 37 or later. Direct LAN access then requires a suitable system-mediated picker or the `ACCESS_LOCAL_NETWORK` runtime permission. Version 0.1.0 reports failed LAN/socket operations but does not declare or request this host-application permission.

### Apple platforms

On iOS, SSID/BSSID access requires the **Access WiFi Information** capability and one of Apple's permitted access conditions. Core Location authorization may also be required for the application's use case. macOS sandboxed applications must include the network entitlements appropriate to their inbound or outbound connections.

## Captive portal detection

`captivePortalSuspected` is a heuristic, not proof. It becomes true when the configured HTTP quorum fails and an endpoint responds with an unexpected redirect containing a location header. Captive portals that block requests, intercept TLS, or return a normal success page may not be detected.

## Privacy

The package contains no analytics or telemetry. Network probes necessarily contact the configured endpoints, so those servers can observe the application's public IP address like any normal network request. Use first-party endpoints when required by your privacy policy.

Before sharing a report, prefer:

```dart
final safeReport = report.toPrettyJson(
  redactWifiIdentifiers: true,
);
```

This masks SSID and BSSID. Local IP, subnet, broadcast, and gateway values remain because they are often essential for troubleshooting; remove them separately if your support policy treats them as sensitive.

## Measurement notes

- DNS latency measures a host lookup through the operating system resolver; it is not a direct query to every configured DNS server.
- TCP and TLS latency measure connection setup, not bandwidth or application request latency.
- IPv4/IPv6 checks establish TCP connections to the configured literal addresses; they are not ICMP ping tests.
- Timings can be influenced by DNS caches, connection policy, VPNs, proxies, firewalls, and platform scheduling.

## Development

```bash
flutter pub get
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
dart pub publish --dry-run
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for the contribution workflow.

## Roadmap

- Native DNS server discovery
- Metered, expensive, and constrained network flags
- Android 17 `ACCESS_LOCAL_NETWORK` readiness reporting
- Native local-gateway reachability probe
- Optional jitter and packet-loss sampling
- Reusable support/debug panel widget

## Maintainer

[Malik](https://github.com/malikdoksoz)

## License

MIT © 2026 Malik. See [LICENSE](LICENSE).
