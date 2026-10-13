import 'package:http/http.dart' as http;

import '../../core/adapter/protocol_driver.dart';
import '../../core/adapter/smart_tv_adapter.dart';
import '../../core/discovery/discovered_device.dart';
import '../../core/discovery/ssdp.dart';
import '../../core/storage/device_record.dart';
import 'roku_adapter.dart';

class RokuDriver implements ProtocolDriver {
  RokuDriver({http.Client Function()? clientFactory})
    : _clientFactory = clientFactory ?? http.Client.new;

  final http.Client Function() _clientFactory;

  static const searchTarget = 'roku:ecp';

  @override
  String get protocol => Protocols.roku;

  @override
  String get displayName => 'Roku';

  @override
  List<String> get ssdpSearchTargets => const [searchTarget];

  @override
  bool matches(SsdpResponse response) =>
      response.st == searchTarget ||
      (response.usn?.contains('roku:ecp') ?? false);

  @override
  Future<DiscoveredDevice?> describe(SsdpResponse response) async {
    final location = Uri.tryParse(response.location ?? '');
    final host = location?.host.isNotEmpty == true
        ? location!.host
        : response.address.address;
    try {
      return await probe(host, port: location?.port ?? 8060);
    } on Exception {
      return null;
    }
  }

  @override
  Future<DiscoveredDevice> probe(String ipAddress, {int port = 8060}) async {
    final adapter = RokuAdapter(
      host: ipAddress,
      port: port,
      client: _clientFactory(),
    );
    try {
      final info = await adapter.fetchDeviceInfo();
      return DiscoveredDevice(
        id: 'roku:${info.serialNumber}',
        name: info.friendlyName ?? 'Roku',
        protocol: protocol,
        ipAddress: ipAddress,
        manufacturer: info.vendorName ?? 'Roku',
        model: info.modelName,
        macAddress: info.wifiMac ?? info.ethernetMac,
      );
    } finally {
      await adapter.dispose();
    }
  }

  @override
  SmartTVAdapter createAdapter(DeviceRecord device) =>
      RokuAdapter(host: device.ipAddress!, client: _clientFactory());
}
