import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/platform/haptics.dart';
import '../keyboard/search_history.dart';
import '../themes/theme_library.dart';
import '../themes/themes_screen.dart';
import 'app_settings.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(appSettingsProvider.notifier);
    void update(AppSettings s) => notifier.save(s);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          ListTile(
            title: const Text('Theme'),
            subtitle: SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(value: ThemeMode.system, label: Text('System')),
                ButtonSegment(value: ThemeMode.light, label: Text('Light')),
                ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
              ],
              selected: {settings.themeMode},
              onSelectionChanged: (s) =>
                  update(settings.copyWith(themeMode: s.first)),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: const Text('Remote theme'),
            subtitle: Text(ref.watch(activeThemeProvider)?.name ?? 'Default'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const ThemesScreen())),
          ),
          SwitchListTile(
            title: const Text('Left-handed layout'),
            value: settings.leftHanded,
            onChanged: (v) => update(settings.copyWith(leftHanded: v)),
          ),
          ListTile(
            title: const Text('Button vibration'),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SegmentedButton<HapticStrength>(
                segments: const [
                  ButtonSegment(value: HapticStrength.off, label: Text('Off')),
                  ButtonSegment(
                    value: HapticStrength.light,
                    label: Text('Light'),
                  ),
                  ButtonSegment(
                    value: HapticStrength.medium,
                    label: Text('Medium'),
                  ),
                  ButtonSegment(
                    value: HapticStrength.strong,
                    label: Text('Strong'),
                  ),
                ],
                selected: {settings.hapticStrength},
                onSelectionChanged: (s) {
                  // Preview the new strength.
                  Haptics.play(HapticEvent.press, s.first);
                  update(settings.copyWith(hapticStrength: s.first));
                },
              ),
            ),
          ),
          SwitchListTile(
            title: const Text('Open keyboard automatically'),
            subtitle: const Text(
              'When the TV reports that a text field is selected. '
              'Not every TV can report this.',
            ),
            value: settings.keyboardAutoOpen,
            onChanged: (v) => update(settings.copyWith(keyboardAutoOpen: v)),
          ),
          ListTile(
            title: const Text('Keyboard batching'),
            subtitle: Text(
              'Waits ${settings.keyboardBatchMs} ms for more keystrokes '
              'before sending',
            ),
          ),
          Slider(
            value: settings.keyboardBatchMs.toDouble(),
            min: AppSettingsNotifier.minBatchMs.toDouble(),
            max: AppSettingsNotifier.maxBatchMs.toDouble(),
            divisions:
                AppSettingsNotifier.maxBatchMs - AppSettingsNotifier.minBatchMs,
            label: '${settings.keyboardBatchMs} ms',
            onChanged: (v) =>
                update(settings.copyWith(keyboardBatchMs: v.round())),
          ),
          SwitchListTile(
            title: const Text('Adapt to what is on the TV'),
            subtitle: const Text(
              'Shows playback controls while something plays and suggests '
              'the touchpad in a web browser, on TVs that report this.',
            ),
            value: settings.adaptiveLayout,
            onChanged: (v) => update(settings.copyWith(adaptiveLayout: v)),
          ),
          SwitchListTile(
            title: const Text('Remember searches'),
            subtitle: const Text(
              'Shows recent keyboard entries as shortcuts. Kept only on this '
              'phone; password fields are never saved. Turning this off '
              'deletes the history.',
            ),
            value: settings.rememberSearches,
            onChanged: (v) => update(settings.copyWith(rememberSearches: v)),
          ),
          if (settings.rememberSearches)
            ListTile(
              leading: const Icon(Icons.history_toggle_off),
              title: const Text('Clear search history'),
              onTap: () async {
                await ref.read(searchHistoryProvider.notifier).clear();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Search history cleared')),
                  );
                }
              },
            ),
          ListTile(
            title: const Text('Touchpad sensitivity'),
            subtitle: Text(
              '${settings.touchpadSensitivity.toStringAsFixed(1)}× '
              '(pointer speed and swipe distance)',
            ),
          ),
          Slider(
            value: settings.touchpadSensitivity,
            min: AppSettingsNotifier.minSensitivity,
            max: AppSettingsNotifier.maxSensitivity,
            divisions: 25,
            label: '${settings.touchpadSensitivity.toStringAsFixed(1)}×',
            onChanged: (v) => update(
              settings.copyWith(
                touchpadSensitivity: (v * 10).roundToDouble() / 10,
              ),
            ),
          ),
          const Divider(),
          const AboutListTile(
            icon: Icon(Icons.info_outline),
            applicationName: 'TV Remote Free',
            applicationLegalese:
                'Free and open source under the Apache License 2.0. No ads, '
                'no tracking, no accounts. Works only on your local network.\n\n'
                'Roku, LG, webOS, Android TV and Google TV are trademarks of their '
                'respective owners. '
                'This app is not affiliated with or endorsed by them.',
          ),
        ],
      ),
    );
  }
}
