import '../discovery/discovered_device.dart';
import '../discovery/ssdp.dart';
import '../storage/device_record.dart';
import 'smart_tv_adapter.dart';

/// Everything the app needs to know about one manufacturer protocol:
/// how to find its devices and how to build an adapter for one.
///
/// Adding a new platform means adding a driver; no UI code changes.
abstract class ProtocolDriver {
  String get protocol;

  String get displayName;

  /// SSDP search targets to multicast during discovery.
  List<String> get ssdpSearchTargets;

  bool matches(SsdpResponse response);

  /// Discovery that does not go through SSDP (e.g. mDNS). Streams devices
  /// until [timeout]. Most drivers rely on SSDP and keep this empty.
  Stream<DiscoveredDevice> discover({
    Duration timeout = const Duration(seconds: 5),
  }) => const Stream.empty();

  /// Turns an SSDP response into a device, fetching details if needed.
  /// Returns null if the responder turns out not to be a supported device.
  Future<DiscoveredDevice?> describe(SsdpResponse response);

  /// Identifies a device entered by IP address. Throws [TvRemoteException]
  /// if nothing speaking this protocol answers.
  Future<DiscoveredDevice> probe(String ipAddress);

  SmartTVAdapter createAdapter(DeviceRecord device);
}
