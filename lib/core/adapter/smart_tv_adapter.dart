import 'dart:async';
import 'dart:typed_data';

import '../capabilities/device_capabilities.dart';
import '../capabilities/remote_key.dart';

/// Connection lifecycle of an adapter.
enum ConnectionStatus { disconnected, connecting, awaitingPairing, connected }

/// Information needed by an adapter to reach and authenticate with a TV.
class PairingRequest {
  const PairingRequest({this.pin, this.storedCredential});

  /// PIN shown on the TV, for protocols that use PIN pairing.
  final String? pin;

  /// Credential from a previous successful pairing, if any.
  final String? storedCredential;
}

/// Events pushed from the TV to the app.
sealed class DeviceEvent {
  const DeviceEvent();
}

class ConnectionStatusChanged extends DeviceEvent {
  const ConnectionStatusChanged(this.status, {this.error});
  final ConnectionStatus status;
  final Object? error;
}

/// The TV is asking the user to accept the pairing request on screen,
/// or (for PIN protocols) to enter the PIN it displays.
class PairingPromptShown extends DeviceEvent {
  const PairingPromptShown({this.needsPin = false});
  final bool needsPin;
}

/// Pairing succeeded; [credential] must be persisted in the secure store.
class PairingCompleted extends DeviceEvent {
  const PairingCompleted(this.credential);
  final String credential;
}

/// A text field on the TV gained or lost focus.
class TextFieldFocusChanged extends DeviceEvent {
  const TextFieldFocusChanged({
    required this.focused,
    this.sensitive = false,
    this.inputType,
  });
  final bool focused;

  /// The TV marked the field as a password or other hidden input.
  final bool sensitive;
  final String? inputType;
}

class VolumeChanged extends DeviceEvent {
  const VolumeChanged({this.level, this.muted});
  final int? level;
  final bool? muted;
}

/// Extra device details learned after connecting (e.g. MAC for Wake-on-LAN).
class DeviceInfoUpdated extends DeviceEvent {
  const DeviceInfoUpdated({this.name, this.model, this.macAddress});
  final String? name;
  final String? model;
  final String? macAddress;
}

class TvApp {
  const TvApp({required this.id, required this.name, this.iconUrl});
  final String id;
  final String name;
  final String? iconUrl;
}

/// Contract every manufacturer protocol implements.
///
/// Every operation is capability-gated: calling something the device does not
/// support throws a [TvRemoteException] with [TvErrorCode.unsupported] rather
/// than silently doing nothing.
abstract class SmartTVAdapter {
  /// Stable protocol identifier stored in the devices table.
  String get protocol;

  ConnectionStatus get status;

  /// Opens the connection, pairing if needed. [pairing] carries a stored
  /// credential so previously paired TVs reconnect without prompting.
  Future<void> connect({PairingRequest pairing = const PairingRequest()});

  Future<void> disconnect();

  /// Capabilities of the connected device. Accurate only after [connect].
  Future<DeviceCapabilities> getCapabilities();

  /// Completes a pairing that needs user input, such as a PIN.
  Future<void> pair(PairingRequest request);

  Future<void> sendKey(RemoteKey key);

  Future<void> setVolume(int volume);

  Future<void> mute();

  /// Inserts [text] at the cursor of the focused TV text field.
  Future<void> sendText(String text);

  /// Deletes [count] characters before the cursor.
  Future<void> deleteText(int count);

  /// Submits the focused text field (Enter / search).
  Future<void> submitText();

  Future<List<TvApp>> listApps();

  Future<void> launchApp(String appId);

  /// Downloads the icon for [app] from the TV, or null if it has none or it
  /// cannot be fetched. Never throws.
  Future<Uint8List?> fetchAppIcon(TvApp app);

  /// Moves the on-screen pointer by a relative offset in logical pixels.
  Future<void> movePointer(double dx, double dy);

  /// Clicks at the current pointer position.
  Future<void> pointerClick();

  /// Scrolls the content under the pointer (two-finger drag).
  Future<void> scroll(double dx, double dy);

  Stream<DeviceEvent> get events;
}
