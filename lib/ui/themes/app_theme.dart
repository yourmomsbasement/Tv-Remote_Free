import 'package:flutter/material.dart';

import '../../features/themes/theme_definition.dart';
import 'remote_style.dart';

abstract final class AppTheme {
  static const defaultSeed = Color(0xFF3D5AFE);

  static ThemeData light([ThemeDefinition? theme]) =>
      build(Brightness.light, theme);
  static ThemeData dark([ThemeDefinition? theme]) =>
      build(Brightness.dark, theme);

  /// Material theme for [brightness], customised by a user [theme].
  static ThemeData build(Brightness brightness, [ThemeDefinition? theme]) {
    final palette = theme?.paletteFor(brightness);
    var scheme = ColorScheme.fromSeed(
      seedColor: palette?.seed ?? defaultSeed,
      brightness: brightness,
    );
    if (palette?.surface case final surface?) {
      scheme = scheme.copyWith(
        surface: surface,
        surfaceContainer: surface,
        onSurface: _readableOn(surface),
      );
    }
    final background = palette?.background ?? scheme.surface;
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      scaffoldBackgroundColor: background,
      appBarTheme: AppBarTheme(
        backgroundColor: palette?.surface ?? background,
        foregroundColor: _readableOn(palette?.surface ?? background),
      ),
      visualDensity: VisualDensity.standard,
      // Generous tap targets for one-handed use and accessibility.
      materialTapTargetSize: MaterialTapTargetSize.padded,
      extensions: [RemoteStyle.resolve(scheme, palette, theme)],
    );
  }

  /// Black or white, whichever is more readable on [background].
  static Color _readableOn(Color background) =>
      ThemeDefinition.contrastRatio(Colors.white, background) >=
          ThemeDefinition.contrastRatio(Colors.black, background)
      ? Colors.white
      : Colors.black;
}
