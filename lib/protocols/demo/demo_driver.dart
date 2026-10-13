import '../../core/adapter/protocol_driver.dart';
import '../../core/adapter/smart_tv_adapter.dart';
import '../../core/discovery/discovered_device.dart';
import '../../core/discovery/ssdp.dart';
import '../../core/errors.dart';
import '../../core/storage/device_record.dart';
import 'demo_adapter.dart';

/// The simulated TV. Never discovered on the network; offered on the TVs
/// screen as "Try the demo TV".
class DemoDriver extends ProtocolDriver {
  static const device = DeviceRecord(
    id: 'demo:tv',
    name: 'Demo TV',
    protocol: Protocols.demo,
    manufacturer: 'TV Remote Free',
    model: 'Simulated TV',
  );

  @override
  String get protocol => Protocols.demo;

  @override
  String get displayName => 'Demo TV';

  @override
  List<String> get ssdpSearchTargets => const [];

  @override
  bool matches(SsdpResponse response) => false;

  @override
  Future<DiscoveredDevice?> describe(SsdpResponse response) async => null;

  @override
  Future<DiscoveredDevice> probe(String ipAddress) async =>
      throw const TvRemoteException(
        TvErrorCode.unreachable,
        'The demo TV is not on the network',
      );

  @override
  SmartTVAdapter createAdapter(DeviceRecord device) => DemoAdapter();
}
