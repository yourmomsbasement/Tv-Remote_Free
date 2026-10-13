import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_remote_free/core/adapter/smart_tv_adapter.dart';
import 'package:tv_remote_free/core/capabilities/device_capabilities.dart';
import 'package:tv_remote_free/core/capabilities/remote_key.dart';
import 'package:tv_remote_free/core/errors.dart';
import 'package:tv_remote_free/protocols/roku/roku_adapter.dart';
import 'package:tv_remote_free/protocols/roku/roku_driver.dart';

String deviceInfo({bool isTv = true, String mode = 'default'}) =>
    '''
<?xml version="1.0" encoding="UTF-8" ?>
<device-info>
  <serial-number>X01234567890</serial-number>
  <vendor-name>TCL</vendor-name>
  <model-name>55S425</model-name>
  <friendly-model-name>TCL Roku TV</friendly-model-name>
  <user-device-name>Living Room</user-device-name>
  <wifi-mac>d8:31:34:aa:bb:cc</wifi-mac>
  <is-tv>$isTv</is-tv>
  <supports-suspend>false</supports-suspend>
  <ecp-setting-mode>$mode</ecp-setting-mode>
</device-info>''';

const appsXml = '''
<apps>
  <app id="tvinput.hdmi1" type="tvin" version="1.0.0">HDMI 1</app>
  <app id="12" type="appl" version="5.1.0">Netflix</app>
  <app id="837" type="appl" version="2.21.0">YouTube</app>
</apps>''';

/// A minimal ECP server that records requests.
class MockRoku {
  late HttpServer server;
  final requests = <String>[];
  bool isTv = true;
  bool forbidKeys = false;

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      // Record the raw (still percent-encoded) path.
      final line = '${req.method} ${req.uri}';
      requests.add(line);
      final res = req.response;
      if (req.uri.path == '/query/device-info') {
        res.write(deviceInfo(isTv: isTv));
      } else if (req.uri.path == '/query/apps') {
        res.write(appsXml);
      } else if (req.method == 'POST' && forbidKeys) {
        res.statusCode = 403;
      }
      await res.close();
    });
  }

  int get port => server.port;
  List<String> get posts =>
      requests.where((r) => r.startsWith('POST')).toList();
}

void main() {
  late MockRoku tv;
  late RokuAdapter adapter;

  setUp(() async {
    tv = MockRoku();
    await tv.start();
    adapter = RokuAdapter(host: '127.0.0.1', port: tv.port);
  });

  tearDown(() async {
    await adapter.dispose();
    await tv.server.close(force: true);
  });

  test('connect reads device info and reports TV capabilities', () async {
    final events = <DeviceEvent>[];
    adapter.events.listen(events.add);
    await adapter.connect();
    final caps = await adapter.getCapabilities();
    expect(adapter.status, ConnectionStatus.connected);
    expect(caps.navigation, isTrue);
    expect(caps.volume, isTrue);
    expect(caps.channels, isTrue);
    expect(caps.textInput, isTrue);
    expect(caps.textInputStrategy, TextInputStrategy.characterEvents);
    expect(caps.textFieldDetection, isFalse);
    expect(caps.pointer, isFalse);
    expect(caps.pairingRequired, isFalse);
    await Future<void>.delayed(Duration.zero);
    final info = events.whereType<DeviceInfoUpdated>().single;
    expect(info.name, 'Living Room');
    expect(info.macAddress, 'd8:31:34:aa:bb:cc');
  });

  test('streaming players do not advertise TV-only keys', () async {
    tv.isTv = false;
    await adapter.connect();
    final caps = await adapter.getCapabilities();
    expect(caps.volume, isFalse);
    expect(caps.powerOff, isFalse);
    expect(caps.navigation, isTrue);
    expect(
      () => adapter.sendKey(RemoteKey.volumeUp),
      throwsA(
        isA<TvRemoteException>().having(
          (e) => e.code,
          'code',
          TvErrorCode.unsupported,
        ),
      ),
    );
  });

  test('keys map to ECP keypress paths', () async {
    await adapter.connect();
    await adapter.sendKey(RemoteKey.select);
    await adapter.sendKey(RemoteKey.playPause);
    await adapter.sendKey(RemoteKey.mute);
    expect(tv.posts, [
      'POST /keypress/Select',
      'POST /keypress/Play',
      'POST /keypress/VolumeMute',
    ]);
  });

  test(
    'text is sent as URL-encoded Lit_ keypresses, one per character',
    () async {
      await adapter.connect();
      await adapter.sendText('a é&😀');
      await adapter.deleteText(2);
      expect(tv.posts, [
        'POST /keypress/Lit_a',
        'POST /keypress/Lit_%20',
        'POST /keypress/Lit_%C3%A9',
        'POST /keypress/Lit_%26',
        'POST /keypress/Lit_%F0%9F%98%80',
        'POST /keypress/Backspace',
        'POST /keypress/Backspace',
      ]);
    },
  );

  test('lists launchable apps only and launches by id', () async {
    await adapter.connect();
    final apps = await adapter.listApps();
    expect(apps.map((a) => a.name), ['Netflix', 'YouTube']);
    expect(apps.first.iconUrl, endsWith('/query/icon/12'));
    await adapter.launchApp('837');
    expect(tv.posts.last, 'POST /launch/837');
  });

  test('a 403 explains how to enable mobile control', () async {
    await adapter.connect();
    tv.forbidKeys = true;
    expect(
      () => adapter.sendKey(RemoteKey.home),
      throwsA(
        isA<TvRemoteException>()
            .having((e) => e.code, 'code', TvErrorCode.forbidden)
            .having(
              (e) => e.message,
              'message',
              contains('Control by mobile apps'),
            ),
      ),
    );
  });

  test('unreachable host fails with a structured error', () async {
    await tv.server.close(force: true);
    expect(
      () => adapter.connect(),
      throwsA(
        isA<TvRemoteException>().having(
          (e) => e.code,
          'code',
          TvErrorCode.unreachable,
        ),
      ),
    );
  });

  test('commands before connect are rejected', () {
    expect(
      () => adapter.sendKey(RemoteKey.home),
      throwsA(
        isA<TvRemoteException>().having(
          (e) => e.code,
          'code',
          TvErrorCode.notConnected,
        ),
      ),
    );
  });

  test('pointer and absolute volume are unsupported', () async {
    await adapter.connect();
    expect(() => adapter.movePointer(1, 1), throwsA(isA<TvRemoteException>()));
    expect(() => adapter.setVolume(10), throwsA(isA<TvRemoteException>()));
  });

  test('driver probe identifies the device by serial number', () async {
    final device = await RokuDriver().probe('127.0.0.1', port: tv.port);
    expect(device.id, 'roku:X01234567890');
    expect(device.name, 'Living Room');
    expect(device.model, 'TCL Roku TV');
  });
}
