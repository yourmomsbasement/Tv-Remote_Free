import '../../core/adapter/protocol_driver.dart';
import '../../core/adapter/smart_tv_adapter.dart';
import '../../core/discovery/discovered_device.dart';
import '../../core/discovery/ssdp.dart';
import '../../core/errors.dart';
import '../../core/storage/device_record.dart';
import 'samsung_adapter.dart';

/// Samsung Tizen TVs (2016 and later).
class SamsungDriver extends ProtocolDriver {
  static const searchTarget = 'urn:samsung.com:device:RemoteControlReceiver:1';

  @override
  String get protocol => Protocols.samsung;

  @override
  String get displayName => 'Samsung';

  @override
  List<String> get ssdpSearchTargets => const [searchTarget];

  @override
  bool matches(SsdpResponse response) =>
      response.st == searchTarget ||
      (response.usn?.contains('RemoteControlReceiver') ?? false);

  @override
  Future<DiscoveredDevice?> describe(SsdpResponse response) async {
    try {
      return await probe(response.address.address);
    } on Exception {
      return null;
    }
  }

  /// Reads the TV's REST description (port 8001), which needs no pairing.
  @override
  Future<DiscoveredDevice> probe(String ipAddress) =>
      describeAt(SamsungAdapter(host: ipAddress), ipAddress);

  static Future<DiscoveredDevice> describeAt(
    SamsungAdapter adapter,
    String ipAddress,
  ) async {
    final info = await adapter.fetchInfo();
    final device = info?['device'];
    if (device is! Map) {
      throw TvRemoteException(
        TvErrorCode.unreachable,
        'No Samsung TV answered at $ipAddress. Check the address and that '
        'the TV is on.',
      );
    }
    final id = (device['id'] ?? device['duid'] ?? ipAddress).toString();
    return DiscoveredDevice(
      id: 'samsung:${id.replaceFirst('uuid:', '')}',
      name: _cleanName(device['name'] as String?) ?? 'Samsung TV',
      protocol: Protocols.samsung,
      ipAddress: ipAddress,
      manufacturer: 'Samsung',
      model: device['modelName'] as String?,
      macAddress: device['wifiMac'] as String?,
    );
  }

  /// Samsung names look like "[TV] Samsung Q6 Series (55)".
  static String? _cleanName(String? name) {
    final n = name?.replaceFirst(RegExp(r'^\[TV\]\s*'), '').trim();
    return n == null || n.isEmpty ? null : n;
  }

  @override
  SmartTVAdapter createAdapter(DeviceRecord device) =>
      SamsungAdapter(host: device.ipAddress!);
}
