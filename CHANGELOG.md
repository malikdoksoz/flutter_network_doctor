## 0.4.0

- Added `FlutterNetworkDoctor.check()`, a sub-second quick check that returns a `NetworkStatus` and produces no network traffic when the operating system reports no active transport.
- Added `NetworkDoctorMonitor` and `FlutterNetworkDoctor.monitor()` for continuous watching, exposing a `NetworkStatus` stream, a sealed `NetworkMonitorEvent` stream, `currentStatus`, `latestReport`, and `start`/`stop`/`refresh`/`dispose` lifecycle control.
- Added online, offline, transport-change, degraded, and recovered events, each carrying the deep diagnostic report produced for the transition.
- Escalated to a full diagnostic run only when a quick check observes a changed, non-healthy state, so an unchanged network costs one cheap check and a quick-check false positive is never emitted.
- Debounced operating-system connectivity notifications, re-armed periodic checks after each completed run, coalesced overlapping triggers into a single follow-up, and suppressed emissions that repeat the current state.
- Paused all monitor work while the application is backgrounded and ran an immediate check on resume, degrading gracefully when no Flutter binding is available.
- Confirmed a connectivity read that reports no transport with a second read, fixing a false `offline` verdict on Apple platforms whose network path monitor restarts after the last connectivity listener is cancelled.
- Added `NetworkCheckConfig` and `NetworkMonitorConfig` with validation matching `NetworkDoctorConfig`.
- Serialized `NetworkStatus` to versioned JSON with the same network-address redaction as reports.
- Added deterministic quick-check, monitor state-machine, lifecycle, concurrency, and Web fallback tests, plus a monitor lifecycle case to the on-device integration suite.
- Added a live monitor panel to the example application.

## 0.3.5

- Added self-updating pub.dev version, score, likes, and publisher badges to the README.
- Replaced the static license badge with one that tracks the repository license.

## 0.3.4

- Added a project banner to the top of the README.

## 0.3.3

- Fixed the CI badge to track successful pushes to the main branch.
- Removed the cached pub version badge; the package header remains the source of truth for the current version.

## 0.3.2

- Added pub.dev package screenshots for the network diagnostics example.
- Made README screenshots 240px wide and link to their full-size images.

## 0.3.1

- Fixed README screenshots on pub.dev by using GitHub-hosted image URLs.
- Reduced pub version-badge cache time so new releases appear sooner.

## 0.3.0

- Added optional local-gateway reachability checks using bounded TCP attempts.
- Added optional repeated TCP quality sampling with minimum, average, p95,
  maximum, jitter, and failed-sample percentage metrics.
- Added structured gateway and quality results to versioned JSON reports.
- Added Apple native path status reporting and avoided publishing IP/DNS
  capability flags from an unsatisfied path snapshot.
- Expanded full redaction to cover probe hosts, endpoint URIs, redirect
  locations, and sensitive values embedded in probe messages.
- Added deterministic metric, socket, configuration, serialization, and Web
  fallback tests.
- Split CI into fast pull-request checks and complete main/tag/manual matrices,
  with deterministic integration clients and stale-run cancellation.

## 0.2.0

- Added native Android, iOS, and macOS network characteristics.
- Added DNS server, route, interface, MTU, proxy, metered, expensive,
  constrained, validation, and captive-portal fields where supported.
- Added Android 17 local-network permission readiness reporting.
- Added overall diagnostic deadlines, cancellation, and progress callbacks.
- Added balanced, strict, and internet-only health policies.
- Added stable probe error codes, report schema version, and total duration.
- Added full network-address redaction for support reports.
- Isolated platform-specific connectivity and Wi-Fi implementations for clean,
  WebAssembly-safe static analysis while retaining all six Flutter platforms.
- Added Android, iOS, Linux, macOS, Web, and Windows build CI.
- Added deterministic concurrency, deadline, and six-platform integration
  regression coverage.
- Expanded the example and automated test coverage.

## 0.1.1

- Removed duplicate maintainer attribution from the README introduction.

## 0.1.0

- Initial release.
- Added transport discovery.
- Added Wi-Fi/LAN metadata collection.
- Added multi-endpoint HTTP internet checks.
- Added DNS, TCP, TLS, IPv4, and IPv6 probes on `dart:io` platforms.
- Added JSON support reports and captive-portal redirect heuristic.
- Added configuration validation and resilient partial Wi-Fi metadata reads.
- Added health, captive-portal, redaction, and configuration tests.
