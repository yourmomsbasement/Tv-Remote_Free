import 'package:flutter/material.dart';

abstract final class AppTheme {
  static const _seed = Color(0xFF3D5AFE);

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: brightness,
    );
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      visualDensity: VisualDensity.standard,
      // Generous tap targets for one-handed use and accessibility.
      materialTapTargetSize: MaterialTapTargetSize.padded,
    );
  }
}
