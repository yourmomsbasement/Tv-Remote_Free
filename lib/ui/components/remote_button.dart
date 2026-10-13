import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
    this.haptics = true,
    this.size = 64,
    this.filled = false,
    this.repeatInterval = const Duration(milliseconds: 150),
    this.maxRepeats = 60,
  });

  final IconData icon;

  /// Spoken by TalkBack / VoiceOver and shown as a tooltip.
  final String label;
  final VoidCallback? onPressed;
  final bool repeat;
  final bool haptics;
  final double size;
  final bool filled;
  final Duration repeatInterval;
  final int maxRepeats;

  @override
  State<RemoteButton> createState() => _RemoteButtonState();
}

class _RemoteButtonState extends State<RemoteButton> {
  Timer? _delay;
  Timer? _repeat;
  int _count = 0;

  void _press() {
    if (widget.haptics) HapticFeedback.selectionClick();
    widget.onPressed?.call();
  }

  void _startRepeat() {
    _count = 0;
    _delay = Timer(const Duration(milliseconds: 350), () {
      _repeat = Timer.periodic(widget.repeatInterval, (t) {
        if (++_count > widget.maxRepeats) return _stopRepeat();
        _press();
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
    final scheme = Theme.of(context).colorScheme;
    final enabled = widget.onPressed != null;
    final background = widget.filled
        ? scheme.primaryContainer
        : scheme.surfaceContainerHighest;
    final foreground = widget.filled
        ? scheme.onPrimaryContainer
        : scheme.onSurfaceVariant;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      excludeSemantics: true,
      onTap: enabled ? _press : null,
      child: Tooltip(
        message: widget.label,
        child: Listener(
          onPointerDown: enabled && widget.repeat
              ? (_) => _startRepeat()
              : null,
          onPointerUp: (_) => _stopRepeat(),
          onPointerCancel: (_) => _stopRepeat(),
          child: Material(
            color: enabled ? background : background.withValues(alpha: 0.4),
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: enabled ? _press : null,
              child: SizedBox.square(
                dimension: widget.size,
                child: Icon(
                  widget.icon,
                  size: widget.size * 0.42,
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
