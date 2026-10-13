import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/adapter/smart_tv_adapter.dart';
import '../../core/capabilities/device_capabilities.dart';
import '../../core/capabilities/remote_key.dart';
import '../../core/connection/backoff.dart';
import '../../core/connection/wake_on_lan.dart';
import '../../core/errors.dart';
import '../../core/storage/device_record.dart';
import '../devices/saved_devices.dart';
import '../keyboard/keyboard_controller.dart';

class RemoteSessionState {
  const RemoteSessionState({
    this.device,
    this.status = ConnectionStatus.disconnected,
    this.capabilities = DeviceCapabilities.none,
    this.error,
    this.awaitingPairing = false,
    this.reconnecting = false,
    this.volume,
    this.muted,
    this.textFieldFocused = false,
  });

  final DeviceRecord? device;
  final ConnectionStatus status;
  final DeviceCapabilities capabilities;
  final TvRemoteException? error;
  final bool awaitingPairing;
  final bool reconnecting;
  final int? volume;
  final bool? muted;
  final bool textFieldFocused;

  bool get isConnected => status == ConnectionStatus.connected;

  /// Power-on works through the protocol or Wake-on-LAN with a known MAC.
  bool get canPowerOn =>
      capabilities.powerOn ||
      (device?.macAddress != null && WakeOnLan.isValidMac(device!.macAddress!));

  RemoteSessionState copyWith({
    DeviceRecord? device,
    ConnectionStatus? status,
    DeviceCapabilities? capabilities,
    TvRemoteException? Function()? error,
    bool? awaitingPairing,
    bool? reconnecting,
    int? volume,
    bool? muted,
    bool? textFieldFocused,
  }) => RemoteSessionState(
    device: device ?? this.device,
    status: status ?? this.status,
    capabilities: capabilities ?? this.capabilities,
    error: error == null ? this.error : error(),
    awaitingPairing: awaitingPairing ?? this.awaitingPairing,
    reconnecting: reconnecting ?? this.reconnecting,
    volume: volume ?? this.volume,
    muted: muted ?? this.muted,
    textFieldFocused: textFieldFocused ?? this.textFieldFocused,
  );
}

/// The unified remote controller: owns the active adapter, routes commands
/// after checking capabilities, persists pairing, and recovers connections.
class RemoteSession extends Notifier<RemoteSessionState> {
  static const maxReconnectAttempts = 6;

  KeyboardController? _keyboard;
  KeyboardController get keyboard => _keyboard ??= KeyboardController();
  SmartTVAdapter? _adapter;
  StreamSubscription<DeviceEvent>? _events;
  Timer? _reconnectTimer;
  final _backoff = Backoff();
  bool _wantConnected = false;

  @override
  RemoteSessionState build() {
    ref.onDispose(() {
      _wantConnected = false;
      _reconnectTimer?.cancel();
      _teardownAdapter();
      _keyboard?.dispose();
      _keyboard = null;
    });
    return const RemoteSessionState();
  }

  SmartTVAdapter? get adapter => _adapter;

  Future<void> connect(DeviceRecord device) async {
    if (state.device?.id != device.id) await disconnect();
    _wantConnected = true;
    _backoff.reset();
    _reconnectTimer?.cancel();
    state = RemoteSessionState(device: device);
    await _open(device);
  }

  Future<void> _open(DeviceRecord device) async {
    // Supersedes any attempt in flight; its result is ignored below.
    await _teardownAdapter();
    // Another attempt started while we were tearing down; let it win.
    if (_adapter != null) return;
    final driver = ref
        .read(discoveryServiceProvider)
        .driverFor(device.protocol);
    final adapter = _adapter = driver.createAdapter(device);
    _events = adapter.events.listen(_onEvent);
    state = state.copyWith(
      status: ConnectionStatus.connecting,
      error: () => null,
    );
    try {
      final credential = await ref
          .read(credentialStoreProvider)
          .read(device.id);
      await adapter.connect(
        pairing: PairingRequest(storedCredential: credential),
      );
      if (!identical(adapter, _adapter)) return;
      final capabilities = await adapter.getCapabilities();
      keyboard.attach(adapter, capabilities);
      _backoff.reset();
      state = state.copyWith(
        status: ConnectionStatus.connected,
        capabilities: capabilities,
        awaitingPairing: false,
        reconnecting: false,
        error: () => null,
      );
      await _saveDevice(state.device!.copyWith(lastConnected: DateTime.now()));
    } on TvRemoteException catch (e) {
      if (!identical(adapter, _adapter)) return;
      if (e.code == TvErrorCode.pairingRequired) {
        await ref.read(credentialStoreProvider).delete(device.id);
      }
      state = state.copyWith(
        status: ConnectionStatus.disconnected,
        awaitingPairing: false,
        error: () => e,
      );
      if (e.code == TvErrorCode.unreachable || e.code == TvErrorCode.timeout) {
        _scheduleReconnect();
      } else {
        _wantConnected = false;
      }
    }
  }

  void _onEvent(DeviceEvent event) {
    switch (event) {
      case PairingPromptShown():
        state = state.copyWith(awaitingPairing: true);
      case PairingCompleted(:final credential):
        final id = state.device?.id;
        if (id != null) ref.read(credentialStoreProvider).write(id, credential);
      case DeviceInfoUpdated(:final name, :final model, :final macAddress):
        final device = state.device;
        if (device == null) return;
        // Keep the user's name for the TV once saved; only fill blanks.
        final updated = device.copyWith(
          name: device.name.isEmpty ? name : null,
          model: model,
          macAddress: macAddress,
        );
        state = state.copyWith(device: updated);
        _saveDevice(updated);
      case TextFieldFocusChanged():
        keyboard.onTextFieldFocus(event);
        state = state.copyWith(textFieldFocused: event.focused);
      case VolumeChanged(:final level, :final muted):
        state = state.copyWith(volume: level, muted: muted);
      case ConnectionStatusChanged(:final status):
        if (status == ConnectionStatus.disconnected &&
            state.status == ConnectionStatus.connected) {
          keyboard.detach();
          state = state.copyWith(
            status: ConnectionStatus.disconnected,
            textFieldFocused: false,
          );
          _scheduleReconnect();
        }
    }
  }

  Future<void> _saveDevice(DeviceRecord device) async {
    // Only persist TVs the user has saved (or is saving by connecting).
    await ref.read(savedDevicesProvider.notifier).save(device);
  }

  void _scheduleReconnect() {
    final device = state.device;
    if (!_wantConnected || device == null) return;
    if (_backoff.attempt >= maxReconnectAttempts) {
      state = state.copyWith(reconnecting: false);
      return;
    }
    state = state.copyWith(reconnecting: true);
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(_backoff.next(), () {
      if (_wantConnected) _open(state.device!);
    });
  }

  /// Retry now (e.g. user tapped "Reconnect" or the app came to foreground).
  Future<void> reconnect() async {
    final device = state.device;
    if (device == null) return;
    _wantConnected = true;
    _backoff.reset();
    _reconnectTimer?.cancel();
    await _open(device);
  }

  Future<void> disconnect() async {
    _wantConnected = false;
    _reconnectTimer?.cancel();
    await _teardownAdapter();
    state = state.copyWith(
      status: ConnectionStatus.disconnected,
      reconnecting: false,
      awaitingPairing: false,
      textFieldFocused: false,
    );
  }

  /// App went to background: drop sockets to save battery, remember intent.
  Future<void> suspend() async {
    final wanted = _wantConnected;
    await disconnect();
    _wantConnected = wanted;
  }

  Future<void> resume() async {
    if (_wantConnected && !state.isConnected) await reconnect();
  }

  Future<void> _teardownAdapter() async {
    final adapter = _adapter;
    _adapter = null;
    await _events?.cancel();
    _events = null;
    keyboard.detach();
    await adapter?.disconnect();
  }

  void clearError() => state = state.copyWith(error: () => null);

  /// Runs a command; failures become [RemoteSessionState.error].
  Future<bool> _run(
    Future<void> Function(SmartTVAdapter adapter) command,
  ) async {
    final adapter = _adapter;
    if (adapter == null || !state.isConnected) {
      state = state.copyWith(
        error: () => const TvRemoteException.notConnected(),
      );
      return false;
    }
    try {
      await command(adapter);
      return true;
    } on TvRemoteException catch (e) {
      state = state.copyWith(error: () => e);
      if (e.code == TvErrorCode.unreachable) {
        keyboard.detach();
        state = state.copyWith(status: ConnectionStatus.disconnected);
        _scheduleReconnect();
      }
      return false;
    }
  }

  Future<bool> _gated(
    bool supported,
    String operation,
    Future<void> Function(SmartTVAdapter adapter) command,
  ) {
    if (!supported) {
      state = state.copyWith(
        error: () => TvRemoteException.unsupported(operation),
      );
      return Future.value(false);
    }
    return _run(command);
  }

  Future<bool> sendKey(RemoteKey key) => _gated(
    state.capabilities.supportsKey(key),
    'The ${key.name} key',
    (a) => a.sendKey(key),
  );

  Future<bool> setVolume(int level) => _gated(
    state.capabilities.volumeSet,
    'Setting the volume',
    (a) => a.setVolume(level),
  );

  Future<bool> launchApp(String appId) => _gated(
    state.capabilities.appLaunch,
    'Launching apps',
    (a) => a.launchApp(appId),
  );

  Future<List<TvApp>> listApps() async {
    final adapter = _adapter;
    if (adapter == null || !state.capabilities.appList) return const [];
    return adapter.listApps();
  }

  Future<bool> movePointer(double dx, double dy) => _gated(
    state.capabilities.pointer,
    'Pointer control',
    (a) => a.movePointer(dx, dy),
  );

  Future<bool> pointerClick() => _gated(
    state.capabilities.pointer,
    'Pointer control',
    (a) => a.pointerClick(),
  );

  /// Turns the TV on: protocol command if connected, else Wake-on-LAN and
  /// reconnect.
  Future<bool> powerOn() async {
    if (state.isConnected && state.capabilities.powerOn) {
      return sendKey(RemoteKey.powerOn);
    }
    final mac = state.device?.macAddress;
    if (mac == null || !WakeOnLan.isValidMac(mac)) {
      state = state.copyWith(
        error: () => const TvRemoteException.unsupported('Turning on'),
      );
      return false;
    }
    try {
      await WakeOnLan.send(mac);
    } on Exception catch (e) {
      state = state.copyWith(
        error: () => TvRemoteException(
          TvErrorCode.unreachable,
          'Could not send Wake-on-LAN',
          cause: e,
        ),
      );
      return false;
    }
    _wantConnected = true;
    _backoff.reset();
    _scheduleReconnect();
    return true;
  }
}

final remoteSessionProvider =
    NotifierProvider<RemoteSession, RemoteSessionState>(RemoteSession.new);
