import 'dart:convert';

import '../../core/capabilities/device_capabilities.dart';
import '../../core/capabilities/remote_key.dart';

/// One action in a macro.
sealed class MacroStep {
  const MacroStep();

  String get type;
  Map<String, Object?> toJson();

  /// Short human-readable description for lists and run logs.
  String describe();

  /// Why [capabilities] cannot run this step, or null if it can.
  String? unsupportedReason(DeviceCapabilities c) => null;

  static MacroStep fromJson(Map<String, Object?> json) =>
      switch (json['type']) {
        'power_on' => const PowerOnStep(),
        'wait_connected' => WaitConnectedStep(
          timeoutSeconds: _int(json['timeout'], 30, 5, 120),
        ),
        'key' => KeyStep(
          RemoteKey.values.byName(json['key']! as String),
          times: _int(json['times'], 1, 1, 50),
        ),
        'launch_app' => LaunchAppStep(
          appId: json['app']! as String,
          appName: (json['name'] as String?) ?? json['app']! as String,
        ),
        'volume' => VolumeStep(_int(json['level'], 10, 0, 100)),
        'delay' => DelayStep(_int(json['ms'], 1000, 100, 60000)),
        'text' => TextStep(
          (json['text'] as String?) ?? '',
          submit: json['submit'] == true,
        ),
        final other => throw FormatException('Unknown macro step "$other"'),
      };

  static int _int(Object? v, int fallback, int min, int max) =>
      (v is num ? v.round() : fallback).clamp(min, max);
}

/// Turns the TV on (protocol command or Wake-on-LAN).
class PowerOnStep extends MacroStep {
  const PowerOnStep();
  @override
  String get type => 'power_on';
  @override
  Map<String, Object?> toJson() => {'type': type};
  @override
  String describe() => 'Turn on the TV';
}

/// Waits until the TV accepts commands (e.g. after power on).
class WaitConnectedStep extends MacroStep {
  const WaitConnectedStep({this.timeoutSeconds = 30});
  final int timeoutSeconds;
  @override
  String get type => 'wait_connected';
  @override
  Map<String, Object?> toJson() => {'type': type, 'timeout': timeoutSeconds};
  @override
  String describe() => 'Wait for the TV (up to $timeoutSeconds s)';
}

class KeyStep extends MacroStep {
  const KeyStep(this.key, {this.times = 1});
  final RemoteKey key;
  final int times;
  @override
  String get type => 'key';
  @override
  Map<String, Object?> toJson() => {
    'type': type,
    'key': key.name,
    'times': times,
  };
  @override
  String describe() => 'Press ${keyLabel(key)}${times > 1 ? ' ×$times' : ''}';
  @override
  String? unsupportedReason(DeviceCapabilities c) => c.supportsKey(key)
      ? null
      : '${keyLabel(key)} is not available on this TV';
}

/// Opens an app (or, on TVs that list them, an input such as HDMI 1).
class LaunchAppStep extends MacroStep {
  const LaunchAppStep({required this.appId, required this.appName});
  final String appId;
  final String appName;
  @override
  String get type => 'launch_app';
  @override
  Map<String, Object?> toJson() => {
    'type': type,
    'app': appId,
    'name': appName,
  };
  @override
  String describe() => 'Open $appName';
  @override
  String? unsupportedReason(DeviceCapabilities c) =>
      c.appLaunch ? null : 'This TV cannot open apps from the phone';
}

class VolumeStep extends MacroStep {
  const VolumeStep(this.level);
  final int level;
  @override
  String get type => 'volume';
  @override
  Map<String, Object?> toJson() => {'type': type, 'level': level};
  @override
  String describe() => 'Set volume to $level';
  @override
  String? unsupportedReason(DeviceCapabilities c) =>
      c.volumeSet ? null : 'This TV cannot set an exact volume';
}

class DelayStep extends MacroStep {
  const DelayStep(this.milliseconds);
  final int milliseconds;
  @override
  String get type => 'delay';
  @override
  Map<String, Object?> toJson() => {'type': type, 'ms': milliseconds};
  @override
  String describe() {
    final s = milliseconds / 1000;
    return 'Wait ${s == s.roundToDouble() ? s.round() : s.toStringAsFixed(1)} s';
  }
}

/// Types text into the focused TV field, optionally pressing Enter.
class TextStep extends MacroStep {
  const TextStep(this.text, {this.submit = false});
  final String text;
  final bool submit;
  @override
  String get type => 'text';
  @override
  Map<String, Object?> toJson() => {
    'type': type,
    'text': text,
    'submit': submit,
  };
  @override
  String describe() => 'Type "$text"${submit ? ' and press Enter' : ''}';
  @override
  String? unsupportedReason(DeviceCapabilities c) =>
      c.textInput ? null : 'This TV does not accept text from the phone';
}

/// A named sequence of steps for one TV (or whichever TV is connected).
class Macro {
  const Macro({
    required this.id,
    required this.name,
    required this.steps,
    this.deviceId,
    this.stopOnError = true,
  });

  final String id;
  final String name;

  /// The TV to run on, or null for the currently connected TV.
  final String? deviceId;
  final List<MacroStep> steps;

  /// Stop at the first step that fails; otherwise skip it and carry on.
  final bool stopOnError;

  Macro copyWith({
    String? name,
    String? Function()? deviceId,
    List<MacroStep>? steps,
    bool? stopOnError,
  }) => Macro(
    id: id,
    name: name ?? this.name,
    deviceId: deviceId == null ? this.deviceId : deviceId(),
    steps: steps ?? this.steps,
    stopOnError: stopOnError ?? this.stopOnError,
  );

  String encode() => jsonEncode({
    'version': 1,
    'name': name,
    'device': deviceId,
    'stop_on_error': stopOnError,
    'steps': [for (final s in steps) s.toJson()],
  });

  static Macro decode(String id, String json) {
    final map = jsonDecode(json) as Map<String, Object?>;
    return Macro(
      id: id,
      name: (map['name'] as String?) ?? 'Macro',
      deviceId: map['device'] as String?,
      stopOnError: map['stop_on_error'] != false,
      steps: [
        for (final s in (map['steps'] as List? ?? const []))
          if (s is Map<String, Object?>) MacroStep.fromJson(s),
      ],
    );
  }

  /// Ready-made starting point matching the design's example.
  static Macro movieNight(String id) => Macro(
    id: id,
    name: 'Movie night',
    steps: const [
      PowerOnStep(),
      WaitConnectedStep(),
      DelayStep(3000),
      LaunchAppStep(appId: 'netflix', appName: 'Netflix'),
      VolumeStep(18),
    ],
  );
}

/// Friendly names for keys in macro editors and logs.
String keyLabel(RemoteKey key) => switch (key) {
  RemoteKey.select => 'OK',
  RemoteKey.playPause => 'Play/Pause',
  RemoteKey.volumeUp => 'Volume up',
  RemoteKey.volumeDown => 'Volume down',
  RemoteKey.channelUp => 'Channel up',
  RemoteKey.channelDown => 'Channel down',
  RemoteKey.fastForward => 'Fast forward',
  RemoteKey.powerOff => 'Power off',
  RemoteKey.powerOn => 'Power on',
  RemoteKey.input => 'Input',
  _ => key.name[0].toUpperCase() + key.name.substring(1),
};
