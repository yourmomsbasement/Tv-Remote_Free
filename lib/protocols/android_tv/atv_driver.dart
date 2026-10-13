import 'dart:io';

import '../../core/adapter/protocol_driver.dart';
import '../../core/adapter/smart_tv_adapter.dart';
import '../../core/discovery/discovered_device.dart';
import '../../core/discovery/mdns.dart';
import '../../core/discovery/ssdp.dart';
import '../../core/errors.dart';
import '../../core/storage/device_record.dart';
import 'atv_adapter.dart';

class AndroidTvDriver extends ProtocolDriver {
  AndroidTvDriver({MdnsBrowser? browser}) : _browser = browser ?? MdnsBrowser();

  final MdnsBrowser _browser;

  static const serviceType = '_androidtvremote2._tcp';

  @override
  String get protocol => Protocols.androidTv;

  @override
  String get displayName => 'Android TV / Google TV';

  @override
  List<String> get ssdpSearchTargets => const [];

  @override
  bool matches(SsdpResponse response) => false;

  @override
  Future<DiscoveredDevice?> describe(SsdpResponse response) async => null;

  @override
  Stream<DiscoveredDevice> discover({
    Duration timeout = const Duration(seconds: 5),
  }) => _browser
      .browse(serviceType, timeout: timeout)
      .map(
        (s) => DiscoveredDevice(
          id: 'android_tv:${s.instanceName}',
          name: s.instanceName,
          protocol: protocol,
          ipAddress: s.address.address,
          manufacturer: 'Android TV',
        ),
      );

  /// Checks the remote port is open. Pairing happens on connect.
  @override
  Future<DiscoveredDevice> probe(String ipAddress) async {
    try {
      final socket = await Socket.connect(
        ipAddress,
        6466,
        timeout: const Duration(seconds: 2),
      );
      socket.destroy();
    } on SocketException catch (e) {
      throw TvRemoteException(
        TvErrorCode.unreachable,
        'No Android TV answered at $ipAddress. Check the address and that '
        'the TV is on.',
        cause: e,
      );
    }
    return DiscoveredDevice(
      id: 'android_tv:$ipAddress',
      name: 'Android TV ($ipAddress)',
      protocol: protocol,
      ipAddress: ipAddress,
      manufacturer: 'Android TV',
    );
  }

  @override
  SmartTVAdapter createAdapter(DeviceRecord device) =>
      AndroidTvAdapter(host: device.ipAddress!);
}
