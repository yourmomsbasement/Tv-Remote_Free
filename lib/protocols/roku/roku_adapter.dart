import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import '../../core/adapter/smart_tv_adapter.dart';
import '../../core/capabilities/device_capabilities.dart';
import '../../core/capabilities/remote_key.dart';
import '../../core/connection/tv_image_fetcher.dart';
import '../../core/errors.dart';
import 'roku_device_info.dart';
import 'roku_keys.dart';

/// Roku External Control Protocol (ECP) adapter.
///
/// ECP is plain HTTP on port 8060 with no pairing. Text is sent one
/// character at a time as `Lit_` keypresses, so input is append-only and
/// Roku does not report text-field focus.
class RokuAdapter implements SmartTVAdapter {
  RokuAdapter({
    required this.host,
    this.port = 8060,
    http.Client? client,
    this.timeout = const Duration(seconds: 3),
    this.activityInterval = const Duration(seconds: 2),
  }) : _client = client ?? http.Client();

  final String host;
  final int port;
  final Duration timeout;

  /// How often to poll what the TV is playing while connected.
  final Duration activityInterval;
  Timer? _activityTimer;
  bool _polling = false;
  String? _lastActivityKey;
  final http.Client _client;
  final _events = StreamController<DeviceEvent>.broadcast();
  late final _images = TvImageFetcher(host);

  ConnectionStatus _status = ConnectionStatus.disconnected;
  RokuDeviceInfo? _info;
  DeviceCapabilities _capabilities = DeviceCapabilities.none;

  RokuDeviceInfo? get deviceInfo => _info;

  @override
  String get protocol => 'roku';

  @override
  ConnectionStatus get status => _status;

  @override
  Stream<DeviceEvent> get events => _events.stream;

  Uri _uri(String path) =>
      Uri(scheme: 'http', host: host, port: port, path: path);

  void _setStatus(ConnectionStatus status, {Object? error}) {
    _status = status;
    _events.add(ConnectionStatusChanged(status, error: error));
  }

  Future<http.Response> _send(String method, String path) async {
    final http.Response response;
    try {
      response =
          await (method == 'POST'
                  ? _client.post(_uri(path))
                  : _client.get(_uri(path)))
              .timeout(timeout);
    } on TimeoutException catch (e) {
      throw TvRemoteException(
        TvErrorCode.timeout,
        'Roku did not respond',
        cause: e,
      );
    } on SocketException catch (e) {
      throw TvRemoteException(
        TvErrorCode.unreachable,
        'Cannot reach Roku at $host',
        cause: e,
      );
    } on http.ClientException catch (e) {
      throw TvRemoteException(
        TvErrorCode.unreachable,
        'Cannot reach Roku at $host',
        cause: e,
      );
    }
    if (response.statusCode == 403) {
      throw const TvRemoteException(
        TvErrorCode.forbidden,
        'Roku refused the command. On the Roku, open Settings > System > '
        'Advanced system settings > Control by mobile apps and set Network '
        'access to Default or Permissive.',
      );
    }
    if (response.statusCode >= 400) {
      throw TvRemoteException(
        TvErrorCode.protocol,
        'Roku returned HTTP ${response.statusCode}',
      );
    }
    return response;
  }

  Future<RokuDeviceInfo> fetchDeviceInfo() async {
    final response = await _send('GET', '/query/device-info');
    try {
      return RokuDeviceInfo.parse(response.body);
    } on Exception catch (e) {
      throw TvRemoteException(
        TvErrorCode.protocol,
        'Unexpected Roku device-info response',
        cause: e,
      );
    }
  }

  @override
  Future<void> connect({
    PairingRequest pairing = const PairingRequest(),
  }) async {
    _setStatus(ConnectionStatus.connecting);
    try {
      final info = await fetchDeviceInfo();
      _info = info;
      _capabilities = capabilitiesFor(info);
      _events.add(
        DeviceInfoUpdated(
          name: info.friendlyName,
          model: info.modelName,
          macAddress: info.wifiMac ?? info.ethernetMac,
        ),
      );
      _setStatus(ConnectionStatus.connected);
      _startActivityPolling();
    } catch (e) {
      _setStatus(ConnectionStatus.disconnected, error: e);
      rethrow;
    }
  }

  static DeviceCapabilities capabilitiesFor(RokuDeviceInfo info) {
    final keys = rokuKeyNames.keys.where((key) {
      if (rokuTvOnlyKeys.contains(key)) return info.isTv;
      if (rokuPowerKeys.contains(key)) return info.isTv || info.supportsSuspend;
      return true;
    }).toSet();
    return DeviceCapabilities(
      keys: keys,
      powerOff: keys.contains(RemoteKey.powerOff),
      powerOn: keys.contains(RemoteKey.powerOn),
      textInput: true,
      textInputStrategy: TextInputStrategy.characterEvents,
      activity: true,
      playbackState: true,
      playbackPosition: true,
      appLaunch: true,
      appList: true,
    );
  }

  @override
  Future<void> disconnect() async {
    _activityTimer?.cancel();
    _activityTimer = null;
    if (_status != ConnectionStatus.disconnected) {
      _setStatus(ConnectionStatus.disconnected);
    }
  }

  /// Releases the HTTP client. The adapter cannot be reused afterwards.
  Future<void> dispose() async {
    await disconnect();
    _client.close();
    _images.close();
    await _events.close();
  }

  @override
  Future<DeviceCapabilities> getCapabilities() async => _capabilities;

  @override
  Future<void> pair(PairingRequest request) async {
    // ECP has no pairing step.
  }

  void _requireConnected() {
    if (_status != ConnectionStatus.connected) {
      throw const TvRemoteException.notConnected();
    }
  }

  @override
  Future<void> sendKey(RemoteKey key) async {
    _requireConnected();
    final name = rokuKeyNames[key];
    if (name == null || !_capabilities.supportsKey(key)) {
      throw TvRemoteException.unsupported('The ${key.name} key');
    }
    await _send('POST', '/keypress/$name');
  }

  @override
  Future<void> setVolume(int volume) async =>
      throw const TvRemoteException.unsupported('Setting an exact volume');

  @override
  Future<void> mute() => sendKey(RemoteKey.mute);

  @override
  Future<void> sendText(String text) async {
    _requireConnected();
    // One request per code point, in order; Roku has no bulk text API.
    for (final rune in text.runes) {
      await _send(
        'POST',
        '/keypress/${rokuLiteral(String.fromCharCode(rune))}',
      );
    }
  }

  @override
  Future<void> deleteText(int count) async {
    _requireConnected();
    for (var i = 0; i < count; i++) {
      await _send('POST', '/keypress/Backspace');
    }
  }

  @override
  Future<void> submitText() => sendKey(RemoteKey.enter);

  @override
  Future<List<TvApp>> listApps() async {
    _requireConnected();
    final response = await _send('GET', '/query/apps');
    try {
      return parseApps(response.body)
          .map(
            (app) => TvApp(
              id: app.id,
              name: app.name,
              iconUrl: _uri('/query/icon/${app.id}').toString(),
            ),
          )
          .toList();
    } on XmlException catch (e) {
      throw TvRemoteException(
        TvErrorCode.protocol,
        'Unexpected app list',
        cause: e,
      );
    }
  }

  static List<TvApp> parseApps(String xmlText) => XmlDocument.parse(xmlText)
      .findAllElements('app')
      .where((e) => e.getAttribute('id') != null)
      // Apps and, on Roku TVs, inputs such as HDMI 1 (launching one switches
      // to it). Other entries (e.g. menus) are not launchable.
      .where(
        (e) =>
            const {'appl', 'tvin'}.contains(e.getAttribute('type') ?? 'appl'),
      )
      .map((e) => TvApp(id: e.getAttribute('id')!, name: e.innerText.trim()))
      .toList();

  @override
  Future<void> launchApp(String appId) async {
    _requireConnected();
    await _send('POST', '/launch/${Uri.encodeComponent(appId)}');
  }

  /// ECP has no push events, so poll the media player (and the active app
  /// while nothing plays). Failures are ignored; commands report errors.
  void _startActivityPolling() {
    _activityTimer?.cancel();
    _activityTimer = Timer.periodic(activityInterval, (_) => pollActivity());
    unawaited(pollActivity());
  }

  Future<void> pollActivity() async {
    if (_polling || _status != ConnectionStatus.connected) return;
    _polling = true;
    try {
      final player = parseMediaPlayer(
        (await _send('GET', '/query/media-player')).body,
        DateTime.now(),
      );
      var activity = player;
      if (!player.hasMedia) {
        final app = parseActiveApp(
          (await _send('GET', '/query/active-app')).body,
        );
        activity = MediaActivity(
          appId: app.$1,
          appName: app.$2,
          state: player.state,
          receivedAt: player.receivedAt,
        );
      }
      // Emit on change, and on every poll while playing (position moves).
      final key = '${activity.appId}|${activity.state}';
      if (key != _lastActivityKey || activity.hasMedia) {
        _lastActivityKey = key;
        if (!_events.isClosed) _events.add(ActivityChanged(activity));
      }
    } on Object {
      // Older firmware or a channel without media-player support.
    } finally {
      _polling = false;
    }
  }

  static Duration? _ms(String? text) {
    final match = RegExp(r'(\d+)').firstMatch(text ?? '');
    return match == null ? null : Duration(milliseconds: int.parse(match[1]!));
  }

  /// Parses `GET /query/media-player`.
  static MediaActivity parseMediaPlayer(String xmlText, DateTime receivedAt) {
    final player = XmlDocument.parse(xmlText).rootElement;
    final plugin = player.getElement('plugin');
    String? text(String name) => player.getElement(name)?.innerText.trim();
    return MediaActivity(
      appId: plugin?.getAttribute('id'),
      appName: plugin?.getAttribute('name'),
      state: switch (player.getAttribute('state')) {
        'play' => PlaybackState.playing,
        'pause' => PlaybackState.paused,
        'buffer' || 'startup' || 'open' => PlaybackState.buffering,
        'stop' || 'close' || 'none' => PlaybackState.stopped,
        _ => PlaybackState.unknown,
      },
      position: _ms(text('position')),
      duration: _ms(text('duration')),
      isLive: text('is_live') == 'true',
      receivedAt: receivedAt,
    );
  }

  /// Parses `GET /query/active-app`: (app id, name); the home screen has no
  /// id.
  static (String?, String?) parseActiveApp(String xmlText) {
    final app = XmlDocument.parse(xmlText).findAllElements('app').firstOrNull;
    return (app?.getAttribute('id'), app?.innerText.trim());
  }

  @override
  Future<Uint8List?> fetchAppIcon(TvApp app) =>
      _images.fetchFirst([_uri('/query/icon/${Uri.encodeComponent(app.id)}')]);

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
