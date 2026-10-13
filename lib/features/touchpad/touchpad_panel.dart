import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/capabilities/remote_key.dart';
import '../../core/platform/haptics.dart';
import '../remote/remote_session.dart';
import '../settings/app_settings.dart';

/// Touch surface. On TVs with a pointer API it moves the cursor; otherwise
/// swipes become arrow keys and a tap becomes OK.
class TouchpadPanel extends ConsumerStatefulWidget {
  const TouchpadPanel({super.key});

  @override
  ConsumerState<TouchpadPanel> createState() => _TouchpadPanelState();
}

class _TouchpadPanelState extends ConsumerState<TouchpadPanel> {
  static const _pointerSpeed = 1.6;

  /// Distance a finger travels per arrow key in swipe mode.
  static const _swipeStep = 48.0;

  Offset _pending = Offset.zero;
  Offset _swipe = Offset.zero;
  Timer? _flushTimer;

  RemoteSession get _remote => ref.read(remoteSessionProvider.notifier);

  void _haptic([HapticEvent event = HapticEvent.press]) =>
      Haptics.play(event, ref.read(settingsProvider).hapticStrength);

  /// Coalesces pointer moves to roughly one message per frame.
  void _queueMove(Offset delta) {
    _pending += delta * _pointerSpeed;
    _flushTimer ??= Timer(const Duration(milliseconds: 16), () {
      _flushTimer = null;
      final move = _pending;
      _pending = Offset.zero;
      if (move != Offset.zero) _remote.movePointer(move.dx, move.dy);
    });
  }

  void _swipeBy(Offset delta) {
    _swipe += delta;
    while (_swipe.distance >= _swipeStep) {
      final horizontal = _swipe.dx.abs() > _swipe.dy.abs();
      final RemoteKey key;
      if (horizontal) {
        key = _swipe.dx > 0 ? RemoteKey.right : RemoteKey.left;
        _swipe = Offset(_swipe.dx - _swipeStep * _swipe.dx.sign, 0);
      } else {
        key = _swipe.dy > 0 ? RemoteKey.down : RemoteKey.up;
        _swipe = Offset(0, _swipe.dy - _swipeStep * _swipe.dy.sign);
      }
      _haptic(HapticEvent.repeat);
      _remote.sendKey(key);
    }
  }

  @override
  void dispose() {
    _flushTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(remoteSessionProvider);
    final scheme = Theme.of(context).colorScheme;
    final pointer = session.capabilities.pointer;
    final enabled =
        session.isConnected && (pointer || session.capabilities.navigation);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Text(
            pointer
                ? 'Drag to move the pointer. Tap to click.'
                : 'Swipe to move. Tap for OK.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Semantics(
              label: 'Touchpad',
              hint: pointer ? 'Drag to move pointer' : 'Swipe to navigate',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: enabled
                    ? () {
                        _haptic();
                        pointer
                            ? _remote.pointerClick()
                            : _remote.sendKey(RemoteKey.select);
                      }
                    : null,
                onPanStart: enabled ? (_) => _swipe = Offset.zero : null,
                onPanUpdate: enabled
                    ? (d) => pointer ? _queueMove(d.delta) : _swipeBy(d.delta)
                    : null,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: Center(
                    child: Icon(
                      pointer ? Icons.mouse_outlined : Icons.swipe,
                      size: 48,
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              if (session.capabilities.supportsKey(RemoteKey.back))
                FilledButton.tonalIcon(
                  onPressed: enabled
                      ? () {
                          _haptic();
                          _remote.sendKey(RemoteKey.back);
                        }
                      : null,
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Back'),
                ),
              if (session.capabilities.supportsKey(RemoteKey.home))
                FilledButton.tonalIcon(
                  onPressed: enabled
                      ? () {
                          _haptic();
                          _remote.sendKey(RemoteKey.home);
                        }
                      : null,
                  icon: const Icon(Icons.home_outlined),
                  label: const Text('Home'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
