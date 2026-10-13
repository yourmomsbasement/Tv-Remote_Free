import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_remote_free/core/adapter/custom_command.dart';
import 'package:tv_remote_free/core/adapter/smart_tv_adapter.dart';
import 'package:tv_remote_free/core/capabilities/device_capabilities.dart';
import 'package:tv_remote_free/core/capabilities/remote_key.dart';
import 'package:tv_remote_free/core/content/content_link.dart';
import 'package:tv_remote_free/core/errors.dart';
import 'package:tv_remote_free/protocols/android_tv/atv_adapter.dart';
import 'package:tv_remote_free/protocols/android_tv/atv_crypto.dart';
import 'package:tv_remote_free/protocols/android_tv/atv_messages.dart';
import 'package:tv_remote_free/protocols/android_tv/protobuf.dart';

/// A mock Android TV implementing both the pairing and the remote port.
class MockAndroidTv {
  MockAndroidTv(this.identity, this.trustedClients);

  final ClientIdentity identity;

  /// Dart's TLS server cannot accept an unverifiable client certificate, so
  /// the mock trusts the test's client certificates explicitly. Whether a
  /// client is *paired* is still decided by [pairedClients].
  final List<ClientIdentity> trustedClients;
  late SecureServerSocket pairingServer;
  late SecureServerSocket remoteServer;
  final pairedClients = <String>{};
  final received = <ProtoMessage>[];
  String? shownPin;
  int supportedFeatures = AtvFeature.requested;
  SecureSocket? remoteSocket;

  SecurityContext get _context {
    final context = SecurityContext()
      ..useCertificateChainBytes(identity.certificatePem.codeUnits)
      ..usePrivateKeyBytes(identity.privateKeyPem.codeUnits);
    for (final client in trustedClients) {
      context.setTrustedCertificatesBytes(client.certificatePem.codeUnits);
    }
    return context;
  }

  Future<void> start() async {
    pairingServer = await SecureServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
      _context,
      requestClientCertificate: true,
    );
    remoteServer = await SecureServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
      _context,
      requestClientCertificate: true,
    );
    pairingServer.listen(_onPairing, onError: (_) {});
    remoteServer.listen(_onRemote, onError: (_) {});
  }

  Future<void> stop() async {
    await pairingServer.close();
    await remoteServer.close();
    remoteSocket?.destroy();
  }

  void _send(Socket s, ProtoWriter m) {
    try {
      s.add(m.toFrame());
    } on Object {
      // Closed by the test.
    }
  }

  static ProtoWriter _outer([int status = Polo.statusOk]) => ProtoWriter()
    ..varint(1, 2)
    ..varint(2, status);

  void _onPairing(SecureSocket socket) {
    final client = socket.peerCertificate!;
    final decoder = ProtoFrameDecoder();
    socket.listen((chunk) {
      for (final frame in decoder.add(chunk)) {
        final m = ProtoMessage.decode(frame);
        if (m.has(Polo.pairingRequest)) {
          expect(m.message(Polo.pairingRequest)!.string(1), 'atvremote');
          _send(
            socket,
            _outer()
              ..message(Polo.pairingRequestAck, ProtoWriter()..string(1, 'tv')),
          );
        } else if (m.has(Polo.options)) {
          _send(
            socket,
            _outer()..message(Polo.options, ProtoWriter()..varint(3, 1)),
          );
        } else if (m.has(Polo.configuration)) {
          shownPin = AtvCrypto.pinFor(
            client: AtvCrypto.publicKeyFromCertificateDer(client.der),
            server: AtvCrypto.publicKeyFromCertificatePem(
              identity.certificatePem,
            ),
            nonce: Random().nextInt(0x10000),
          );
          _send(
            socket,
            _outer()..message(Polo.configurationAck, ProtoWriter()),
          );
        } else if (m.has(Polo.secret)) {
          final expected = AtvCrypto.pairingSecret(
            client: AtvCrypto.publicKeyFromCertificateDer(client.der),
            server: AtvCrypto.publicKeyFromCertificatePem(
              identity.certificatePem,
            ),
            pin: shownPin!,
          );
          final got = m.message(Polo.secret)!.bytes(1);
          if (expected != null && got != null && _eq(expected, got)) {
            pairedClients.add(AtvCrypto.sha256Hex(client.der));
            _send(
              socket,
              _outer()..message(Polo.secretAck, ProtoWriter()..bytes(1, got)),
            );
          } else {
            _send(socket, _outer(402));
          }
        }
      }
    }, onError: (_) {});
  }

  static bool _eq(List<int> a, List<int> b) =>
      a.length == b.length &&
      Iterable.generate(a.length).every((i) => a[i] == b[i]);

  void _onRemote(SecureSocket socket) {
    final cert = socket.peerCertificate;
    if (cert == null ||
        !pairedClients.contains(AtvCrypto.sha256Hex(cert.der))) {
      socket.destroy();
      return;
    }
    remoteSocket = socket;
    final decoder = ProtoFrameDecoder();
    socket.listen((chunk) {
      for (final frame in decoder.add(chunk)) {
        final m = ProtoMessage.decode(frame);
        received.add(m);
        if (m.has(RemoteMsg.configure)) {
          _send(
            socket,
            ProtoWriter()..message(RemoteMsg.setActive, ProtoWriter()),
          );
        } else if (m.has(RemoteMsg.setActive)) {
          _send(
            socket,
            ProtoWriter()
              ..message(RemoteMsg.start, ProtoWriter()..boolean(1, true)),
          );
        }
      }
    }, onError: (_) {});
    _send(
      socket,
      ProtoWriter()..message(
        RemoteMsg.configure,
        ProtoWriter()
          ..varint(1, supportedFeatures)
          ..message(
            2,
            ProtoWriter()
              ..string(1, 'SHIELD Android TV')
              ..string(2, 'NVIDIA'),
          ),
      ),
    );
  }

  void sendRemote(ProtoWriter m) => _send(remoteSocket!, m);

  List<ProtoMessage> sent(int field) =>
      received.where((m) => m.has(field)).toList();
}

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 80));

void main() {
  late ClientIdentity tvIdentity;
  late ClientIdentity clientIdentity;
  late MockAndroidTv tv;
  late List<DeviceEvent> events;

  setUpAll(() async {
    tvIdentity = await AtvCrypto.generateIdentity(keySize: 1024);
    clientIdentity = await AtvCrypto.generateIdentity(keySize: 1024);
  });

  setUp(() async {
    tv = MockAndroidTv(tvIdentity, [clientIdentity]);
    await tv.start();
    events = [];
  });

  tearDown(() => tv.stop());

  AndroidTvAdapter newAdapter() {
    final adapter = AndroidTvAdapter(
      host: '127.0.0.1',
      pairingPort: tv.pairingServer.port,
      remotePort: tv.remoteServer.port,
      responseTimeout: const Duration(seconds: 3),
      identityFactory: () async => clientIdentity,
    );
    adapter.events.listen(events.add);
    return adapter;
  }

  /// Connects, typing [pin] (or the TV's real code) when asked.
  Future<String> pairAndConnect(
    AndroidTvAdapter adapter, {
    List<String> wrongPins = const [],
  }) async {
    final prompt = adapter.events.firstWhere(
      (e) => e is PairingPromptShown && e.needsPin,
    );
    final credential = adapter.events
        .firstWhere((e) => e is PairingCompleted)
        .then((e) => (e as PairingCompleted).credential);
    final connecting = adapter.connect();
    await prompt;
    for (final pin in wrongPins) {
      await expectLater(
        adapter.pair(PairingRequest(pin: pin)),
        throwsA(
          isA<TvRemoteException>().having(
            (e) => e.code,
            'code',
            TvErrorCode.pairingRejected,
          ),
        ),
      );
    }
    await adapter.pair(PairingRequest(pin: tv.shownPin!.toLowerCase()));
    await connecting;
    return credential;
  }

  test('pairs with the on-screen code and connects', () async {
    final adapter = newAdapter();
    final credential = await pairAndConnect(adapter);
    expect(adapter.status, ConnectionStatus.connected);
    final stored = AtvCredential.tryDecode(credential)!;
    expect(stored.serverCertificateSha256, hasLength(64));
    expect(tv.pairedClients, hasLength(1));
    final caps = await adapter.getCapabilities();
    expect(caps.navigation, isTrue);
    expect(caps.textInputStrategy, TextInputStrategy.nativeTextApi);
    expect(caps.appLaunch, isTrue);
    expect(caps.appList, isFalse);
    expect(caps.pointer, isFalse);
    // Feature negotiation echoes what both sides support.
    expect(
      tv.sent(RemoteMsg.configure).single.message(1)!.integer(1),
      AtvFeature.requested,
    );
    await settle();
    expect(
      events.whereType<DeviceInfoUpdated>().first.model,
      'NVIDIA SHIELD Android TV',
    );
    await adapter.dispose();
  });

  test('a mistyped code is rejected locally and can be retried', () async {
    final adapter = newAdapter();
    await pairAndConnect(adapter, wrongPins: ['000000', 'ZZZZZZ', '12']);
    expect(adapter.status, ConnectionStatus.connected);
    await adapter.dispose();
  });

  test('a stored credential reconnects without pairing', () async {
    final first = newAdapter();
    final credential = await pairAndConnect(first);
    await first.dispose();

    final second = newAdapter();
    await second.connect(pairing: PairingRequest(storedCredential: credential));
    expect(second.status, ConnectionStatus.connected);
    expect(events.whereType<PairingPromptShown>(), hasLength(1));
    await second.dispose();
  });

  test('a credential the TV forgot asks to pair again', () async {
    final first = newAdapter();
    final credential = await pairAndConnect(first);
    await first.dispose();
    tv.pairedClients.clear();

    final second = newAdapter();
    await expectLater(
      second.connect(pairing: PairingRequest(storedCredential: credential)),
      throwsA(
        isA<TvRemoteException>().having(
          (e) => e.code,
          'code',
          TvErrorCode.pairingRequired,
        ),
      ),
    );
    await second.dispose();
  });

  test('a different TV certificate is refused (pinning)', () async {
    final first = newAdapter();
    final credential = AtvCredential.tryDecode(await pairAndConnect(first))!;
    await first.dispose();
    final tampered = AtvCredential(
      certificatePem: credential.certificatePem,
      privateKeyPem: credential.privateKeyPem,
      serverCertificateSha256: '0' * 64,
    ).encode();

    final second = newAdapter();
    await expectLater(
      second.connect(pairing: PairingRequest(storedCredential: tampered)),
      throwsA(
        isA<TvRemoteException>().having(
          (e) => e.code,
          'code',
          TvErrorCode.pairingRequired,
        ),
      ),
    );
    await second.dispose();
  });

  test('keys, app links and text reach the TV', () async {
    final adapter = newAdapter();
    await pairAndConnect(adapter);
    await adapter.sendKey(RemoteKey.up);
    await adapter.sendKey(RemoteKey.select);
    await adapter.launchApp('https://www.netflix.com/title');
    // The TV reports a focused field and its counters.
    tv.sendRemote(
      ProtoWriter()..message(
        RemoteMsg.imeBatchEdit,
        ProtoWriter()
          ..varint(1, 5)
          ..varint(2, 9),
      ),
    );
    await settle();
    await adapter.sendText('hel');
    await adapter.sendText('lo');
    await adapter.deleteText(1);
    await adapter.submitText();
    await settle();

    final keys = tv
        .sent(RemoteMsg.keyInject)
        .map((m) => m.message(RemoteMsg.keyInject)!.integer(1));
    expect(keys, [19, 23, 66]);
    expect(
      tv
          .sent(RemoteMsg.appLinkLaunch)
          .single
          .message(RemoteMsg.appLinkLaunch)!
          .string(1),
      'https://www.netflix.com/title',
    );
    final edits = tv.sent(RemoteMsg.imeBatchEdit).map((m) {
      final e = m.message(RemoteMsg.imeBatchEdit)!;
      expect((e.integer(1), e.integer(2)), (5, 9));
      return e.messages(3).single.message(2)!.string(3);
    });
    // Each edit carries the whole field value.
    expect(edits, ['hel', 'hello', 'hell']);
    await adapter.dispose();
  });

  test('deleting the whole field falls back to Delete key presses', () async {
    final adapter = newAdapter();
    await pairAndConnect(adapter);
    await adapter.sendText('ab');
    await adapter.deleteText(2);
    await settle();
    final keys = tv
        .sent(RemoteMsg.keyInject)
        .map((m) => m.message(RemoteMsg.keyInject)!.integer(1));
    expect(keys, [67, 67]);
    await adapter.dispose();
  });

  test('keyboard requests become focus events', () async {
    final adapter = newAdapter();
    await pairAndConnect(adapter);
    tv.sendRemote(
      ProtoWriter()..message(
        RemoteMsg.imeShowRequest,
        ProtoWriter()..message(2, ProtoWriter()..string(2, 'abc')),
      ),
    );
    await settle();
    final focus = events.whereType<TextFieldFocusChanged>().toList();
    expect(focus.map((e) => e.focused), [false, true]);
    // Typing continues from the field's existing content.
    await adapter.sendText('d');
    await settle();
    expect(
      tv
          .sent(RemoteMsg.imeBatchEdit)
          .last
          .message(RemoteMsg.imeBatchEdit)!
          .messages(3)
          .single
          .message(2)!
          .string(3),
      'abcd',
    );
    await adapter.dispose();
  });

  test('answers pings and reports volume', () async {
    final adapter = newAdapter();
    await pairAndConnect(adapter);
    tv.sendRemote(
      ProtoWriter()
        ..message(RemoteMsg.pingRequest, ProtoWriter()..varint(1, 42)),
    );
    tv.sendRemote(
      ProtoWriter()..message(
        RemoteMsg.setVolumeLevel,
        ProtoWriter()
          ..varint(6, 15)
          ..varint(7, 6)
          ..boolean(8, false),
      ),
    );
    await settle();
    expect(
      tv
          .sent(RemoteMsg.pingResponse)
          .single
          .message(RemoteMsg.pingResponse)!
          .integer(1),
      42,
    );
    final volume = events.whereType<VolumeChanged>().single;
    expect(volume.level, 40);
    expect(volume.muted, isFalse);
    await adapter.dispose();
  });

  test('features the TV lacks are not advertised', () async {
    tv.supportedFeatures = AtvFeature.ping | AtvFeature.key;
    final adapter = newAdapter();
    await pairAndConnect(adapter);
    final caps = await adapter.getCapabilities();
    expect(caps.textInput, isFalse);
    expect(caps.appLaunch, isFalse);
    expect(() => adapter.sendText('x'), throwsA(isA<TvRemoteException>()));
    await adapter.dispose();
  });

  test('the TV dropping the connection is reported', () async {
    final adapter = newAdapter();
    await pairAndConnect(adapter);
    tv.remoteSocket!.destroy();
    await settle();
    expect(adapter.status, ConnectionStatus.disconnected);
    await adapter.dispose();
  });

  test('unreachable TV fails with a structured error', () async {
    final port = tv.remoteServer.port;
    await tv.stop();
    final adapter = AndroidTvAdapter(host: '127.0.0.1', remotePort: port);
    final credential = AtvCredential(
      certificatePem: tvIdentity.certificatePem,
      privateKeyPem: tvIdentity.privateKeyPem,
      serverCertificateSha256: '0' * 64,
    ).encode();
    await expectLater(
      adapter.connect(pairing: PairingRequest(storedCredential: credential)),
      throwsA(
        isA<TvRemoteException>().having(
          (e) => e.code,
          'code',
          TvErrorCode.unreachable,
        ),
      ),
    );
    await adapter.dispose();
  });

  test('pairing secret matches the TV-side code derivation', () async {
    final c = AtvCrypto.publicKeyFromCertificatePem(
      clientIdentity.certificatePem,
    );
    final s = AtvCrypto.publicKeyFromCertificatePem(tvIdentity.certificatePem);
    for (final nonce in [0, 1, 0xABCD, 0xFFFF]) {
      final pin = AtvCrypto.pinFor(client: c, server: s, nonce: nonce);
      expect(
        AtvCrypto.pairingSecret(client: c, server: s, pin: pin),
        hasLength(32),
      );
      // Changing the check byte invalidates it.
      final bad =
          ((int.parse(pin.substring(0, 2), radix: 16) + 1) % 256)
              .toRadixString(16)
              .padLeft(2, '0') +
          pin.substring(2);
      expect(AtvCrypto.pairingSecret(client: c, server: s, pin: bad), isNull);
    }
  });

  test('reports the foreground app', () async {
    final adapter = newAdapter();
    await pairAndConnect(adapter);
    tv.sendRemote(
      ProtoWriter()..message(
        RemoteMsg.imeKeyInject,
        ProtoWriter()
          ..message(1, ProtoWriter()..string(12, 'com.netflix.ninja')),
      ),
    );
    await settle();
    expect(
      events.whereType<ActivityChanged>().single.activity.appId,
      'com.netflix.ninja',
    );
    await adapter.dispose();
  });

  test('opens any shared link as an app link', () async {
    final adapter = newAdapter();
    await pairAndConnect(adapter);
    expect(
      await adapter.openContent(
        ContentLink.parse('https://www.disneyplus.com/video/abc')!,
      ),
      isTrue,
    );
    await settle();
    expect(
      tv
          .sent(RemoteMsg.appLinkLaunch)
          .single
          .message(RemoteMsg.appLinkLaunch)!
          .string(1),
      'https://www.disneyplus.com/video/abc',
    );
    await adapter.dispose();
  });

  test('runs custom key codes and links', () async {
    final adapter = newAdapter();
    await pairAndConnect(adapter);
    await adapter.sendCustom(
      const CustomCommand(
        id: 'a',
        name: 'Red',
        kind: CustomCommandKind.androidKeyCode,
        value: '183',
      ),
    );
    await adapter.sendCustom(
      const CustomCommand(
        id: 'b',
        name: 'YT',
        kind: CustomCommandKind.androidLink,
        value: 'https://www.youtube.com',
      ),
    );
    await settle();
    expect(
      tv
          .sent(RemoteMsg.keyInject)
          .last
          .message(RemoteMsg.keyInject)!
          .integer(1),
      183,
    );
    expect(
      tv
          .sent(RemoteMsg.appLinkLaunch)
          .last
          .message(RemoteMsg.appLinkLaunch)!
          .string(1),
      'https://www.youtube.com',
    );
    await adapter.dispose();
  });
}
