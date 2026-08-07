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
