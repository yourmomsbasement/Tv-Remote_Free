import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../core/adapter/smart_tv_adapter.dart';
import '../../core/capabilities/device_capabilities.dart';
import '../../core/capabilities/remote_key.dart';
import '../../core/connection/tv_image_fetcher.dart';
import '../../core/errors.dart';
import 'webos_keys.dart';
import 'webos_manifest.dart';

/// LG webOS adapter using the SSAP WebSocket API ("second screen").
///
/// Registration shows an allow/deny prompt on the TV the first time; the TV
/// then issues a client key that is reused for silent reconnects. Navigation
/// keys and the pointer go through a secondary "pointer input" socket. Text
/// uses the IME service, which also reports when a TV text field has focus.
class WebOsAdapter implements SmartTVAdapter {
  WebOsAdapter({
    required this.host,
    List<Uri>? endpoints,
    this.connectTimeout = const Duration(seconds: 5),
    this.requestTimeout = const Duration(seconds: 5),
    this.pairingTimeout = const Duration(seconds: 60),
  }) : endpoints =
           endpoints ??
           [Uri.parse('wss://$host:3001'), Uri.parse('ws://$host:3000')];

  final String host;

  /// Tried in order. Newer firmware accepts only the TLS endpoint.
  final List<Uri> endpoints;
  final Duration connectTimeout;
  final Duration requestTimeout;
  final Duration pairingTimeout;

  final _events = StreamController<DeviceEvent>.broadcast();
  late final _images = TvImageFetcher(host);

  /// Icon paths per app from the last app list, largest first.
  final _iconPaths = <String, List<String>>{};
  final _pending = <String, Completer<Map<String, Object?>>>{};
  final _subscriptions = <String, void Function(Map<String, Object?>)>{};

  WebSocket? _socket;
  WebSocket? _pointer;
  Future<WebSocket>? _pointerOpening;
  Completer<String>? _registration;
  ConnectionStatus _status = ConnectionStatus.disconnected;
  int _nextId = 1;
  bool _muted = false;
  DeviceCapabilities _capabilities = DeviceCapabilities.none;

  @override
  String get protocol => 'lg_webos';

  @override
  ConnectionStatus get status => _status;

  @override
  Stream<DeviceEvent> get events => _events.stream;

  void _setStatus(ConnectionStatus status, {Object? error}) {
    if (_status == status && error == null) return;
    _status = status;
    if (!_events.isClosed) {
      _events.add(ConnectionStatusChanged(status, error: error));
    }
  }

  void _emit(DeviceEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  /// webOS uses a self-signed certificate. Accept it only for this TV's
  /// address so the app never trusts unknown certificates elsewhere.
  HttpClient _httpClient() => HttpClient()
    ..connectionTimeout = connectTimeout
    ..badCertificateCallback = (cert, certHost, port) => certHost == host;

  Future<WebSocket> _open(Uri uri) => WebSocket.connect(
    uri.toString(),
    customClient: _httpClient(),
  ).timeout(connectTimeout);

  @override
  Future<void> connect({
    PairingRequest pairing = const PairingRequest(),
  }) async {
    await _closeSockets();
    _setStatus(ConnectionStatus.connecting);
    Object? lastError;
    for (final uri in endpoints) {
      try {
        _socket = await _open(uri);
        break;
      } on Object catch (e) {
        lastError = e;
      }
    }
    final socket = _socket;
    if (socket == null) {
      _setStatus(ConnectionStatus.disconnected, error: lastError);
      throw TvRemoteException(
        TvErrorCode.unreachable,
        'Cannot reach LG TV at $host',
        cause: lastError,
      );
    }
    socket.listen(
      _onMessage,
      onDone: () => _onSocketClosed(socket),
      onError: (_) => _onSocketClosed(socket),
      cancelOnError: true,
    );

    try {
      final key = await _register(pairing.storedCredential);
      // Announce the new key before "connected" so it is stored first.
      if (key != pairing.storedCredential) _emit(PairingCompleted(key));
      _capabilities = _buildCapabilities();
      _setStatus(ConnectionStatus.connected);
    } catch (e) {
      await _closeSockets();
      _setStatus(ConnectionStatus.disconnected, error: e);
      rethrow;
    }
    await _afterConnect();
  }

  Future<String> _register(String? clientKey) async {
    final completer = _registration = Completer<String>();
    _socket!.add(
      jsonEncode({
        'type': 'register',
        'id': 'register_0',
        'payload': webOsRegisterPayload(clientKey: clientKey),
      }),
    );
    try {
      return await completer.future.timeout(pairingTimeout);
    } on TimeoutException {
      throw const TvRemoteException(
        TvErrorCode.timeout,
        'The TV did not answer the pairing request',
      );
    } on TvRemoteException catch (e) {
      // A rejected stored key means the TV forgot us (e.g. factory reset).
      if (clientKey != null && e.code == TvErrorCode.pairingRejected) {
        throw TvRemoteException(
          TvErrorCode.pairingRequired,
          'The TV no longer accepts this phone. Pair again.',
          cause: e,
        );
      }
      rethrow;
    } finally {
      _registration = null;
    }
  }

  DeviceCapabilities _buildCapabilities() => DeviceCapabilities(
    keys: {
      ...webOsButtonNames.keys,
      ...webOsSsapKeys.keys,
      RemoteKey.backspace,
    },
    volumeSet: true,
    powerOff: true,
    textInput: true,
    textInputStrategy: TextInputStrategy.nativeTextApi,
    textFieldDetection: true,
    pointer: true,
    appLaunch: true,
    appList: true,
    pairingRequired: true,
  );

  Future<void> _afterConnect() async {
    // Best effort: not every firmware exposes every service.
    unawaited(
      _subscribe(
        'ssap://com.webos.service.ime/registerRemoteKeyboard',
        _onKeyboardEvent,
      ).catchError((_) {}),
    );
    unawaited(
      _subscribe('ssap://audio/getVolume', _onVolumeEvent).catchError((_) {}),
    );
    unawaited(
      _request('ssap://com.webos.service.connectionmanager/getinfo')
          .then((info) {
            final mac = _mac(info['wiredInfo']) ?? _mac(info['wifiInfo']);
            if (mac != null) _emit(DeviceInfoUpdated(macAddress: mac));
          })
          .catchError((_) {}),
    );
    unawaited(
      _request('ssap://system/getSystemInfo')
          .then((info) {
            final model = info['modelName'];
            if (model is String) _emit(DeviceInfoUpdated(model: model));
          })
          .catchError((_) {}),
    );
  }

  static String? _mac(Object? info) {
    if (info is! Map) return null;
    final mac = info['macAddress'];
    return mac is String && mac.isNotEmpty ? mac : null;
  }

  void _onKeyboardEvent(Map<String, Object?> payload) {
    final widget = payload['currentWidget'];
    if (widget is! Map) return;
    final focused = widget['focus'] == true;
    final contentType = widget['contentType'] as String?;
    _emit(
      TextFieldFocusChanged(
        focused: focused,
        sensitive: widget['hiddenText'] == true || contentType == 'password',
        inputType: contentType,
      ),
    );
  }

  void _onVolumeEvent(Map<String, Object?> payload) {
    // Older firmware: {volume, muted}; newer: {volumeStatus: {volume, muteStatus}}.
    final status = payload['volumeStatus'];
    final source = status is Map ? status : payload;
    final level = source['volume'];
    final muted = source['muteStatus'] ?? source['muted'];
    if (muted is bool) _muted = muted;
    _emit(
      VolumeChanged(
        level: level is num ? level.toInt() : null,
        muted: muted is bool ? muted : null,
      ),
    );
  }

  void _onMessage(Object? data) {
    if (data is! String) return;
    final Map<String, Object?> message;
    try {
      message = (jsonDecode(data) as Map).cast<String, Object?>();
    } on Object {
      return;
    }
    final id = message['id'];
    final type = message['type'];
    final payload =
        (message['payload'] as Map?)?.cast<String, Object?>() ?? const {};

    if (id == 'register_0') {
      _onRegistrationMessage(type, payload, message['error']);
      return;
    }
    if (id is! String) return;

    final subscription = _subscriptions[id];
    if (subscription != null && type == 'response') {
      subscription(payload);
    }
    final pending = _pending.remove(id);
    if (pending == null) return;
    if (type == 'error' || payload['returnValue'] == false) {
      final error = (message['error'] ?? payload['errorText'] ?? 'error')
          .toString();
      pending.completeError(
        TvRemoteException(
          error.startsWith('404')
              ? TvErrorCode.unsupported
              : TvErrorCode.protocol,
          'TV rejected the request: $error',
        ),
      );
    } else {
      pending.complete(payload);
    }
  }

  void _onRegistrationMessage(
    Object? type,
    Map<String, Object?> payload,
    Object? error,
  ) {
    final registration = _registration;
    if (registration == null || registration.isCompleted) return;
    switch (type) {
      case 'response' when payload['pairingType'] == 'PROMPT':
        _setStatus(ConnectionStatus.awaitingPairing);
        _emit(const PairingPromptShown());
      case 'registered':
        final key = payload['client-key'];
        if (key is String && key.isNotEmpty) {
          registration.complete(key);
        } else {
          registration.completeError(
            const TvRemoteException(
              TvErrorCode.protocol,
              'The TV did not return a client key',
            ),
          );
        }
      case 'error':
        registration.completeError(
          TvRemoteException(
            TvErrorCode.pairingRejected,
            'Pairing was declined on the TV (${error ?? 'unknown'})',
          ),
        );
    }
  }

  /// The TV dropped the connection (sleep, network loss, firmware restart).
  void _onSocketClosed(WebSocket closed) {
    // Ignore sockets we already replaced or closed on purpose.
    if (!identical(_socket, closed)) return;
    _socket = null;
    _pointer?.close();
    _pointer = null;
    _pointerOpening = null;
    _failPending(
      const TvRemoteException(
        TvErrorCode.unreachable,
        'The TV closed the connection',
      ),
    );
    _setStatus(ConnectionStatus.disconnected);
  }

  void _failPending(TvRemoteException error) {
    _subscriptions.clear();
    final pending = _pending.values.toList();
    _pending.clear();
    for (final completer in pending) {
      completer.completeError(error);
    }
    final registration = _registration;
    if (registration != null && !registration.isCompleted) {
      registration.completeError(error);
    }
  }

  Future<Map<String, Object?>> _request(
    String uri, [
    Map<String, Object?>? payload,
  ]) {
    final socket = _socket;
    if (socket == null) {
      return Future.error(const TvRemoteException.notConnected());
    }
    final id = 'req_${_nextId++}';
    final completer = _pending[id] = Completer<Map<String, Object?>>();
    socket.add(
      jsonEncode({
        'type': 'request',
        'id': id,
        'uri': uri,
        'payload': ?payload,
      }),
    );
    return completer.future.timeout(
      requestTimeout,
      onTimeout: () {
        _pending.remove(id);
        throw const TvRemoteException(
          TvErrorCode.timeout,
          'The TV did not respond',
        );
      },
    );
  }

  Future<void> _subscribe(
    String uri,
    void Function(Map<String, Object?>) onUpdate,
  ) {
    final socket = _socket;
    if (socket == null) {
      return Future.error(const TvRemoteException.notConnected());
    }
    final id = 'sub_${_nextId++}';
    _subscriptions[id] = onUpdate;
    final completer = _pending[id] = Completer<Map<String, Object?>>();
    socket.add(jsonEncode({'type': 'subscribe', 'id': id, 'uri': uri}));
    return completer.future
        .timeout(requestTimeout)
        .then(
          (_) {},
          onError: (e) {
            _subscriptions.remove(id);
            _pending.remove(id);
            throw e;
          },
        );
  }

  Future<WebSocket> _pointerSocket() {
    final existing = _pointer;
    if (existing != null) return Future.value(existing);
    return _pointerOpening ??= () async {
      try {
        final response = await _request(
          'ssap://com.webos.service.networkinput/getPointerInputSocket',
        );
        final path = response['socketPath'];
        if (path is! String) {
          throw const TvRemoteException(
            TvErrorCode.protocol,
            'The TV did not return a pointer socket',
          );
        }
        final socket = await _open(Uri.parse(path));
        socket.listen(
          (_) {},
          onDone: () {
            if (identical(_pointer, socket)) _pointer = null;
          },
          onError: (_) {},
        );
        return _pointer = socket;
      } finally {
        _pointerOpening = null;
      }
    }();
  }

  void _requireConnected() {
    if (_status != ConnectionStatus.connected || _socket == null) {
      throw const TvRemoteException.notConnected();
    }
  }

  @override
  Future<void> disconnect() async {
    await _closeSockets();
    _setStatus(ConnectionStatus.disconnected);
  }

  Future<void> _closeSockets() async {
    final socket = _socket;
    final pointer = _pointer;
    _socket = null;
    _pointer = null;
    _pointerOpening = null;
    _failPending(const TvRemoteException.notConnected());
    await pointer?.close();
    await socket?.close();
  }

  Future<void> dispose() async {
    await disconnect();
    _images.close();
    await _events.close();
  }

  @override
  Future<DeviceCapabilities> getCapabilities() async => _capabilities;

  @override
  Future<void> pair(PairingRequest request) => connect(pairing: request);

  @override
  Future<void> sendKey(RemoteKey key) async {
    _requireConnected();
    if (!_capabilities.supportsKey(key)) {
      throw TvRemoteException.unsupported('The ${key.name} key');
    }
    if (key == RemoteKey.backspace) return deleteText(1);
    final ssap = webOsSsapKeys[key];
    if (ssap != null) {
      await _request(ssap);
      return;
    }
    final pointer = await _pointerSocket();
    pointer.add(webOsButtonMessage(webOsButtonNames[key]!));
  }

  @override
  Future<void> setVolume(int volume) async {
    _requireConnected();
    await _request('ssap://audio/setVolume', {'volume': volume.clamp(0, 100)});
  }

  @override
  Future<void> mute() async {
    _requireConnected();
    await _request('ssap://audio/setMute', {'mute': !_muted});
  }

  @override
  Future<void> sendText(String text) async {
    _requireConnected();
    if (text.isEmpty) return;
    await _request('ssap://com.webos.service.ime/insertText', {
      'text': text,
      'replace': 0,
    });
  }

  @override
  Future<void> deleteText(int count) async {
    _requireConnected();
    if (count <= 0) return;
    await _request('ssap://com.webos.service.ime/deleteCharacters', {
      'count': count,
    });
  }

  @override
  Future<void> submitText() => sendKey(RemoteKey.enter);

  @override
  Future<List<TvApp>> listApps() async {
    _requireConnected();
    final response = await _request(
      'ssap://com.webos.applicationManager/listLaunchPoints',
    );
    final points = response['launchPoints'];
    if (points is! List) return const [];
    _iconPaths.clear();
    final apps = <TvApp>[];
    for (final p in points.whereType<Map>()) {
      final id = p['id'];
      if (id is! String) continue;
      final icons = [
        for (final key in const ['largeIcon', 'mediumLargeIcon', 'icon'])
          if (p[key] case final String path when path.isNotEmpty) path,
      ];
      _iconPaths[id] = icons;
      apps.add(
        TvApp(
          id: id,
          name: (p['title'] as String?) ?? id,
          iconUrl: icons.firstOrNull,
        ),
      );
    }
    return apps;
  }

  /// Where an icon might be served. Firmware reports absolute URLs on port
  /// 3000 (HTTP) or 3001 (HTTPS, self-signed), or a path relative to the
  /// TV. Newer firmware closes port 3000, so each URL is also tried on the
  /// other port.
  static List<Uri> iconCandidates(String host, Iterable<String> paths) {
    final secure = Uri(scheme: 'https', host: host, port: 3001);
    final plain = Uri(scheme: 'http', host: host, port: 3000);
    final out = <Uri>[];
    void add(Uri uri) {
      if (!out.contains(uri)) out.add(uri);
    }

    for (final raw in paths) {
      final parsed = Uri.tryParse(raw);
      if (parsed == null) continue;
      if (!parsed.hasScheme) {
        final path = parsed.path.startsWith('/')
            ? parsed.path
            : '/${parsed.path}';
        add(secure.replace(path: path));
        add(plain.replace(path: path));
        continue;
      }
      if (parsed.host != host) continue;
      add(parsed);
      if (parsed.scheme == 'http') {
        add(parsed.replace(scheme: 'https', port: 3001));
      } else if (parsed.scheme == 'https') {
        add(parsed.replace(scheme: 'http', port: 3000));
      }
    }
    return out;
  }

  @override
  Future<Uint8List?> fetchAppIcon(TvApp app) => _images.fetchFirst(
    iconCandidates(host, _iconPaths[app.id] ?? [?app.iconUrl]),
  );

  @override
  Future<void> launchApp(String appId) async {
    _requireConnected();
    await _request('ssap://system.launcher/launch', {'id': appId});
  }

  @override
  Future<void> movePointer(double dx, double dy) async {
    _requireConnected();
    final pointer = await _pointerSocket();
    pointer.add(webOsMoveMessage(dx.round(), dy.round()));
  }

  @override
  Future<void> pointerClick() async {
    _requireConnected();
    final pointer = await _pointerSocket();
    pointer.add(webOsClickMessage);
  }
}
