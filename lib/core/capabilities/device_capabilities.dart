import 'remote_key.dart';

/// How the keyboard subsystem delivers text to the TV, best first.
enum TextInputStrategy {
  /// The TV exposes a text API (insert/delete) for the focused field.
  nativeTextApi,

  /// Characters are sent one at a time as key events (append-only).
  characterEvents,

  /// No text input; the user must navigate the TV's on-screen keyboard.
  directionalKeyboard,
}

/// What a connected device can actually do.
///
/// Values come from the adapter after connecting, and may depend on the model
/// or firmware. The UI hides or disables anything reported as unsupported.
class DeviceCapabilities {
  const DeviceCapabilities({
    required this.keys,
    this.volumeSet = false,
    this.powerOff = false,
    this.powerOn = false,
    this.textInput = false,
    this.textInputStrategy = TextInputStrategy.directionalKeyboard,
    this.textFieldDetection = false,
    this.pointer = false,
    this.scroll = false,
    this.activity = false,
    this.playbackState = false,
    this.playbackPosition = false,
    this.appLaunch = false,
    this.appList = false,
    this.pairingRequired = false,
    this.voiceInput = false,
  });

  static const none = DeviceCapabilities(keys: {});

  /// Remote keys the device accepts.
  final Set<RemoteKey> keys;

  /// Absolute volume level can be set (not just stepped up/down).
  final bool volumeSet;
  final bool powerOff;

  /// The device can be woken from standby (protocol command or Wake-on-LAN).
  final bool powerOn;
  final bool textInput;
  final TextInputStrategy textInputStrategy;

  /// The TV reports when one of its text fields gains or loses focus.
  final bool textFieldDetection;

  /// Relative pointer/cursor movement is supported.
  final bool pointer;

  /// Pointer-style scrolling (two-finger drag on the touchpad).
  final bool scroll;

  /// Reports the foreground app.
  final bool activity;

  /// Reports playing/paused.
  final bool playbackState;

  /// Reports playback position and duration.
  final bool playbackPosition;
  final bool appLaunch;
  final bool appList;
  final bool pairingRequired;
  final bool voiceInput;

  bool get navigation => navigationKeys.every(keys.contains);
  bool get volume =>
      keys.contains(RemoteKey.volumeUp) && keys.contains(RemoteKey.volumeDown);
  bool get mute => keys.contains(RemoteKey.mute);
  bool get channels =>
      keys.contains(RemoteKey.channelUp) &&
      keys.contains(RemoteKey.channelDown);
  bool get mediaControls => keys.any(mediaKeys.contains);

  bool supportsKey(RemoteKey key) => keys.contains(key);

  Map<String, Object> toJson() => {
    'navigation': navigation,
    'volume': volume,
    'volume_set': volumeSet,
    'mute': mute,
    'power_off': powerOff,
    'power_on': powerOn,
    'text_input': textInput,
    'text_input_strategy': textInputStrategy.name,
    'text_field_detection': textFieldDetection,
    'pointer': pointer,
    'scroll': scroll,
    'activity': activity,
    'playback_state': playbackState,
    'playback_position': playbackPosition,
    'app_launch': appLaunch,
    'app_list': appList,
    'media_controls': mediaControls,
    'channels': channels,
    'voice_input': voiceInput,
    'pairing_required': pairingRequired,
  };
}
