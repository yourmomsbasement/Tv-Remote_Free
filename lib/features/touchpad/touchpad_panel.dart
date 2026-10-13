import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/capabilities/remote_key.dart';
import '../../core/platform/haptics.dart';
import '../remote/remote_session.dart';
import '../settings/app_settings.dart';
import 'touchpad_gestures.dart';

/// Touch surface. On TVs with a pointer API it moves the cursor; otherwise
/// swipes become arrow keys and a tap becomes OK.
class TouchpadPanel extends ConsumerStatefulWidget {
  const TouchpadPanel({super.key});

  @override
  ConsumerState<TouchpadPanel> createState() => _TouchpadPanelState();
}

class _TouchpadPanelState extends ConsumerState<TouchpadPanel> {
  TouchpadGestures? _gestures;
  Offset _pendingMove = Offset.zero;
  Offset _pendingScroll = Offset.zero;
  Timer? _flushTimer;

  RemoteSession get _remote => ref.read(remoteSessionProvider.notifier);

  void _haptic([HapticEvent event = HapticEvent.press]) =>
      Haptics.play(event, ref.read(settingsProvider).hapticStrength);

  void _onStart(ScaleStartDetails _) {
    final caps = ref.read(remoteSessionProvider).capabilities;
    _gestures = TouchpadGestures(
      pointer: caps.pointer,
      scroll: caps.scroll,
      sensitivity: ref.read(settingsProvider).touchpadSensitivity,
    );
  }

  void _onUpdate(ScaleUpdateDetails details) {
    final gestures = _gestures;
    if (gestures == null) return;
    final actions = gestures.update(
      fingers: details.pointerCount,
      delta: details.focalPointDelta,
    );
    for (final action in actions) {
      switch (action) {
        case PointerMove(:final delta):
          _pendingMove += delta;
          _scheduleFlush();
        case PointerScroll(:final delta):
          _pendingScroll += delta;
          _scheduleFlush();
        case ArrowKey(:final key):
          _haptic(HapticEvent.repeat);
          _remote.sendKey(key);
      }
    }
  }

  /// Coalesces pointer messages to roughly one per frame.
  void _scheduleFlush() {
    _flushTimer ??= Timer(const Duration(milliseconds: 16), () {
      _flushTimer = null;
      final move = _pendingMove;
      final scroll = _pendingScroll;
      _pendingMove = Offset.zero;
      _pendingScroll = Offset.zero;
      if (move != Offset.zero) _remote.movePointer(move.dx, move.dy);
      if (scroll != Offset.zero) _remote.scroll(scroll.dx, scroll.dy);
    });
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
            [
              pointer
                  ? 'Drag to move the pointer. Tap to click.'
                  : 'Swipe to move. Tap for OK.',
              session.capabilities.scroll
                  ? 'Two fingers to scroll.'
                  : 'Two fingers up/down to step through lists.',
            ].join(' '),
            textAlign: TextAlign.center,
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
                onScaleStart: enabled ? _onStart : null,
                onScaleUpdate: enabled ? _onUpdate : null,
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
