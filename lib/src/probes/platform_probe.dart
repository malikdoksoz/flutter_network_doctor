import 'platform_probe_interface.dart';
import 'platform_probe_stub.dart'
    if (dart.library.io) 'platform_probe_io.dart'
    as implementation;

export 'platform_probe_interface.dart';

/// Creates the default lower-level network probe implementation.
PlatformNetworkProbe createPlatformNetworkProbe() =>
    implementation.PlatformNetworkProbeImpl();
