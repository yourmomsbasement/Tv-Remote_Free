import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/platform/haptics.dart';
import '../themes/remote_style.dart';

/// A remote control button with haptics and optional hold-to-repeat.
///
/// Repeats are paced locally (one command per [repeatInterval]) and capped by
/// [maxRepeats] so a stuck finger cannot cause runaway navigation.
class RemoteButton extends StatefulWidget {
  const RemoteButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.repeat = false,
    this.haptics = HapticStrength.medium,
    this.size = 64,
    this.filled = false,
    this.repeatInterval = const Duration(milliseconds: 150),
    this.maxRepeats = 60,
    this.scaled = true,
  });

  final IconData icon;

  /// Spoken by TalkBack / VoiceOver and shown as a tooltip.
  final String label;
  final VoidCallback? onPressed;
  final bool repeat;
  final HapticStrength haptics;
  final double size;
  final bool filled;
  final Duration repeatInterval;
  final int maxRepeats;

  /// Apply the theme's button scale (off for buttons sized by a parent,
  /// such as the D-pad arrows).
  final bool scaled;

  @override
  State<RemoteButton> createState() => _RemoteButtonState();
}

class _RemoteButtonState extends State<RemoteButton> {
  Timer? _delay;
  Timer? _repeat;
  int _count = 0;

  /// Set once a hold has started repeating; the release must not also
  /// count as a tap.
  bool _held = false;

  void _press() {
    Haptics.play(HapticEvent.press, widget.haptics);
    widget.onPressed?.call();
  }

  void _onTap() {
    if (_held) {
      _held = false;
      return;
    }
    _press();
  }

  void _startRepeat() {
    _count = 0;
    _held = false;
    _delay = Timer(const Duration(milliseconds: 350), () {
      // A distinct, stronger pulse marks the switch to repeating.
      _held = true;
      Haptics.play(HapticEvent.hold, widget.haptics);
      widget.onPressed?.call();
      _repeat = Timer.periodic(widget.repeatInterval, (t) {
        if (++_count > widget.maxRepeats) return _stopRepeat();
        Haptics.play(HapticEvent.repeat, widget.haptics);
        widget.onPressed?.call();
      });
    });
  }

  void _stopRepeat() {
    _delay?.cancel();
    _repeat?.cancel();
    _delay = _repeat = null;
  }

  @override
  void dispose() {
    _stopRepeat();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = RemoteStyle.of(context);
    final size = widget.size * (widget.scaled ? style.buttonScale : 1);
    final enabled = widget.onPressed != null;
    final background = widget.filled ? style.accentButton : style.button;
    final foreground = widget.filled
        ? style.accentButtonIcon
        : style.buttonIcon;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      excludeSemantics: true,
      onTap: enabled ? _onTap : null,
      child: Tooltip(
        message: widget.label,
        // Holding a repeating button must not pop a tooltip (and its own
        // vibration) over the repeats.
        triggerMode: widget.repeat
            ? TooltipTriggerMode.manual
            : TooltipTriggerMode.longPress,
        enableFeedback: false,
        child: Listener(
          onPointerDown: enabled && widget.repeat
              ? (_) => _startRepeat()
              : null,
          onPointerUp: (_) => _stopRepeat(),
          onPointerCancel: (_) => _stopRepeat(),
          child: Material(
            color: enabled ? background : background.withValues(alpha: 0.4),
            shape: style.buttonBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: enabled ? _onTap : null,
              child: SizedBox.square(
                dimension: size,
                child: Icon(
                  widget.icon,
                  size: size * 0.42,
                  color: enabled
                      ? foreground
                      : foreground.withValues(alpha: 0.4),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
