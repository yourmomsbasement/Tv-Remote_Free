import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:characters/characters.dart';

import '../../core/adapter/custom_command.dart';
import '../../core/adapter/smart_tv_adapter.dart';
import '../../core/capabilities/device_capabilities.dart';
import '../../core/capabilities/remote_key.dart';
import '../../core/content/content_link.dart';
import '../../core/errors.dart';
import '../../core/storage/device_record.dart';
import 'samsung_keys.dart';

/// Samsung Tizen (2016 and later) adapter using the TV's remote-control
/// WebSocket channel.
///
/// The first connection shows an Allow/Deny prompt on the TV. Newer TVs then
/// issue a token, reused so later connections are silent. Text replaces the
/// content of the focused TV field, which the TV reports with IME events.
class SamsungAdapter implements SmartTVAdapter {
  SamsungAdapter({
    required this.host,
    this.endpoints,
    Uri? infoUri,
    this.appName = 'OpenRemote',
    this.connectTimeout = const Duration(seconds: 5),
    this.requestTimeout = const Duration(seconds: 5),
    this.pairingTimeout = const Duration(seconds: 60),
  }) : infoUri = infoUri ?? Uri.parse('http://$host:8001/api/v2/');

  final String host;

  /// Base URIs tried in order; defaults to wss :8002 then ws :8001.
  final List<Uri>? endpoints;
  final Uri infoUri;
  final String appName;
  final Duration connectTimeout;
  final Duration requestTimeout;
  final Duration pairingTimeout;

  static const _channel = '/api/v2/channels/samsung.remote.control';
  static const browserAppId = 'org.tizen.browser';

  final _events = StreamController<DeviceEvent>.broadcast();
  WebSocket? _socket;
  ConnectionStatus _status = ConnectionStatus.disconnected;
  Completer<String?>? _authorization;
  Completer<List<TvApp>>? _appsRequest;
  final _iconRequests = <String, Completer<Uint8List?>>{};

  /// Icon path and launch type per app id from the last app list.
  final _appIcons = <String, String>{};
  final _appTypes = <String, int>{};

  /// What the focused TV text field contains, as last reported or sent.
  String _text = '';

  @override
  String get protocol => Protocols.samsung;

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

  void _requireConnected() {
    if (_status != ConnectionStatus.connected || _socket == null) {
      throw const TvRemoteException.notConnected();
    }
  }

  List<Uri> _endpointsFor(String? token) {
    final query = {
      'name': base64.encode(utf8.encode(appName)),
      'token': ?token,
    };
    final bases =
        endpoints ??
        [Uri.parse('wss://$host:8002'), Uri.parse('ws://$host:8001')];
    return [
      for (final base in bases)
        base.replace(path: _channel, queryParameters: query),
    ];
  }

  /// Samsung TVs use a self-signed certificate; trust it only for this TV.
  HttpClient _httpClient() => HttpClient()
    ..connectionTimeout = connectTimeout
    ..badCertificateCallback = (cert, certHost, port) => certHost == host;

  /// Reads the TV's description from its REST API. Returns null if the TV
  /// does not answer.
  Future<Map<String, Object?>?> fetchInfo() async {
    final client = _httpClient();
    try {
      final request = await client.getUrl(infoUri).timeout(connectTimeout);
      final response = await request.close().timeout(connectTimeout);
      if (response.statusCode != 200) return null;
      final body = await response.transform(utf8.decoder).join();
      final json = jsonDecode(body);
      return json is Map<String, Object?> ? json : null;
    } on Object {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<void> connect({
    PairingRequest pairing = const PairingRequest(),
  }) async {
    await _close();
    _setStatus(ConnectionStatus.connecting);
    final token = pairing.storedCredential;
    Object? lastError;
    for (final uri in _endpointsFor(token)) {
      try {
        _socket = await WebSocket.connect(
          uri.toString(),
          customClient: _httpClient(),
        ).timeout(connectTimeout);
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
        'Cannot reach Samsung TV at $host',
        cause: lastError,
      );
    }
    final authorization = _authorization = Completer<String?>();
    socket.listen(
      _onMessage,
      onDone: () => _onClosed(socket),
      onError: (_) => _onClosed(socket),
      cancelOnError: true,
    );
    // An approved phone is let in at once; otherwise the TV is asking.
    final prompt = Timer(const Duration(seconds: 1), () {
      if (!authorization.isCompleted) _emit(const PairingPromptShown());
    });
    try {
      final issued = await authorization.future.timeout(
        pairingTimeout,
        onTimeout: () => throw const TvRemoteException(
          TvErrorCode.timeout,
          'The TV did not respond. Accept the request on the TV screen.',
        ),
      );
      if (issued != null && issued != token) _emit(PairingCompleted(issued));
      _setStatus(ConnectionStatus.connected);
    } catch (e) {
      await _close();
      _setStatus(ConnectionStatus.disconnected, error: e);
      rethrow;
    } finally {
      prompt.cancel();
    }
    unawaited(_reportInfo());
  }

  Future<void> _reportInfo() async {
    final info = await fetchInfo();
    final device = info?['device'];
    if (device is! Map) return;
    _emit(
      DeviceInfoUpdated(
        name: device['name'] as String?,
        model: device['modelName'] as String?,
        macAddress: device['wifiMac'] as String?,
      ),
    );
  }

  void _onMessage(Object? raw) {
    if (raw is! String) return;
    final Object? message;
    try {
      message = jsonDecode(raw);
    } on FormatException {
      return;
    }
    if (message is! Map) return;
    final data = message['data'];
    switch (message['event']) {
      case 'ms.channel.connect':
        final token = data is Map ? data['token'] : null;
        _authorization?.complete(token is String ? token : null);
        _authorization = null;
      case 'ms.channel.unauthorized':
        _authorization?.completeError(
          const TvRemoteException(
            TvErrorCode.pairingRejected,
            'The TV declined the connection. Allow it on the TV, or under '
            'Settings > General > External Device Manager > Device Connection '
            'Manager.',
          ),
        );
        _authorization = null;
      case 'ms.channel.timeOut':
        _authorization?.completeError(
          const TvRemoteException(
            TvErrorCode.timeout,
            'The request on the TV timed out. Try again and accept it.',
          ),
        );
        _authorization = null;
      case 'ed.installedApp.get':
        final list = data is Map ? data['data'] : null;
        _appsRequest?.complete(_parseApps(list is List ? list : const []));
        _appsRequest = null;
      case 'ed.apps.icon':
        if (data is! Map) return;
        final completer = _iconRequests.remove(data['iconPath']);
        final image = data['imageBase64'];
        Uint8List? bytes;
        if (image is String && image.isNotEmpty) {
          try {
            bytes = base64.decode(image);
          } on FormatException {
            bytes = null;
          }
        }
        completer?.complete(bytes);
      case 'ms.remote.imeStart':
        _text = '';
        _emit(const TextFieldFocusChanged(focused: true));
      case 'ms.remote.imeUpdate':
        if (data is String) {
          try {
            _text = utf8.decode(base64.decode(data), allowMalformed: true);
          } on FormatException {
            // Keep what we have.
          }
        }
      case 'ms.remote.imeEnd':
        _text = '';
        _emit(const TextFieldFocusChanged(focused: false));
    }
  }

  List<TvApp> _parseApps(List<Object?> list) {
    final apps = <TvApp>[];
    for (final item in list) {
      if (item is! Map) continue;
      final id = item['appId'];
      final name = item['name'];
      if (id is! String || name is! String) continue;
      final icon = item['icon'];
      if (icon is String && icon.isNotEmpty) _appIcons[id] = icon;
      final type = item['app_type'];
      if (type is int) _appTypes[id] = type;
      apps.add(
        TvApp(id: id, name: name, iconUrl: icon is String ? icon : null),
      );
    }
    apps.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return apps;
  }

  void _onClosed(WebSocket closed) {
    if (!identical(_socket, closed)) return;
    _socket = null;
    _failRequests();
    _setStatus(ConnectionStatus.disconnected);
  }

  void _failRequests() {
    const error = TvRemoteException.notConnected();
    _authorization?.completeError(
      const TvRemoteException(
        TvErrorCode.unreachable,
        'The TV closed the connection',
      ),
    );
    _authorization = null;
    _appsRequest?.completeError(error);
    _appsRequest = null;
    for (final c in _iconRequests.values) {
      c.complete(null);
    }
    _iconRequests.clear();
  }

  Future<void> _close() async {
    final socket = _socket;
    _socket = null;
    _failRequests();
    await socket?.close();
  }

  @override
  Future<void> disconnect() async {
    await _close();
    _setStatus(ConnectionStatus.disconnected);
  }

  void _send(Map<String, Object?> message) {
    _requireConnected();
    _socket!.add(jsonEncode(message));
  }

  void _remote(Map<String, Object?> params) =>
      _send({'method': 'ms.remote.control', 'params': params});

  void _emitToHost(String event, [Map<String, Object?>? data]) => _send({
    'method': 'ms.channel.emit',
    'params': {'event': event, 'to': 'host', 'data': ?data},
  });

  void _sendKeyName(String name) => _remote({
    'Cmd': 'Click',
    'DataOfCmd': name,
    'Option': 'false',
    'TypeOfRemote': 'SendRemoteKey',
  });

  @override
  Future<DeviceCapabilities> getCapabilities() async => DeviceCapabilities(
    keys: samsungKeyNames.keys.toSet(),
    powerOff: true,
    textInput: true,
    textInputStrategy: TextInputStrategy.nativeTextApi,
    textFieldDetection: true,
    pointer: true,
    appLaunch: true,
    appList: true,
    contentLaunch: true,
    customCommands: true,
    pairingRequired: true,
  );

  @override
  Future<void> pair(PairingRequest request) async {}

  @override
  Future<void> sendKey(RemoteKey key) async {
    final name = samsungKeyNames[key];
    if (name == null) throw TvRemoteException.unsupported(key.name);
    _sendKeyName(name);
  }

  @override
  Future<void> setVolume(int volume) async =>
      throw const TvRemoteException.unsupported('Setting the volume level');

  @override
  Future<void> mute() => sendKey(RemoteKey.mute);

  void _sendText() => _remote({
    'Cmd': base64.encode(utf8.encode(_text)),
    'DataOfCmd': 'base64',
    'TypeOfRemote': 'SendInputString',
  });

  @override
  Future<void> sendText(String text) async {
    _requireConnected();
    _text += text;
    _sendText();
  }

  @override
  Future<void> deleteText(int count) async {
    _requireConnected();
    final chars = _text.characters;
    _text = chars.take((chars.length - count).clamp(0, chars.length)).string;
    _sendText();
  }

  @override
  Future<void> submitText() async {
    _requireConnected();
    _remote({'TypeOfRemote': 'SendInputEnd'});
  }

  @override
  Future<List<TvApp>> listApps() async {
    _requireConnected();
    final request = _appsRequest ??= Completer<List<TvApp>>();
    _emitToHost('ed.installedApp.get');
    return request.future.timeout(
      requestTimeout,
      onTimeout: () {
        _appsRequest = null;
        throw const TvRemoteException(
          TvErrorCode.timeout,
          'The TV did not send its app list',
        );
      },
    );
  }

  void _launch(String appId, {String? metaTag, String? actionType}) =>
      _emitToHost('ed.apps.launch', {
        'appId': appId,
        'action_type':
            actionType ??
            (_appTypes[appId] == 4 ? 'NATIVE_LAUNCH' : 'DEEP_LINK'),
        'metaTag': ?metaTag,
      });

  @override
  Future<void> launchApp(String appId) async {
    _requireConnected();
    _launch(appId);
  }

  @override
  Future<bool> openContent(ContentLink link) async {
    _requireConnected();
    if (link.service == StreamingService.other) {
      _launch(
        browserAppId,
        actionType: 'NATIVE_LAUNCH',
        metaTag: link.url.toString(),
      );
      return true;
    }
    final apps = await listApps();
    final app = apps.where((a) => link.service.matchesApp(a.name)).firstOrNull;
    if (app == null) {
      throw TvRemoteException(
        TvErrorCode.unsupported,
        '${link.service.displayName} is not installed on this TV',
      );
    }
    _launch(app.id);
    return false;
  }

  @override
  Future<void> sendCustom(CustomCommand command) async {
    _requireConnected();
    checkCustomCommand(command, protocol);
    _sendKeyName(command.value);
  }

  @override
  Future<Uint8List?> fetchAppIcon(TvApp app) async {
    final path = _appIcons[app.id] ?? app.iconUrl;
    if (path == null || _socket == null) return null;
    final request = _iconRequests[path] ??= Completer<Uint8List?>();
    try {
      _emitToHost('ed.apps.icon', {'iconPath': path});
      return await request.future.timeout(requestTimeout);
    } on Object {
      _iconRequests.remove(path);
      return null;
    }
  }

  @override
  Future<void> movePointer(double dx, double dy) async => _remote({
    'Cmd': 'Move',
    'Position': {
      'x': dx.round(),
      'y': dy.round(),
      'Time': '${DateTime.now().millisecondsSinceEpoch}',
    },
    'TypeOfRemote': 'ProcessMouseDevice',
  });

  @override
  Future<void> pointerClick() async =>
      _remote({'Cmd': 'LeftClick', 'TypeOfRemote': 'ProcessMouseDevice'});

  @override
  Future<void> scroll(double dx, double dy) async =>
      throw const TvRemoteException.unsupported('Scrolling');
}
