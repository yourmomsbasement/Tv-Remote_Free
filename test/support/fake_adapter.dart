import 'dart:async';
import 'dart:typed_data';

import 'package:tv_remote_free/core/adapter/smart_tv_adapter.dart';
import 'package:tv_remote_free/core/capabilities/device_capabilities.dart';
import 'package:tv_remote_free/core/capabilities/remote_key.dart';
import 'package:tv_remote_free/core/content/content_link.dart';
import 'package:tv_remote_free/core/errors.dart';

/// Records every call so tests can assert exactly what reached the "TV".
class FakeAdapter implements SmartTVAdapter {
  FakeAdapter({DeviceCapabilities? capabilities})
    : capabilities =
          capabilities ??
          const DeviceCapabilities(
            keys: {...RemoteKey.values},
            textInput: true,
            textInputStrategy: TextInputStrategy.characterEvents,
          );

  DeviceCapabilities capabilities;
  final calls = <String>[];
  final eventController = StreamController<DeviceEvent>.broadcast();

  /// What an append-only TV text field would now contain.
  String tvText = '';
  TvRemoteException? failNext;
  ConnectionStatus _status = ConnectionStatus.disconnected;

  void _maybeFail() {
    final error = failNext;
    if (error != null) {
      failNext = null;
      throw error;
    }
  }

  @override
  String get protocol => 'fake';

  @override
  ConnectionStatus get status => _status;

  @override
  Stream<DeviceEvent> get events => eventController.stream;

  @override
  Future<void> connect({
    PairingRequest pairing = const PairingRequest(),
  }) async {
    calls.add('connect');
    _status = ConnectionStatus.connected;
  }

  @override
  Future<void> disconnect() async {
    calls.add('disconnect');
    _status = ConnectionStatus.disconnected;
  }

  @override
  Future<DeviceCapabilities> getCapabilities() async => capabilities;

  @override
  Future<void> pair(PairingRequest request) async {
    _maybeFail();
    calls.add('pair:${request.pin}');
  }

  @override
  Future<void> sendKey(RemoteKey key) async {
    _maybeFail();
    calls.add('key:${key.name}');
  }

  @override
  Future<void> setVolume(int volume) async => calls.add('volume:$volume');

  @override
  Future<void> mute() async => calls.add('mute');

  @override
  Future<void> sendText(String text) async {
    _maybeFail();
    calls.add('text:$text');
    tvText += text;
  }

  @override
  Future<void> deleteText(int count) async {
    _maybeFail();
    calls.add('delete:$count');
    final runes = tvText.runes.toList();
    tvText = String.fromCharCodes(
      runes.sublist(0, (runes.length - count).clamp(0, runes.length)),
    );
  }

  @override
  Future<void> submitText() async => calls.add('submit');

  List<TvApp> apps = const [];

  @override
  Future<List<TvApp>> listApps() async => apps;

  @override
  Future<void> launchApp(String appId) async => calls.add('launch:$appId');

  @override
  Future<bool> openContent(ContentLink link) async {
    _maybeFail();
    calls.add('open:${link.service.name}:${link.contentId}');
    return link.contentId != null;
  }

  /// Icon bytes to return per app id.
  final icons = <String, Uint8List>{};

  @override
  Future<Uint8List?> fetchAppIcon(TvApp app) async {
    calls.add('icon:${app.id}');
    return icons[app.id];
  }

  @override
  Future<void> movePointer(double dx, double dy) async =>
      calls.add('move:$dx,$dy');

  @override
  Future<void> pointerClick() async => calls.add('click');

  @override
  Future<void> scroll(double dx, double dy) async =>
      calls.add('scroll:$dx,$dy');
}
