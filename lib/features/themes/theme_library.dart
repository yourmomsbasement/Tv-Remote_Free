import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../settings/app_settings.dart';
import 'theme_definition.dart';

const defaultThemeId = 'builtin.default';

/// Theme files bundled with the app (assets/themes/).
const builtInThemeAssets = [
  'assets/themes/sunset.json',
  'assets/themes/midnight.json',
  'assets/themes/retro.json',
  'assets/themes/high_contrast.json',
];

/// The app's standard look, expressed as a theme so it can be exported as a
/// starting template.
const _defaultThemeJson = '''
{
  "format": "tv-remote-free-theme",
  "version": 1,
  "id": "builtin.default",
  "name": "Default",
  "author": "OpenRemote",
  "description": "The standard look. Follows the system light/dark setting.",
  "colors": { "seed": "#3D5AFE" }
}''';

/// Built-in themes followed by the user's imported themes.
class ThemeLibrary extends AsyncNotifier<List<ThemeDefinition>> {
  @override
  Future<List<ThemeDefinition>> build() async {
    final themes = [ThemeDefinition.parse(_defaultThemeJson, builtIn: true)];
    for (final asset in builtInThemeAssets) {
      try {
        themes.add(
          ThemeDefinition.parse(
            await rootBundle.loadString(asset, cache: false),
            builtIn: true,
          ),
        );
      } on Object catch (e) {
        debugPrint('Skipping built-in theme $asset: $e');
      }
    }
    final stored = await ref.watch(deviceRepositoryProvider).listThemes();
    for (final (_, json) in stored) {
      try {
        themes.add(ThemeDefinition.parse(json));
      } on ThemeFormatException {
        // A theme saved by a newer app version; ignore rather than crash.
      }
    }
    return themes;
  }

  /// Installs (or updates, by id) an imported theme.
  Future<void> install(ThemeDefinition theme) async {
    if (theme.builtIn) return;
    await ref.read(deviceRepositoryProvider).saveTheme(theme.id, theme.source);
    ref.invalidateSelf();
    await future;
  }

  Future<void> remove(ThemeDefinition theme) async {
    if (theme.builtIn) return;
    final settings = ref.read(appSettingsProvider.notifier);
    if (ref.read(settingsProvider).themeId == theme.id) {
      await settings.save(
        ref.read(settingsProvider).copyWith(themeId: defaultThemeId),
      );
    }
    await ref.read(deviceRepositoryProvider).deleteTheme(theme.id);
    ref.invalidateSelf();
    await future;
  }
}

final themeLibraryProvider =
    AsyncNotifierProvider<ThemeLibrary, List<ThemeDefinition>>(
      ThemeLibrary.new,
    );

/// The theme to apply, or null for the default.
final activeThemeProvider = Provider<ThemeDefinition?>((ref) {
  final id = ref.watch(settingsProvider.select((s) => s.themeId));
  final themes = ref.watch(themeLibraryProvider).value ?? const [];
  return themes.where((t) => t.id == id).firstOrNull;
});

/// A theme that only defines one brightness overrides the system setting.
ThemeMode effectiveThemeMode(ThemeMode chosen, ThemeDefinition? theme) {
  if (theme == null) return chosen;
  if (theme.supportsLight && !theme.supportsDark) return ThemeMode.light;
  if (theme.supportsDark && !theme.supportsLight) return ThemeMode.dark;
  return chosen;
}
