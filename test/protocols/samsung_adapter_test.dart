import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_remote_free/core/adapter/custom_command.dart';
import 'package:tv_remote_free/core/adapter/smart_tv_adapter.dart';
import 'package:tv_remote_free/core/capabilities/remote_key.dart';
import 'package:tv_remote_free/core/content/content_link.dart';
import 'package:tv_remote_free/core/errors.dart';
import 'package:tv_remote_free/protocols/samsung/samsung_adapter.dart';
import 'package:tv_remote_free/protocols/samsung/samsung_driver.dart';

/// A mock Samsung TV: REST description plus the remote-control channel.
class MockSamsungTv {
  late HttpServer server;
  WebSocket? socket;
  final messages = <Map<String, dynamic>>[];
  final tokens = <String>{};
  bool userAccepts = true;
  Duration approvalDelay = const Duration(milliseconds: 20);

  int get port => server.port;

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      if (req.uri.path == '/api/v2/') {
        req.response
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({
              'device': {
                'id': 'uuid:abc-123',
                'name': '[TV] Samsung Q6 Series (55)',
                'modelName': 'QN55Q6FNA',
                'wifiMac': '64:1c:ae:00:11:22',
                'TokenAuthSupport': 'true',
              },
              'type': 'Samsung SmartTV',
            }),
          );
        await req.response.close();
        return;
      }
      final ws = socket = await WebSocketTransformer.upgrade(req);
      ws.listen((m) => _onMessage(ws, jsonDecode(m as String)));
      final token = req.uri.queryParameters['token'];
      if (token != null && tokens.contains(token)) {
        _connected(ws, token);
        return;
      }
      Timer(approvalDelay, () {
        if (userAccepts) {
          tokens.add('tok-1');
          _connected(ws, 'tok-1');
        } else {
          send({'event': 'ms.channel.unauthorized'});
        }
      });
    });
  }

  void _connected(WebSocket ws, String token) => send({
    'event': 'ms.channel.connect',
    'data': {'token': token, 'clients': []},
  });

  void send(Map<String, Object?> m) => socket!.add(jsonEncode(m));

  void _onMessage(WebSocket ws, Map<String, dynamic> m) {
    messages.add(m);
    final params = m['params'] as Map<String, dynamic>;
    switch (params['event']) {
      case 'ed.installedApp.get':
        send({
          'event': 'ed.installedApp.get',
          'data': {
            'data': [
              {
                'appId': '111299001912',
                'name': 'YouTube',
                'app_type': 2,
                'icon': '/icons/yt.png',
              },
              {'appId': '3201907018807', 'name': 'Netflix', 'app_type': 2},
            ],
          },
        });
      case 'ed.apps.icon':
        send({
          'event': 'ed.apps.icon',
          'data': {
            'iconPath': params['data']['iconPath'],
            'imageBase64': base64.encode([1, 2, 3]),
          },
        });
    }
  }

  Iterable<Map<String, dynamic>> get remote => messages
      .where((m) => m['method'] == 'ms.remote.control')
      .map((m) => m['params'] as Map<String, dynamic>);
}

void main() {
  late MockSamsungTv tv;
  late SamsungAdapter adapter;

  setUp(() async {
    tv = MockSamsungTv();
    await tv.start();
    adapter = SamsungAdapter(
      host: '127.0.0.1',
      endpoints: [Uri.parse('ws://127.0.0.1:${tv.port}')],
      infoUri: Uri.parse('http://127.0.0.1:${tv.port}/api/v2/'),
    );
  });

  tearDown(() async {
    await adapter.disconnect();
    await tv.server.close(force: true);
  });

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 50));

  test('first connection is approved on the TV and issues a token', () async {
    final events = <DeviceEvent>[];
    adapter.events.listen(events.add);
    await adapter.connect();
    expect(adapter.status, ConnectionStatus.connected);
    await settle();
    expect(events.whereType<PairingCompleted>().single.credential, 'tok-1');
    for (
      var i = 0;
      i < 40 && events.whereType<DeviceInfoUpdated>().isEmpty;
      i++
    ) {
      await settle();
    }
    final info = events.whereType<DeviceInfoUpdated>().single;
    expect(info.model, 'QN55Q6FNA');
    expect(info.macAddress, '64:1c:ae:00:11:22');

    // Reconnecting with the token is silent.
    await adapter.disconnect();
    events.clear();
    await adapter.connect(
      pairing: const PairingRequest(storedCredential: 'tok-1'),
    );
    expect(events.whereType<PairingCompleted>(), isEmpty);
  });

  test(
    'shows the pairing prompt while waiting, and reports a refusal',
    () async {
      tv
        ..approvalDelay = const Duration(milliseconds: 1300)
        ..userAccepts = false;
      final events = <DeviceEvent>[];
      adapter.events.listen(events.add);
      await expectLater(
        adapter.connect(),
        throwsA(
          isA<TvRemoteException>().having(
            (e) => e.code,
            'code',
            TvErrorCode.pairingRejected,
          ),
        ),
      );
      expect(events.whereType<PairingPromptShown>(), hasLength(1));
      expect(adapter.status, ConnectionStatus.disconnected);
    },
  );

  test('keys, pointer and custom key names', () async {
    await adapter.connect();
    await adapter.sendKey(RemoteKey.home);
    await adapter.sendKey(RemoteKey.volumeUp);
    await adapter.movePointer(4.4, -2);
    await adapter.pointerClick();
    await adapter.sendCustom(
      const CustomCommand(
        id: 'c',
        name: 'HDMI 2',
        kind: CustomCommandKind.samsungKey,
        value: 'KEY_HDMI2',
      ),
    );
    expect(
      () => adapter.sendKey(RemoteKey.backspace),
      throwsA(isA<TvRemoteException>()),
    );
    await settle();
    final remote = tv.remote.toList();
    expect(remote.map((p) => p['DataOfCmd']).where((k) => k != null), [
      'KEY_HOME',
      'KEY_VOLUP',
      'KEY_HDMI2',
    ]);
    final move = remote.firstWhere((p) => p['Cmd'] == 'Move');
    expect(move['Position']['x'], 4);
    expect(remote.any((p) => p['Cmd'] == 'LeftClick'), isTrue);
  });

  test('typing follows the TV field and replaces its text', () async {
    await adapter.connect();
    final focus = <bool>[];
    adapter.events
        .where((e) => e is TextFieldFocusChanged)
        .listen((e) => focus.add((e as TextFieldFocusChanged).focused));
    tv.send({'event': 'ms.remote.imeStart', 'data': ''});
    tv.send({
      'event': 'ms.remote.imeUpdate',
      'data': base64.encode(utf8.encode('ab')),
    });
    await settle();
    await adapter.sendText('cd');
    await adapter.deleteText(1);
    await adapter.submitText();
    tv.send({'event': 'ms.remote.imeEnd'});
    await settle();

    final sent = tv.remote
        .where((p) => p['TypeOfRemote'] == 'SendInputString')
        .map((p) => utf8.decode(base64.decode(p['Cmd'] as String)))
        .toList();
    expect(sent, ['abcd', 'abc']);
    expect(tv.remote.last['TypeOfRemote'], 'SendInputEnd');
    expect(focus, [true, false]);
  });

  test('apps, icons and links', () async {
    await adapter.connect();
    final apps = await adapter.listApps();
    expect(apps.map((a) => a.name), ['Netflix', 'YouTube']);
    final yt = apps.firstWhere((a) => a.name == 'YouTube');
    expect(await adapter.fetchAppIcon(yt), [1, 2, 3]);

    await adapter.launchApp(yt.id);
    final exact = await adapter.openContent(
      ContentLink.parse('https://www.netflix.com/title/80100172')!,
    );
    expect(exact, isFalse);
    expect(
      await adapter.openContent(ContentLink.parse('https://example.com/a')!),
      isTrue,
    );
    await settle();
    final launches = tv.messages
        .map((m) => m['params'] as Map<String, dynamic>)
        .where((p) => p['event'] == 'ed.apps.launch')
        .map((p) => p['data'] as Map<String, dynamic>)
        .toList();
    expect(launches.map((d) => d['appId']), [
      '111299001912',
      '3201907018807',
      SamsungAdapter.browserAppId,
    ]);
    expect(launches.last['metaTag'], 'https://example.com/a');
  });

  test('driver identifies a TV from its REST description', () async {
    final device = await SamsungDriver.describeAt(adapter, '127.0.0.1');
    expect(device.id, 'samsung:abc-123');
    expect(device.name, 'Samsung Q6 Series (55)');
    expect(device.macAddress, '64:1c:ae:00:11:22');
  });
}
