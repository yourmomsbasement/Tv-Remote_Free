import 'dart:io';

import 'package:flutter/services.dart';

/// User-selectable vibration strength.
enum HapticStrength { off, light, medium, strong }

/// What the user did, so each gets a distinct feel.
enum HapticEvent {
  /// A button tap.
  press,

  /// A button held long enough to start repeating.
  hold,

  /// Each automatic repeat while held (and each touchpad swipe step).
  repeat,
}

/// Physical effects, weakest to strongest.
enum HapticEffect { tick, light, medium, heavy }

/// Plays button feedback.
///
/// Android: Flutter's built-in feedback goes through the view's haptic
/// constants, which many phones play very faintly or not at all (and which
/// follow the system "touch feedback" setting). Instead this uses the
/// Vibrator's predefined click effects through `MainActivity.kt`, falling
/// back to Flutter's feedback if that is unavailable. iOS uses
/// UIImpactFeedbackGenerator through Flutter.
abstract final class Haptics {
  static const _channel = MethodChannel('tv_remote_free/haptics');
  static bool _nativeUnavailable = false;

  /// The effect for [event] at [strength], or null for none.
  static HapticEffect? effectFor(HapticEvent event, HapticStrength strength) =>
      switch ((strength, event)) {
        (HapticStrength.off, _) => null,
        (HapticStrength.light, HapticEvent.press) => HapticEffect.tick,
        (HapticStrength.light, HapticEvent.hold) => HapticEffect.light,
        (HapticStrength.light, HapticEvent.repeat) => HapticEffect.tick,
        (HapticStrength.medium, HapticEvent.press) => HapticEffect.light,
        (HapticStrength.medium, HapticEvent.hold) => HapticEffect.heavy,
        (HapticStrength.medium, HapticEvent.repeat) => HapticEffect.tick,
        (HapticStrength.strong, HapticEvent.press) => HapticEffect.medium,
        (HapticStrength.strong, HapticEvent.hold) => HapticEffect.heavy,
        (HapticStrength.strong, HapticEvent.repeat) => HapticEffect.light,
      };

  static Future<void> play(HapticEvent event, HapticStrength strength) async {
    final effect = effectFor(event, strength);
    if (effect == null) return;
    if (_isAndroid && !_nativeUnavailable) {
      try {
        await _channel.invokeMethod<void>('play', effect.name);
        return;
      } on MissingPluginException {
        _nativeUnavailable = true;
      } on PlatformException {
        _nativeUnavailable = true;
      }
    }
    await switch (effect) {
      HapticEffect.tick => HapticFeedback.selectionClick(),
      HapticEffect.light => HapticFeedback.lightImpact(),
      HapticEffect.medium => HapticFeedback.mediumImpact(),
      HapticEffect.heavy => HapticFeedback.heavyImpact(),
    };
  }

  static bool get _isAndroid {
    try {
      return Platform.isAndroid;
    } on UnsupportedError {
      return false;
    }
  }
}
