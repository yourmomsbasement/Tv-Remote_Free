import 'package:tv_remote_free/core/adapter/protocol_driver.dart';
import 'package:tv_remote_free/core/adapter/smart_tv_adapter.dart';
import 'package:tv_remote_free/core/discovery/discovered_device.dart';
import 'package:tv_remote_free/core/discovery/ssdp.dart';
import 'package:tv_remote_free/core/storage/device_record.dart';

import 'fake_adapter.dart';

class FakeDriver implements ProtocolDriver {
  FakeDriver(this.adapter);

  final FakeAdapter adapter;

  @override
  String get protocol => 'fake';

  @override
  String get displayName => 'Fake TV';

  @override
  List<String> get ssdpSearchTargets => const [];

  @override
  bool matches(SsdpResponse response) => false;

  @override
  Future<DiscoveredDevice?> describe(SsdpResponse response) async => null;

  @override
  Future<DiscoveredDevice> probe(String ipAddress) async => DiscoveredDevice(
    id: 'fake:$ipAddress',
    name: 'Fake TV',
    protocol: protocol,
    ipAddress: ipAddress,
  );

  @override
  SmartTVAdapter createAdapter(DeviceRecord device) => adapter;
}

class NoSsdp extends SsdpClient {
  @override
  Stream<SsdpResponse> search(
    List<String> searchTargets, {
    Duration timeout = const Duration(seconds: 4),
  }) => const Stream.empty();
}
