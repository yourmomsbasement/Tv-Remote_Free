import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/capabilities/remote_key.dart';
import '../../ui/components/dpad.dart';
import '../../ui/components/remote_button.dart';
import '../settings/app_settings.dart';
import 'remote_session.dart';

/// The main button layout. Buttons the TV does not support are hidden.
class RemotePanel extends ConsumerWidget {
  const RemotePanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(remoteSessionProvider);
    final settings = ref.watch(settingsProvider);
    final remote = ref.read(remoteSessionProvider.notifier);
    final caps = session.capabilities;
    final connected = session.isConnected;

    Widget? key(
      RemoteKey key,
      IconData icon,
      String label, {
      bool repeat = false,
      bool filled = false,
    }) {
      if (!caps.supportsKey(key)) return null;
      return RemoteButton(
        icon: icon,
        label: label,
        repeat: repeat,
        filled: filled,
        haptics: settings.hapticStrength,
        onPressed: connected ? () => remote.sendKey(key) : null,
      );
    }

    Widget row(List<Widget?> children) {
      final visible = children.whereType<Widget>().toList();
      if (visible.isEmpty) return const SizedBox.shrink();
      final ordered = settings.leftHanded ? visible.reversed.toList() : visible;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: ordered,
        ),
      );
    }

    // Power: prefer a toggle, else separate on/off as supported.
    final powerButtons = <Widget?>[
      if (caps.supportsKey(RemoteKey.power))
        key(RemoteKey.power, Icons.power_settings_new, 'Power', filled: true)
      else ...[
        if (caps.powerOff)
          key(
            RemoteKey.powerOff,
            Icons.power_settings_new,
            'Turn off',
            filled: true,
          ),
      ],
      if (session.canPowerOn && !caps.supportsKey(RemoteKey.power))
        RemoteButton(
          icon: Icons.power,
          label: 'Turn on',
          haptics: settings.hapticStrength,
          onPressed: remote.powerOn,
        ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final dpadSize = (constraints.maxWidth * 0.68).clamp(200.0, 300.0);
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            children: [
              row([
                ...powerButtons,
                key(RemoteKey.input, Icons.input, 'Input'),
                key(RemoteKey.search, Icons.search, 'Search'),
                key(RemoteKey.info, Icons.info_outline, 'Info'),
              ]),
              row([
                key(RemoteKey.back, Icons.arrow_back, 'Back'),
                key(RemoteKey.home, Icons.home_outlined, 'Home'),
                key(RemoteKey.menu, Icons.menu, 'Menu'),
              ]),
              const SizedBox(height: 8),
              if (caps.navigation)
                DPad(
                  size: dpadSize,
                  enabled: connected,
                  haptics: settings.hapticStrength,
                  onKey: remote.sendKey,
                ),
              const SizedBox(height: 8),
              row([
                key(RemoteKey.replay, Icons.replay, 'Instant replay'),
                key(RemoteKey.rewind, Icons.fast_rewind, 'Rewind'),
                key(RemoteKey.playPause, Icons.play_arrow, 'Play / Pause'),
                key(RemoteKey.play, Icons.play_arrow, 'Play'),
                key(RemoteKey.pause, Icons.pause, 'Pause'),
                key(RemoteKey.stop, Icons.stop, 'Stop'),
                key(RemoteKey.fastForward, Icons.fast_forward, 'Fast forward'),
              ]),
              row([
                key(
                  RemoteKey.volumeDown,
                  Icons.volume_down,
                  'Volume down',
                  repeat: true,
                ),
                key(
                  RemoteKey.mute,
                  session.muted == true ? Icons.volume_off : Icons.volume_mute,
                  'Mute',
                ),
                key(
                  RemoteKey.volumeUp,
                  Icons.volume_up,
                  'Volume up',
                  repeat: true,
                ),
              ]),
              if (caps.volumeSet && session.volume != null)
                Semantics(
                  label: 'Volume',
                  child: Slider(
                    value: session.volume!
                        .clamp(0, session.volumeLimit ?? 100)
                        .toDouble(),
                    max: (session.volumeLimit ?? 100).toDouble(),
                    divisions: session.volumeLimit ?? 100,
                    label: '${session.volume}',
                    onChanged: connected
                        ? (v) => remote.setVolume(v.round())
                        : null,
                  ),
                ),
              row([
                key(
                  RemoteKey.channelDown,
                  Icons.keyboard_double_arrow_down,
                  'Channel down',
                  repeat: true,
                ),
                key(
                  RemoteKey.channelUp,
                  Icons.keyboard_double_arrow_up,
                  'Channel up',
                  repeat: true,
                ),
              ]),
            ],
          ),
        );
      },
    );
  }
}
