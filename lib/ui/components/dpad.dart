import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/capabilities/remote_key.dart';
import 'remote_button.dart';

/// Directional pad with a centre OK button.
class DPad extends StatelessWidget {
  const DPad({
    super.key,
    required this.onKey,
    this.enabled = true,
    this.haptics = true,
    this.size = 240,
  });

  final void Function(RemoteKey key) onKey;
  final bool enabled;
  final bool haptics;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final button = size * 0.27;

    Widget arrow(RemoteKey key, IconData icon, String label) => RemoteButton(
      icon: icon,
      label: label,
      size: button,
      repeat: true,
      haptics: haptics,
      onPressed: enabled ? () => onKey(key) : null,
    );

    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: scheme.surfaceContainer,
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Align(
              alignment: Alignment.topCenter,
              child: arrow(RemoteKey.up, Icons.keyboard_arrow_up, 'Up'),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: arrow(RemoteKey.down, Icons.keyboard_arrow_down, 'Down'),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: arrow(RemoteKey.left, Icons.keyboard_arrow_left, 'Left'),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: arrow(
                RemoteKey.right,
                Icons.keyboard_arrow_right,
                'Right',
              ),
            ),
            Semantics(
              button: true,
              label: 'OK',
              excludeSemantics: true,
              child: FilledButton(
                onPressed: enabled
                    ? () {
                        if (haptics) HapticFeedback.selectionClick();
                        onKey(RemoteKey.select);
                      }
                    : null,
                style: FilledButton.styleFrom(
                  shape: const CircleBorder(),
                  fixedSize: Size.square(size * 0.36),
                ),
                child: const Text(
                  'OK',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
