import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../../core/adapter/smart_tv_adapter.dart';
import '../../core/capabilities/device_capabilities.dart';
import '../../core/capabilities/remote_key.dart';
import '../../core/content/content_link.dart';
import '../../core/errors.dart';
import 'atv_crypto.dart';
import 'atv_keys.dart';
import 'atv_messages.dart';
import 'protobuf.dart';

/// A TLS connection carrying length-prefixed protobuf messages.
class _Link {
  _Link(this.socket, {required this.onMessage, required this.onClosed}) {
    socket.listen(
      (chunk) {
        try {
          for (final frame in _decoder.add(chunk)) {
            onMessage(ProtoMessage.decode(frame));
          }
        } on FormatException {
          socket.destroy();
        }
      },
      onDone: () => onClosed(),
      onError: (Object _) => onClosed(),
      cancelOnError: true,
    );
  }

  final SecureSocket socket;
  final void Function(ProtoMessage) onMessage;
  final void Function() onClosed;
  final _decoder = ProtoFrameDecoder();

  void send(ProtoWriter message) => socket.add(message.toFrame());

  void close() => socket.destroy();
}

/// Android TV / Google TV adapter for the "Android TV Remote Service" (v2),
/// the protocol used by Google's own phone remote.
///
/// Pairing (port 6467): the app presents a self-signed client certificate,
/// the TV shows a 6-digit hex code, and the app proves it saw the code by
/// hashing it with both public keys. The TV then trusts that certificate on
/// the remote port (6466). The TV's certificate is pinned at pairing time.
class AndroidTvAdapter implements SmartTVAdapter {
  AndroidTvAdapter({
    required this.host,
    this.remotePort = 6466,
    this.pairingPort = 6467,
    this.clientName = 'TV Remote Free',
    this.keySize = 2048,
    this.connectTimeout = const Duration(seconds: 5),
    this.responseTimeout = const Duration(seconds: 10),
    this.pinTimeout = const Duration(minutes: 3),
    this.idleTimeout = const Duration(seconds: 16),
    this.identityFactory,
  });

  final String host;
  final int remotePort;
  final int pairingPort;

  /// Shown on the TV's pairing screen.
  final String clientName;
  final int keySize;
  final Duration connectTimeout;
  final Duration responseTimeout;
  final Duration pinTimeout;

  /// The TV pings every 5 s; silence this long means the link is dead.
  final Duration idleTimeout;

  /// Creates the client certificate for a new pairing. Defaults to a fresh
  /// RSA key of [keySize] bits.
  final Future<ClientIdentity> Function()? identityFactory;

  final _events = StreamController<DeviceEvent>.broadcast();
  ConnectionStatus _status = ConnectionStatus.disconnected;
  DeviceCapabilities _capabilities = DeviceCapabilities.none;

  _Link? _remote;
  Completer<void>? _remoteStarted;
  Timer? _idleTimer;
  int _features = AtvFeature.requested;
  int _imeCounter = 0;
  int _fieldCounter = 0;

  /// What the focused TV field contains, as far as we know. The IME edit
  /// message sets the whole field value, so inserts and deletes are applied
  /// here first and the result is sent.
  String _fieldText = '';

  _PairingSession? _pairing;

  @override
  String get protocol => 'android_tv';

  @override
  ConnectionStatus get status => _status;

  @override
  Stream<DeviceEvent> get events => _events.stream;

  void _emit(DeviceEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  void _setStatus(ConnectionStatus status, {Object? error}) {
    if (_status == status && error == null) return;
    _status = status;
    _emit(ConnectionStatusChanged(status, error: error));
  }

  @override
  Future<void> connect({
    PairingRequest pairing = const PairingRequest(),
  }) async {
    await _closeLinks();
    _setStatus(ConnectionStatus.connecting);
    try {
      var credential = AtvCredential.tryDecode(pairing.storedCredential);
      if (credential == null) {
        credential = await _pair();
        _emit(PairingCompleted(credential.encode()));
      }
      await _openRemote(
        credential,
        storedCredential: pairing.storedCredential != null,
      );
      _capabilities = _buildCapabilities();
      _setStatus(ConnectionStatus.connected);
    } catch (e) {
      await _closeLinks();
      _setStatus(ConnectionStatus.disconnected, error: e);
      rethrow;
    }
  }

  // ---------------------------------------------------------------- pairing

  Future<AtvCredential> _pair() async {
    final identity =
        await (identityFactory?.call() ??
            AtvCrypto.generateIdentity(keySize: keySize));
    final session = _pairing = _PairingSession(identity);
    try {
      final socket = await _secureConnect(
        pairingPort,
        identity,
        onCertificate: (cert) {
          session.serverCertificateDer = cert.der;
          return true; // Authenticated by the PIN hash below.
        },
      );
      session.link = _Link(
        socket,
        onMessage: session.onMessage,
        onClosed: session.onClosed,
      );
      session.link!.send(Polo.pairingRequestMessage(clientName));
      await session.configured.future.timeout(
        responseTimeout,
        onTimeout: () => throw const TvRemoteException(
          TvErrorCode.timeout,
          'The TV did not start pairing',
        ),
      );

      _setStatus(ConnectionStatus.awaitingPairing);
      _emit(const PairingPromptShown(needsPin: true));

      await session.paired.future.timeout(
        pinTimeout,
        onTimeout: () => throw const TvRemoteException(
          TvErrorCode.timeout,
          'Pairing timed out. Try again.',
        ),
      );
      final der = session.serverCertificateDer;
      if (der == null) {
        throw const TvRemoteException(
          TvErrorCode.protocol,
          'The TV did not present a certificate',
        );
      }
      return AtvCredential(
        certificatePem: identity.certificatePem,
        privateKeyPem: identity.privateKeyPem,
        serverCertificateSha256: AtvCrypto.sha256Hex(der),
      );
    } finally {
      session.link?.close();
      _pairing = null;
    }
  }

  /// Completes pairing with the code shown on the TV. A code that does not
  /// match is rejected locally and the user can retry.
  @override
  Future<void> pair(PairingRequest request) async {
    final session = _pairing;
    final pin = request.pin?.trim().toUpperCase();
    if (session == null || !session.configured.isCompleted) {
      throw const TvRemoteException(
        TvErrorCode.protocol,
        'The TV is not waiting for a code',
      );
    }
    if (pin == null || !AtvCrypto.isValidPin(pin)) {
      throw const TvRemoteException(
        TvErrorCode.pairingRejected,
        'Enter the 6-character code shown on the TV',
      );
    }
    final secret = AtvCrypto.pairingSecret(
      client: AtvCrypto.publicKeyFromCertificatePem(
        session.identity.certificatePem,
      ),
      server: AtvCrypto.publicKeyFromCertificateDer(
        session.serverCertificateDer!,
      ),
      pin: pin,
    );
    if (secret == null) {
      throw const TvRemoteException(
        TvErrorCode.pairingRejected,
        'That code does not match. Check the code on the TV.',
      );
    }
    session.secretAck = Completer<void>();
    session.link!.send(Polo.secretMessage(secret));
    await session.secretAck!.future.timeout(
      responseTimeout,
      onTimeout: () => throw const TvRemoteException(
        TvErrorCode.timeout,
        'The TV did not confirm the code',
      ),
    );
    if (!session.paired.isCompleted) session.paired.complete();
  }

  // ----------------------------------------------------------------- remote

  Future<SecureSocket> _secureConnect(
    int port,
    ClientIdentity identity, {
    required bool Function(X509Certificate) onCertificate,
  }) async {
    final context = SecurityContext(withTrustedRoots: false)
      ..useCertificateChainBytes(identity.certificatePem.codeUnits)
      ..usePrivateKeyBytes(identity.privateKeyPem.codeUnits);
    try {
      return await SecureSocket.connect(
        host,
        port,
        context: context,
        onBadCertificate: onCertificate,
        timeout: connectTimeout,
      ).timeout(connectTimeout + const Duration(seconds: 2));
    } on HandshakeException {
      rethrow;
    } on SocketException catch (e) {
      throw TvRemoteException(
        TvErrorCode.unreachable,
        'Cannot reach Android TV at $host',
        cause: e,
      );
    } on TimeoutException catch (e) {
      throw TvRemoteException(
        TvErrorCode.unreachable,
        'Cannot reach Android TV at $host',
        cause: e,
      );
    }
  }

  Future<void> _openRemote(
    AtvCredential credential, {
    required bool storedCredential,
  }) async {
    final identity = ClientIdentity(
      credential.certificatePem,
      credential.privateKeyPem,
    );
    final SecureSocket socket;
    try {
      socket = await _secureConnect(
        remotePort,
        identity,
        onCertificate: (cert) =>
            AtvCrypto.sha256Hex(cert.der) == credential.serverCertificateSha256,
      );
    } on HandshakeException catch (e) {
      throw TvRemoteException(
        TvErrorCode.pairingRequired,
        'The TV no longer recognises this phone. Pair again.',
        cause: e,
      );
    }
    final started = _remoteStarted = Completer<void>();
    late final _Link link;
    link = _remote = _Link(
      socket,
      onMessage: _onRemoteMessage,
      onClosed: () => _onRemoteClosed(link),
    );
    _resetIdleTimer();
    try {
      await started.future.timeout(responseTimeout);
    } on TimeoutException {
      throw const TvRemoteException(
        TvErrorCode.timeout,
        'The TV did not finish connecting',
      );
    } on TvRemoteException catch (e) {
      // The TV hangs up immediately on certificates it has not paired.
      if (storedCredential && e.code == TvErrorCode.unreachable) {
        throw TvRemoteException(
          TvErrorCode.pairingRequired,
          'The TV no longer recognises this phone. Pair again.',
          cause: e,
        );
      }
      rethrow;
    } finally {
      _remoteStarted = null;
    }
  }

  void _onRemoteMessage(ProtoMessage message) {
    _resetIdleTimer();
    final link = _remote;
    if (link == null) return;

    if (message.message(RemoteMsg.configure) case final configure?) {
      _features = AtvFeature.requested & (configure.integer(1) ?? 0);
      link.send(RemoteMsg.configureReply(_features));
      final info = configure.message(2);
      final model = [
        info?.string(2),
        info?.string(1),
      ].whereType<String>().where((s) => s.isNotEmpty).join(' ');
      if (model.isNotEmpty) _emit(DeviceInfoUpdated(model: model));
    } else if (message.has(RemoteMsg.setActive)) {
      link.send(RemoteMsg.setActiveReply(_features));
    } else if (message.message(RemoteMsg.pingRequest) case final ping?) {
      link.send(RemoteMsg.pingReply(ping.integer(1) ?? 0));
    } else if (message.has(RemoteMsg.start)) {
      final started = _remoteStarted;
      if (started != null && !started.isCompleted) started.complete();
    } else if (message.message(RemoteMsg.imeBatchEdit) case final edit?) {
      _onImeState(
        imeCounter: edit.integer(1),
        fieldCounter: edit.integer(2),
        value: edit.messages(3).lastOrNull?.message(2)?.string(3),
      );
    } else if (message.message(RemoteMsg.imeKeyInject) case final inject?) {
      // Sent when the foreground app changes: app_info.app_package.
      final package = inject.message(1)?.string(12);
      if (package != null && package.isNotEmpty) {
        _emit(
          ActivityChanged(
            MediaActivity(
              appId: package,
              appName: package,
              receivedAt: DateTime.now(),
            ),
          ),
        );
      }
    } else if (message.message(RemoteMsg.imeShowRequest) case final show?) {
      final field = show.message(2);
      // A keyboard is up on the TV: a (new) text field has focus. Emit a
      // blur first so listeners see each field as a fresh focus.
      _emit(const TextFieldFocusChanged(focused: false));
      _fieldText = field?.string(2) ?? '';
      _emit(const TextFieldFocusChanged(focused: true));
    } else if (message.message(RemoteMsg.setVolumeLevel) case final volume?) {
      final max = volume.integer(6) ?? 0;
      final level = volume.integer(7);
      _emit(
        VolumeChanged(
          level: level == null || max <= 0 ? null : (level * 100 / max).round(),
          muted: volume.boolean(8),
        ),
      );
    } else if (message.has(RemoteMsg.error)) {
      final started = _remoteStarted;
      if (started != null && !started.isCompleted) {
        started.completeError(
          const TvRemoteException(
            TvErrorCode.protocol,
            'The TV reported an error',
          ),
        );
      }
    }
  }

  void _onImeState({int? imeCounter, int? fieldCounter, String? value}) {
    if (fieldCounter != null && fieldCounter != _fieldCounter) {
      _fieldText = '';
    }
    _imeCounter = imeCounter ?? _imeCounter;
    _fieldCounter = fieldCounter ?? _fieldCounter;
    if (value != null) _fieldText = value;
  }

  void _resetIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = Timer(idleTimeout, () => _remote?.close());
  }

  void _onRemoteClosed(_Link link) {
    if (!identical(_remote, link)) return;
    _remote = null;
    _idleTimer?.cancel();
    final started = _remoteStarted;
    if (started != null && !started.isCompleted) {
      started.completeError(
        const TvRemoteException(
          TvErrorCode.unreachable,
          'The TV closed the connection',
        ),
      );
    }
    _setStatus(ConnectionStatus.disconnected);
  }

  DeviceCapabilities _buildCapabilities() {
    final keys = (_features & AtvFeature.key) != 0
        ? androidKeyCodes.keys.toSet()
        : <RemoteKey>{};
    final ime = (_features & AtvFeature.ime) != 0;
    return DeviceCapabilities(
      keys: keys,
      powerOff: keys.contains(RemoteKey.powerOff),
      powerOn: keys.contains(RemoteKey.powerOn),
      textInput: ime,
      textInputStrategy: ime
          ? TextInputStrategy.nativeTextApi
          : TextInputStrategy.directionalKeyboard,
      textFieldDetection: ime,
      activity: ime,
      appLaunch: (_features & AtvFeature.appLink) != 0,
      contentLaunch: (_features & AtvFeature.appLink) != 0,
      pairingRequired: true,
    );
  }

  Future<void> _closeLinks() async {
    _idleTimer?.cancel();
    final remote = _remote;
    _remote = null;
    remote?.close();
    _pairing?.link?.close();
    _pairing?.fail(const TvRemoteException.notConnected());
    _pairing = null;
    final started = _remoteStarted;
    if (started != null && !started.isCompleted) {
      started.completeError(const TvRemoteException.notConnected());
    }
  }

  @override
  Future<void> disconnect() async {
    await _closeLinks();
    _setStatus(ConnectionStatus.disconnected);
  }

  Future<void> dispose() async {
    await disconnect();
    await _events.close();
  }

  @override
  Future<DeviceCapabilities> getCapabilities() async => _capabilities;

  _Link _requireRemote() {
    final link = _remote;
    if (link == null || _status != ConnectionStatus.connected) {
      throw const TvRemoteException.notConnected();
    }
    return link;
  }

  void _sendKeyCode(int code) => _requireRemote().send(RemoteMsg.key(code));

  @override
  Future<void> sendKey(RemoteKey key) async {
    _requireRemote();
    final code = androidKeyCodes[key];
    if (code == null || !_capabilities.supportsKey(key)) {
      throw TvRemoteException.unsupported('The ${key.name} key');
    }
    if (key == RemoteKey.backspace) return deleteText(1);
    _sendKeyCode(code);
  }

  @override
  Future<void> setVolume(int volume) async =>
      throw const TvRemoteException.unsupported('Setting an exact volume');

  @override
  Future<void> mute() => sendKey(RemoteKey.mute);

  void _requireText() {
    _requireRemote();
    if (!_capabilities.textInput) {
      throw const TvRemoteException.unsupported('Keyboard input');
    }
  }

  void _sendField(String value) => _requireRemote().send(
    RemoteMsg.imeText(
      imeCounter: _imeCounter,
      fieldCounter: _fieldCounter,
      value: value,
    ),
  );

  @override
  Future<void> sendText(String text) async {
    _requireText();
    if (text.isEmpty) return;
    _fieldText += text;
    _sendField(_fieldText);
  }

  @override
  Future<void> deleteText(int count) async {
    _requireText();
    if (count <= 0) return;
    final runes = _fieldText.runes.toList();
    if (runes.length > count) {
      _fieldText = String.fromCharCodes(runes.sublist(0, runes.length - count));
      _sendField(_fieldText);
      return;
    }
    // The edit message cannot express an empty field; use Delete key presses.
    _fieldText = '';
    for (var i = 0; i < count; i++) {
      _sendKeyCode(androidKeyCodes[RemoteKey.backspace]!);
    }
  }

  @override
  Future<void> submitText() async {
    _requireRemote();
    _sendKeyCode(androidKeyCodes[RemoteKey.enter]!);
    _fieldText = '';
  }

  /// The protocol cannot list installed apps; see [launchApp].
  @override
  Future<List<TvApp>> listApps() async =>
      throw const TvRemoteException.unsupported('Listing apps');

  /// Opens an app link (e.g. `https://www.netflix.com/title`); Android TV
  /// routes it to the installed app that handles it.
  @override
  Future<void> launchApp(String appLink) async {
    final link = _requireRemote();
    if (!_capabilities.appLaunch) {
      throw const TvRemoteException.unsupported('Launching apps');
    }
    link.send(RemoteMsg.appLink(appLink));
  }

  /// Android TV hands the link to the app registered for it.
  @override
  Future<bool> openContent(ContentLink link) async {
    await launchApp(link.url.toString());
    return true;
  }

  /// App links carry no icons; the UI shows lettered tiles.
  @override
  Future<Uint8List?> fetchAppIcon(TvApp app) async => null;

  @override
  Future<void> movePointer(double dx, double dy) async =>
      throw const TvRemoteException.unsupported('Pointer control');

  @override
  Future<void> pointerClick() async =>
      throw const TvRemoteException.unsupported('Pointer control');

  @override
  Future<void> scroll(double dx, double dy) async =>
      throw const TvRemoteException.unsupported('Scrolling');
}

/// State of one pairing attempt on the polo port.
class _PairingSession {
  _PairingSession(this.identity);

  final ClientIdentity identity;
  _Link? link;
  Uint8List? serverCertificateDer;
  final configured = Completer<void>();
  final paired = Completer<void>();
  Completer<void>? secretAck;

  void onMessage(ProtoMessage message) {
    final status = message.integer(Polo.status);
    if (status != Polo.statusOk) {
      fail(
        TvRemoteException(
          TvErrorCode.pairingRejected,
          status == 402
              ? 'The TV rejected the code. Try pairing again.'
              : 'The TV refused pairing (status $status)',
        ),
      );
      link?.close();
      return;
    }
    if (message.has(Polo.pairingRequestAck)) {
      link?.send(Polo.optionsMessage());
    } else if (message.has(Polo.options)) {
      link?.send(Polo.configurationMessage());
    } else if (message.has(Polo.configurationAck)) {
      if (!configured.isCompleted) configured.complete();
    } else if (message.has(Polo.secretAck)) {
      final ack = secretAck;
      if (ack != null && !ack.isCompleted) ack.complete();
    }
  }

  void onClosed() => fail(
    const TvRemoteException(
      TvErrorCode.pairingRejected,
      'The TV ended pairing',
    ),
  );

  void fail(TvRemoteException error) {
    for (final c in [configured, paired, ?secretAck]) {
      if (!c.isCompleted) {
        c.future.ignore();
        c.completeError(error);
      }
    }
  }
}
