import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/adapter/smart_tv_adapter.dart';
import '../../core/capabilities/remote_key.dart';
import '../../core/platform/haptics.dart';
import '../../ui/components/remote_button.dart';
import '../settings/app_settings.dart';
import 'remote_session.dart';

String formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(h > 0 ? 2 : 1, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}

/// Playback controls (and, where the TV reports it, progress) for whatever
/// is playing. Shown at the top of the remote while media is active.
class NowPlayingCard extends ConsumerStatefulWidget {
  const NowPlayingCard({super.key, required this.activity});

  final MediaActivity activity;

  @override
  ConsumerState<NowPlayingCard> createState() => _NowPlayingCardState();
}

class _NowPlayingCardState extends ConsumerState<NowPlayingCard> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // Repaint the extrapolated position between TV reports.
    _ticker = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted && widget.activity.state == PlaybackState.playing) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activity = widget.activity;
    final caps = ref.watch(remoteSessionProvider.select((s) => s.capabilities));
    final haptics = ref.watch(settingsProvider.select((s) => s.hapticStrength));
    final remote = ref.read(remoteSessionProvider.notifier);
    final theme = Theme.of(context);
    final playing = activity.state == PlaybackState.playing;

    Widget? key(
      RemoteKey k,
      IconData icon,
      String label, {
      bool filled = false,
    }) => caps.supportsKey(k)
        ? RemoteButton(
            icon: icon,
            label: label,
            size: filled ? 60 : 48,
            filled: filled,
            haptics: haptics,
            onPressed: () => remote.sendKey(k),
          )
        : null;

    // One play/pause control: a toggle if the TV has one, else the action
    // that matches the current state.
    final playPause = caps.supportsKey(RemoteKey.playPause)
        ? key(
            RemoteKey.playPause,
            playing ? Icons.pause : Icons.play_arrow,
            playing ? 'Pause' : 'Play',
            filled: true,
          )
        : playing
        ? key(RemoteKey.pause, Icons.pause, 'Pause', filled: true)
        : key(RemoteKey.play, Icons.play_arrow, 'Play', filled: true);

    final position = activity.positionAt(DateTime.now());
    return Card(
      margin: const EdgeInsets.fromLTRB(0, 4, 0, 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  playing
                      ? Icons.play_circle_outline
                      : Icons.pause_circle_outline,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    activity.appName ?? 'Now playing',
                    style: theme.textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(switch (activity.state) {
                  PlaybackState.playing => 'Playing',
                  PlaybackState.paused => 'Paused',
                  PlaybackState.buffering => 'Loading…',
                  _ => '',
                }, style: theme.textTheme.labelMedium),
              ],
            ),
            if (activity.hasTimeline && position != null) ...[
              const SizedBox(height: 8),
              Semantics(
                label: 'Playback position',
                value:
                    '${formatDuration(position)} of '
                    '${formatDuration(activity.duration!)}',
                child: LinearProgressIndicator(
                  value:
                      position.inMilliseconds /
                      activity.duration!.inMilliseconds,
                  minHeight: 6,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    formatDuration(position),
                    style: theme.textTheme.bodySmall,
                  ),
                  Text(
                    '-${formatDuration(activity.duration! - position)}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ] else if (activity.isLive) ...[
              const SizedBox(height: 4),
              Text('Live', style: theme.textTheme.labelSmall),
            ],
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ?key(RemoteKey.replay, Icons.replay_10, 'Instant replay'),
                ?key(RemoteKey.rewind, Icons.fast_rewind, 'Rewind'),
                ?playPause,
                ?key(RemoteKey.stop, Icons.stop, 'Stop'),
                ?key(RemoteKey.fastForward, Icons.fast_forward, 'Fast forward'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Suggests the touchpad while a web browser is in front on the TV.
class BrowserHint extends StatelessWidget {
  const BrowserHint({super.key, required this.onOpenTouchpad});

  final VoidCallback onOpenTouchpad;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.fromLTRB(0, 4, 0, 8),
    child: ListTile(
      leading: const Icon(Icons.public),
      title: const Text('Web browser open'),
      subtitle: const Text('The touchpad moves the pointer and scrolls.'),
      trailing: FilledButton.tonal(
        onPressed: () {
          Haptics.play(HapticEvent.press, HapticStrength.light);
          onOpenTouchpad();
        },
        child: const Text('Touchpad'),
      ),
    ),
  );
}
