import 'dart:async';
import 'dart:typed_data';

import '../../core/adapter/custom_command.dart';
import '../../core/adapter/smart_tv_adapter.dart';
import '../../core/capabilities/device_capabilities.dart';
import '../../core/capabilities/remote_key.dart';
import '../../core/content/content_link.dart';
import '../../core/errors.dart';
import '../../core/storage/device_record.dart';

/// A simulated TV that supports everything, so the app can be tried (and
/// reviewed by the app stores) without a TV on the network.
class DemoAdapter implements SmartTVAdapter {
  DemoAdapter({this.latency = const Duration(milliseconds: 150)});

  final Duration latency;
  final _events = StreamController<DeviceEvent>.broadcast();
  ConnectionStatus _status = ConnectionStatus.disconnected;

  static const apps = [
    TvApp(id: 'demo.movies', name: 'Movies'),
    TvApp(id: 'demo.shows', name: 'Shows'),
    TvApp(id: 'demo.music', name: 'Music'),
    TvApp(id: 'demo.news', name: 'News'),
    TvApp(id: 'demo.photos', name: 'Photos'),
    TvApp(id: 'demo.browser', name: 'Web Browser'),
  ];

  int _volume = 15;
  bool _muted = false;
  bool _on = true;
  String _appId = 'demo.home';
  PlaybackState _playback = PlaybackState.stopped;
  Duration _position = Duration.zero;
  DateTime _since = DateTime.now();
  static const _length = Duration(minutes: 42);
  final _text = StringBuffer();
  bool _textFocused = false;

  @override
  String get protocol => Protocols.demo;

  @override
  ConnectionStatus get status => _status;

  @override
  Stream<DeviceEvent> get events => _events.stream;

  Future<void> _work() => Future<void>.delayed(latency);

  void _requireConnected() {
    if (_status != ConnectionStatus.connected) {
      throw const TvRemoteException.notConnected();
    }
  }

  @override
  Future<void> connect({
    PairingRequest pairing = const PairingRequest(),
  }) async {
    _status = ConnectionStatus.connecting;
    await _work();
    _status = ConnectionStatus.connected;
    _events
      ..add(const ConnectionStatusChanged(ConnectionStatus.connected))
      ..add(VolumeChanged(level: _volume, muted: _muted));
    _emitActivity();
  }

  @override
  Future<void> disconnect() async {
    _status = ConnectionStatus.disconnected;
    _events.add(const ConnectionStatusChanged(ConnectionStatus.disconnected));
  }

  @override
  Future<DeviceCapabilities> getCapabilities() async => DeviceCapabilities(
    keys: RemoteKey.values.toSet(),
    volumeSet: true,
    powerOff: true,
    powerOn: true,
    textInput: true,
    textInputStrategy: TextInputStrategy.nativeTextApi,
    textFieldDetection: true,
    pointer: true,
    scroll: true,
    activity: true,
    playbackState: true,
    playbackPosition: true,
    appLaunch: true,
    contentLaunch: true,
    appList: true,
  );

  @override
  Future<void> pair(PairingRequest request) async {}

  Duration get _now {
    if (_playback != PlaybackState.playing) return _position;
    final p = _position + DateTime.now().difference(_since);
    return p > _length ? _length : p;
  }

  void _setPlayback(PlaybackState state, {Duration? position}) {
    _position = position ?? _now;
    _since = DateTime.now();
    _playback = state;
    _emitActivity();
  }

  void _emitActivity() {
    final app = apps.where((a) => a.id == _appId).firstOrNull;
    _events.add(
      ActivityChanged(
        MediaActivity(
          appId: _on ? _appId : null,
          appName: _on ? (app?.name ?? 'Home') : null,
          state: _on ? _playback : PlaybackState.stopped,
          position: _playback == PlaybackState.stopped ? null : _position,
          duration: _playback == PlaybackState.stopped ? null : _length,
          receivedAt: _since,
        ),
      ),
    );
  }

  void _setTextFocus(bool focused) {
    if (_textFocused == focused) return;
    _textFocused = focused;
    if (!focused) _text.clear();
    _events.add(TextFieldFocusChanged(focused: focused));
  }

  @override
  Future<void> sendKey(RemoteKey key) async {
    _requireConnected();
    await _work();
    final media = _appId != 'demo.home';
    switch (key) {
      case RemoteKey.power || RemoteKey.powerOff || RemoteKey.powerOn:
        _on = key == RemoteKey.power ? !_on : key == RemoteKey.powerOn;
        _emitActivity();
      case RemoteKey.home:
        _appId = 'demo.home';
        _setTextFocus(false);
        _setPlayback(PlaybackState.stopped, position: Duration.zero);
      case RemoteKey.back:
        _setTextFocus(false);
      case RemoteKey.search:
        _setTextFocus(true);
      case RemoteKey.volumeUp || RemoteKey.volumeDown:
        _volume = (_volume + (key == RemoteKey.volumeUp ? 1 : -1)).clamp(
          0,
          100,
        );
        _muted = false;
        _events.add(VolumeChanged(level: _volume, muted: _muted));
      case RemoteKey.mute:
        await mute();
      case RemoteKey.play || RemoteKey.pause || RemoteKey.playPause when media:
        final play = switch (key) {
          RemoteKey.play => true,
          RemoteKey.pause => false,
          _ => _playback != PlaybackState.playing,
        };
        _setPlayback(play ? PlaybackState.playing : PlaybackState.paused);
      case RemoteKey.stop when media:
        _setPlayback(PlaybackState.stopped, position: Duration.zero);
      case RemoteKey.fastForward || RemoteKey.rewind || RemoteKey.replay
          when media && _playback != PlaybackState.stopped:
        final step = key == RemoteKey.fastForward
            ? const Duration(seconds: 30)
            : const Duration(seconds: -10);
        final p = _now + step;
        _setPlayback(
          _playback,
          position: p < Duration.zero
              ? Duration.zero
              : p > _length
              ? _length
              : p,
        );
      case RemoteKey.enter:
        if (_textFocused) await submitText();
      default:
    }
  }

  @override
  Future<void> setVolume(int volume) async {
    _requireConnected();
    _volume = volume.clamp(0, 100);
    _events.add(VolumeChanged(level: _volume, muted: _muted));
  }

  @override
  Future<void> mute() async {
    _requireConnected();
    _muted = !_muted;
    _events.add(VolumeChanged(level: _volume, muted: _muted));
  }

  @override
  Future<void> sendText(String text) async {
    _requireConnected();
    _text.write(text);
  }

  @override
  Future<void> deleteText(int count) async {
    _requireConnected();
    final s = _text.toString();
    _text
      ..clear()
      ..write(s.substring(0, (s.length - count).clamp(0, s.length)));
  }

  @override
  Future<void> submitText() async {
    _requireConnected();
    _setTextFocus(false);
  }

  @override
  Future<List<TvApp>> listApps() async {
    _requireConnected();
    await _work();
    return apps;
  }

  @override
  Future<void> launchApp(String appId) async {
    _requireConnected();
    await _work();
    if (!apps.any((a) => a.id == appId)) {
      throw TvRemoteException(TvErrorCode.protocol, 'No app $appId');
    }
    _appId = appId;
    _setTextFocus(false);
    _setPlayback(
      appId == 'demo.browser' || appId == 'demo.photos'
          ? PlaybackState.stopped
          : PlaybackState.playing,
      position: Duration.zero,
    );
  }

  @override
  Future<bool> openContent(ContentLink link) async {
    _requireConnected();
    await launchApp(
      link.service == StreamingService.youtube ? 'demo.shows' : 'demo.movies',
    );
    return true;
  }

  @override
  Future<void> sendCustom(CustomCommand command) async =>
      throw const TvRemoteException.unsupported('Custom commands');

  @override
  Future<Uint8List?> fetchAppIcon(TvApp app) async => null;

  @override
  Future<void> movePointer(double dx, double dy) async => _requireConnected();

  @override
  Future<void> pointerClick() async => _requireConnected();

  @override
  Future<void> scroll(double dx, double dy) async => _requireConnected();
}
