import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_remote_free/core/adapter/smart_tv_adapter.dart';
import 'package:tv_remote_free/core/capabilities/device_capabilities.dart';
import 'package:tv_remote_free/core/capabilities/remote_key.dart';
import 'package:tv_remote_free/core/errors.dart';
import 'package:tv_remote_free/protocols/lg_webos/webos_adapter.dart';

/// A mock webOS TV speaking enough SSAP to exercise the adapter.
class MockWebOsTv {
  late HttpServer server;
  WebSocket? main;
  final requests = <Map<String, dynamic>>[];
  final pointerMessages = <String>[];
  String issuedKey = 'key-123';
  bool userAccepts = true;
  Set<String> knownKeys = {};
  String? keyboardSubscriptionId;
  final subscriptionIds = <String, String>{};

  void push(String uri, Map<String, Object?> payload) => _send(main!, {
    'type': 'response',
    'id': subscriptionIds[uri],
    'payload': payload,
  });

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      if (req.uri.path.startsWith('/icons/')) {
        req.response.headers.contentType = ContentType('image', 'png');
        req.response.add([0x89, 0x50, 0x4E, 0x47]);
        await req.response.close();
        return;
      }
      final socket = await WebSocketTransformer.upgrade(req);
      if (req.uri.path == '/pointer') {
        socket.listen((m) => pointerMessages.add(m as String));
        return;
      }
      main = socket;
      socket.listen((data) => _onMain(socket, jsonDecode(data as String)));
    });
  }

  int get port => server.port;

  void _send(WebSocket s, Map<String, Object?> m) {
    try {
      s.add(jsonEncode(m));
    } on StateError {
      // The test closed this socket; late replies are dropped.
    }
  }

  void _onMain(WebSocket s, Map<String, dynamic> m) {
    final id = m['id'];
    if (m['type'] == 'register') {
      final key = m['payload']['client-key'];
      if (key != null && knownKeys.contains(key)) {
        _send(s, {
          'type': 'registered',
          'id': id,
          'payload': {'client-key': key},
        });
        return;
      }
      if (key != null) {
        _send(s, {
          'type': 'error',
          'id': id,
          'error': '401 insufficient permissions',
        });
        return;
      }
      _send(s, {
        'type': 'response',
        'id': id,
        'payload': {'pairingType': 'PROMPT', 'returnValue': true},
      });
      Timer(const Duration(milliseconds: 20), () {
        if (userAccepts) {
          knownKeys.add(issuedKey);
          _send(s, {
            'type': 'registered',
            'id': id,
            'payload': {'client-key': issuedKey},
          });
        } else {
          _send(s, {'type': 'error', 'id': id, 'error': '403 cancelled'});
        }
      });
      return;
    }
    requests.add(m);
    final uri = m['uri'] as String;
    if (m['type'] == 'subscribe') {
      if (uri.endsWith('registerRemoteKeyboard')) keyboardSubscriptionId = id;
      subscriptionIds[uri] = id as String;
      _send(s, {
        'type': 'response',
        'id': id,
        'payload': {'subscribed': true, 'returnValue': true},
      });
      return;
    }
    final payload = switch (uri) {
      'ssap://com.webos.service.networkinput/getPointerInputSocket' => {
        'returnValue': true,
        'socketPath': 'ws://127.0.0.1:$port/pointer',
      },
      'ssap://com.webos.service.connectionmanager/getinfo' => {
        'returnValue': true,
        'wiredInfo': {'macAddress': '78:5d:c8:00:11:22'},
      },
      'ssap://com.webos.applicationManager/listLaunchPoints' => {
        'returnValue': true,
        'launchPoints': [
          {
            'id': 'netflix',
            'title': 'Netflix',
            'icon': 'http://tv/n.png',
            'largeIcon': 'http://127.0.0.1:$port/icons/netflix.png',
          },
          {'id': 'youtube.leanback.v4', 'title': 'YouTube'},
        ],
      },
      'ssap://unknown/thing' => null,
      _ => {'returnValue': true},
    };
    if (payload == null) {
      _send(s, {
        'type': 'error',
        'id': id,
        'error': '404 no such service or method',
      });
    } else {
      _send(s, {'type': 'response', 'id': id, 'payload': payload});
    }
  }

  void focusTextField({required bool focused, bool hidden = false}) {
    _send(main!, {
      'type': 'response',
      'id': keyboardSubscriptionId,
      'payload': {
        'currentWidget': {
          'focus': focused,
          'contentType': hidden ? 'password' : 'text',
          'hiddenText': hidden,
        },
      },
    });
  }

  List<Map<String, dynamic>> requestsTo(String uri) =>
      requests.where((r) => r['uri'] == uri).toList();
}

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 50));

void main() {
  late MockWebOsTv tv;
  late WebOsAdapter adapter;
  late List<DeviceEvent> events;

  setUp(() async {
    tv = MockWebOsTv();
    await tv.start();
    adapter = WebOsAdapter(
      host: '127.0.0.1',
      endpoints: [Uri.parse('ws://127.0.0.1:${tv.port}/')],
      pairingTimeout: const Duration(seconds: 2),
    );
    events = [];
    adapter.events.listen(events.add);
  });

  tearDown(() async {
    await adapter.dispose();
    await tv.server.close(force: true);
  });

  test('first connection prompts on the TV and returns a client key', () async {
    await adapter.connect();
    await settle();
    expect(adapter.status, ConnectionStatus.connected);
    expect(events.whereType<PairingPromptShown>(), hasLength(1));
    expect(events.whereType<PairingCompleted>().single.credential, 'key-123');
    final caps = await adapter.getCapabilities();
    expect(caps.textInputStrategy, TextInputStrategy.nativeTextApi);
    expect(caps.textFieldDetection, isTrue);
    expect(caps.pointer, isTrue);
  });

  test('a stored key reconnects without prompting', () async {
    tv.knownKeys.add('saved');
    await adapter.connect(
      pairing: const PairingRequest(storedCredential: 'saved'),
    );
    await settle();
    expect(adapter.status, ConnectionStatus.connected);
    expect(events.whereType<PairingPromptShown>(), isEmpty);
    expect(events.whereType<PairingCompleted>(), isEmpty);
  });

  test('declining on the TV is reported as pairingRejected', () async {
    tv.userAccepts = false;
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
    expect(adapter.status, ConnectionStatus.disconnected);
  });

  test('a forgotten stored key asks the user to pair again', () async {
    await expectLater(
      adapter.connect(pairing: const PairingRequest(storedCredential: 'stale')),
      throwsA(
        isA<TvRemoteException>().having(
          (e) => e.code,
          'code',
          TvErrorCode.pairingRequired,
        ),
      ),
    );
  });

  test('reads the MAC address for Wake-on-LAN after connecting', () async {
    await adapter.connect();
    await settle();
    expect(
      events.whereType<DeviceInfoUpdated>().map((e) => e.macAddress),
      contains('78:5d:c8:00:11:22'),
    );
  });

  test('text uses the IME insert/delete/enter API', () async {
    await adapter.connect();
    await adapter.sendText('héllo 😀');
    await adapter.deleteText(2);
    await adapter.submitText();
    final insert = tv
        .requestsTo('ssap://com.webos.service.ime/insertText')
        .single;
    expect(insert['payload'], {'text': 'héllo 😀', 'replace': 0});
    expect(
      tv
          .requestsTo('ssap://com.webos.service.ime/deleteCharacters')
          .single['payload'],
      {'count': 2},
    );
    expect(
      tv.requestsTo('ssap://com.webos.service.ime/sendEnterKey'),
      hasLength(1),
    );
  });

  test('TV text-field focus becomes a TextFieldFocusChanged event', () async {
    await adapter.connect();
    await settle();
    tv.focusTextField(focused: true, hidden: true);
    await settle();
    final focus = events.whereType<TextFieldFocusChanged>().single;
    expect(focus.focused, isTrue);
    expect(focus.sensitive, isTrue);
  });

  test('navigation keys and the pointer use the pointer socket', () async {
    await adapter.connect();
    await adapter.sendKey(RemoteKey.up);
    await adapter.sendKey(RemoteKey.select);
    await adapter.movePointer(10.4, -3.6);
    await adapter.pointerClick();
    await adapter.scroll(0, -12.6);
    await settle();
    expect(tv.pointerMessages, [
      'type:button\nname:UP\n\n',
      'type:button\nname:ENTER\n\n',
      'type:move\ndx:10\ndy:-4\ndown:0\n\n',
      'type:click\n\n',
      'type:scroll\ndx:0\ndy:-13\n\n',
    ]);
    // The pointer socket is opened once and reused.
    expect(
      tv.requestsTo(
        'ssap://com.webos.service.networkinput/getPointerInputSocket',
      ),
      hasLength(1),
    );
  });

  test('power off, volume and app launch use SSAP requests', () async {
    await adapter.connect();
    await adapter.sendKey(RemoteKey.powerOff);
    await adapter.setVolume(150);
    await adapter.launchApp('netflix');
    expect(tv.requestsTo('ssap://system/turnOff'), hasLength(1));
    expect(tv.requestsTo('ssap://audio/setVolume').single['payload'], {
      'volume': 100,
    });
    expect(tv.requestsTo('ssap://system.launcher/launch').single['payload'], {
      'id': 'netflix',
    });
  });

  test('lists launch points as apps', () async {
    await adapter.connect();
    final apps = await adapter.listApps();
    expect(apps.map((a) => a.id), ['netflix', 'youtube.leanback.v4']);
    // The largest icon is preferred.
    expect(apps.first.iconUrl, 'http://127.0.0.1:${tv.port}/icons/netflix.png');
    expect(await adapter.fetchAppIcon(apps.first), [0x89, 0x50, 0x4E, 0x47]);
    // No reachable icon: null, not an error.
    expect(await adapter.fetchAppIcon(apps.last), isNull);
  });

  test('the TV dropping the socket reports a disconnect', () async {
    await adapter.connect();
    await tv.main!.close();
    await settle();
    expect(adapter.status, ConnectionStatus.disconnected);
    expect(
      events.whereType<ConnectionStatusChanged>().last.status,
      ConnectionStatus.disconnected,
    );
    expect(
      () => adapter.sendKey(RemoteKey.home),
      throwsA(isA<TvRemoteException>()),
    );
  });

  test('unreachable TV fails with a structured error', () async {
    await tv.server.close(force: true);
    await expectLater(
      adapter.connect(),
      throwsA(
        isA<TvRemoteException>().having(
          (e) => e.code,
          'code',
          TvErrorCode.unreachable,
        ),
      ),
    );
  });

  test('reports the foreground app and playback state', () async {
    await adapter.connect();
    await settle();
    tv.push('ssap://com.webos.applicationManager/getForegroundAppInfo', {
      'appId': 'netflix',
      'returnValue': true,
    });
    tv.push('ssap://com.webos.media/getForegroundAppInfo', {
      'foregroundAppInfo': [
        {'appId': 'netflix', 'playState': 'playing'},
      ],
    });
    await settle();
    final activity = events.whereType<ActivityChanged>().last.activity;
    expect(activity.appId, 'netflix');
    expect(activity.appName, 'Netflix'); // title from the app list
    expect(activity.state, PlaybackState.playing);
    expect(activity.hasTimeline, isFalse);

    tv.push('ssap://com.webos.media/getForegroundAppInfo', {
      'foregroundAppInfo': <Object>[],
    });
    await settle();
    expect(events.whereType<ActivityChanged>().last.activity.hasMedia, isFalse);
  });
}
