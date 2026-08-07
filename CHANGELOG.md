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
