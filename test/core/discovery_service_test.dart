import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_remote_free/core/adapter/protocol_driver.dart';
import 'package:tv_remote_free/core/adapter/smart_tv_adapter.dart';
import 'package:tv_remote_free/core/discovery/discovered_device.dart';
import 'package:tv_remote_free/core/discovery/discovery_service.dart';
import 'package:tv_remote_free/core/discovery/mdns.dart';
import 'package:tv_remote_free/core/discovery/ssdp.dart';
import 'package:tv_remote_free/core/errors.dart';
import 'package:tv_remote_free/core/storage/device_record.dart';
import 'package:tv_remote_free/protocols/lg_webos/webos_driver.dart';

class FakeSsdp extends SsdpClient {
  FakeSsdp(this.responses);
  final List<SsdpResponse> responses;
  List<String>? searched;

  @override
  Stream<SsdpResponse> search(
    List<String> searchTargets, {
    Duration timeout = const Duration(seconds: 4),
  }) {
    searched = searchTargets;
    return Stream.fromIterable(responses);
  }
}

class StubDriver extends ProtocolDriver {
  StubDriver(this.protocol, this.st);

  @override
  final String protocol;
  final String st;
  int describes = 0;

  @override
  String get displayName => protocol;

  @override
  List<String> get ssdpSearchTargets => [st];

  @override
  bool matches(SsdpResponse r) => r.st == st;

  @override
  Future<DiscoveredDevice?> describe(SsdpResponse r) async {
    describes++;
    return DiscoveredDevice(
      id: '$protocol:${r.usn}',
      name: 'TV',
      protocol: protocol,
      ipAddress: r.address.address,
    );
  }

  @override
  Future<DiscoveredDevice> probe(String ip) async =>
      throw const TvRemoteException(TvErrorCode.unreachable, 'nope');

  @override
  SmartTVAdapter createAdapter(DeviceRecord device) =>
      throw UnimplementedError();
}

SsdpResponse response(String ip, String st, String usn) =>
    SsdpResponse(address: InternetAddress(ip), headers: {'st': st, 'usn': usn});

void main() {
  test('routes responses to the matching driver and de-duplicates', () async {
    final roku = StubDriver('roku', 'roku:ecp');
    final lg = StubDriver('lg', 'urn:lg');
    final ssdp = FakeSsdp([
      response('10.0.0.2', 'roku:ecp', 'a'),
      response('10.0.0.2', 'roku:ecp', 'a'), // repeated answer
      response('10.0.0.3', 'urn:lg', 'b'),
      response('10.0.0.4', 'upnp:rootdevice', 'c'), // unsupported
    ]);
    final service = DiscoveryService([roku, lg], ssdp: ssdp);
    final found = await service.scan().toList();
    expect(ssdp.searched, ['roku:ecp', 'urn:lg']);
    expect(found.map((d) => d.id), ['roku:a', 'lg:b']);
    expect(roku.describes, 1);
  });

  test('probe reports a structured error when nothing answers', () async {
    final service = DiscoveryService([
      StubDriver('roku', 'x'),
    ], ssdp: FakeSsdp([]));
    expect(() => service.probe('10.0.0.9'), throwsA(isA<TvRemoteException>()));
  });

  test('webOS UPnP description parsing', () {
    final d = WebOsDriver.parseDescription('''
<root xmlns="urn:schemas-upnp-org:device-1-0">
  <device>
    <friendlyName>[LG] webOS TV OLED55C1</friendlyName>
    <modelName>LG Smart TV</modelName>
    <UDN>uuid:1234-abcd</UDN>
  </device>
</root>''');
    expect(d.friendlyName, '[LG] webOS TV OLED55C1');
    expect(d.modelName, 'LG Smart TV');
    expect(d.udn, '1234-abcd');
  });

  test('merges driver-specific discovery (mDNS) with SSDP', () async {
    final roku = StubDriver('roku', 'roku:ecp');
    final atv = MdnsStubDriver();
    final service = DiscoveryService([
      roku,
      atv,
    ], ssdp: FakeSsdp([response('10.0.0.2', 'roku:ecp', 'a')]));
    final found = await service.scan().toList();
    expect(found.map((d) => d.id).toSet(), {'roku:a', 'atv:Den'});
  });

  test('mDNS instance names are unescaped', () {
    expect(
      MdnsBrowser.instanceNameOf(
        r'Living\032Room\032TV._androidtvremote2._tcp.local',
        '_androidtvremote2._tcp',
      ),
      'Living Room TV',
    );
    expect(
      MdnsBrowser.instanceNameOf(
        'Den._androidtvremote2._tcp.local',
        '_androidtvremote2._tcp',
      ),
      'Den',
    );
  });
}

class MdnsStubDriver extends StubDriver {
  MdnsStubDriver() : super('atv', 'none');

  @override
  List<String> get ssdpSearchTargets => const [];

  @override
  Stream<DiscoveredDevice> discover({
    Duration timeout = const Duration(seconds: 5),
  }) => Stream.fromIterable(const [
    DiscoveredDevice(
      id: 'atv:Den',
      name: 'Den',
      protocol: 'atv',
      ipAddress: '10.0.0.7',
    ),
    DiscoveredDevice(
      id: 'atv:Den',
      name: 'Den',
      protocol: 'atv',
      ipAddress: '10.0.0.7',
    ),
  ]);
}
