import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Identifies a theme file. See docs/THEMES.md for the full format.
const themeFormatId = 'tv-remote-free-theme';
const themeFormatVersion = 1;

/// Theme files larger than this are rejected before parsing.
const maxThemeFileBytes = 3 * 1024 * 1024;

/// Embedded background images larger than this are rejected.
const maxBackgroundImageBytes = 2 * 1024 * 1024;

enum ButtonShape { circle, rounded, square }

enum DpadShape { circle, rounded }

class ThemeFormatException implements Exception {
  const ThemeFormatException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Colours for one brightness. Any colour left out falls back to a value
/// derived from [seed] (or the app default), so a theme can be as small as
/// a single seed colour.
class ThemePalette {
  const ThemePalette({
    this.seed,
    this.background,
    this.surface,
    this.button,
    this.buttonIcon,
    this.accentButton,
    this.accentButtonIcon,
    this.dpadRing,
    this.ok,
    this.okText,
  });

  final Color? seed;

  /// Screen background behind the remote.
  final Color? background;

  /// Cards, sheets and the app bar.
  final Color? surface;
  final Color? button;
  final Color? buttonIcon;

  /// Highlighted buttons such as Power.
  final Color? accentButton;
  final Color? accentButtonIcon;
  final Color? dpadRing;
  final Color? ok;
  final Color? okText;

  static const keys = [
    'seed',
    'background',
    'surface',
    'button',
    'buttonIcon',
    'accentButton',
    'accentButtonIcon',
    'dpadRing',
    'ok',
    'okText',
  ];

  Color? operator [](String key) => switch (key) {
    'seed' => seed,
    'background' => background,
    'surface' => surface,
    'button' => button,
    'buttonIcon' => buttonIcon,
    'accentButton' => accentButton,
    'accentButtonIcon' => accentButtonIcon,
    'dpadRing' => dpadRing,
    'ok' => ok,
    'okText' => okText,
    _ => null,
  };

  static ThemePalette fromMap(Map<String, Color> c) => ThemePalette(
    seed: c['seed'],
    background: c['background'],
    surface: c['surface'],
    button: c['button'],
    buttonIcon: c['buttonIcon'],
    accentButton: c['accentButton'],
    accentButtonIcon: c['accentButtonIcon'],
    dpadRing: c['dpadRing'],
    ok: c['ok'],
    okText: c['okText'],
  );

  /// [override] wins key by key.
  ThemePalette merge(ThemePalette? override) {
    if (override == null) return this;
    return ThemePalette.fromMap({
      for (final key in keys)
        if ((override[key] ?? this[key]) case final Color c) key: c,
    });
  }
}

class ThemeBackground {
  const ThemeBackground({
    required this.bytes,
    this.fit = BoxFit.cover,
    this.opacity = 1,
  });

  final Uint8List bytes;
  final BoxFit fit;

  /// 0–1; lower values fade the image into the background colour.
  final double opacity;
}

/// A parsed, validated theme.
class ThemeDefinition {
  const ThemeDefinition({
    required this.id,
    required this.name,
    this.author,
    this.description,
    this.light,
    this.dark,
    this.buttonShape = ButtonShape.circle,
    this.cornerRadius = 16,
    this.dpadShape = DpadShape.circle,
    this.buttonScale = 1,
    this.background,
    this.builtIn = false,
    required this.source,
  });

  final String id;
  final String name;
  final String? author;
  final String? description;

  /// Palettes per brightness. A theme that provides only one forces that
  /// brightness; one that provides neither uses the app defaults.
  final ThemePalette? light;
  final ThemePalette? dark;
  final ButtonShape buttonShape;

  /// Corner radius for [ButtonShape.rounded] buttons and a rounded D-pad.
  final double cornerRadius;
  final DpadShape dpadShape;

  /// Multiplies remote button sizes (0.8–1.3).
  final double buttonScale;
  final ThemeBackground? background;
  final bool builtIn;

  /// The JSON this theme was parsed from, for export.
  final String source;

  bool get supportsLight => light != null || dark == null;
  bool get supportsDark => dark != null || light == null;

  ThemePalette? paletteFor(Brightness brightness) =>
      brightness == Brightness.dark ? (dark ?? light) : (light ?? dark);

  /// Parses and validates a theme file. Throws [ThemeFormatException] with
  /// a message suitable for showing to the user.
  static ThemeDefinition parse(String text, {bool builtIn = false}) {
    if (utf8.encode(text).length > maxThemeFileBytes) {
      throw const ThemeFormatException(
        'The theme file is too large (max 3 MB).',
      );
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      throw const ThemeFormatException(
        'This is not a valid theme file (bad JSON).',
      );
    }
    if (decoded is! Map<String, Object?>) {
      throw const ThemeFormatException('This is not a valid theme file.');
    }
    final json = decoded;
    if (json['format'] != themeFormatId) {
      throw const ThemeFormatException(
        'This is not a TV Remote Free theme ("format" is missing or wrong).',
      );
    }
    final version = json['version'];
    if (version is! int || version < 1) {
      throw const ThemeFormatException('The theme has no valid "version".');
    }
    if (version > themeFormatVersion) {
      throw const ThemeFormatException(
        'This theme needs a newer version of the app.',
      );
    }

    final name = _string(json['name'], maxLength: 40);
    if (name == null) {
      throw const ThemeFormatException('The theme needs a "name".');
    }
    final rawId = _string(json['id'], maxLength: 64);
    final id = rawId != null && RegExp(r'^[a-z0-9._-]+$').hasMatch(rawId)
        ? rawId
        : _slug(name);
    if (id.startsWith('builtin.') && !builtIn) {
      throw const ThemeFormatException(
        'Theme ids starting with "builtin." '
        'are reserved.',
      );
    }

    final base = _palette(json['colors'], 'colors');
    final light = _palette(json['light'], 'light');
    final dark = _palette(json['dark'], 'dark');
    final modes = json['modes'];
    var wantsLight = true;
    var wantsDark = true;
    if (modes != null) {
      if (modes is! List || modes.isEmpty) {
        throw const ThemeFormatException(
          '"modes" must be a list containing "light" and/or "dark".',
        );
      }
      wantsLight = modes.contains('light');
      wantsDark = modes.contains('dark');
      if (!wantsLight && !wantsDark) {
        throw const ThemeFormatException(
          '"modes" must contain "light" and/or "dark".',
        );
      }
    }
    ThemePalette? resolve(ThemePalette? specific, bool wanted) {
      if (!wanted) return null;
      if (base == null) return specific;
      return base.merge(specific);
    }

    final shape = _object(json['shape'], 'shape');
    return ThemeDefinition(
      id: id,
      name: name,
      author: _string(json['author'], maxLength: 60),
      description: _string(json['description'], maxLength: 200),
      light:
          resolve(light, wantsLight) ??
          (wantsLight && !wantsDark ? const ThemePalette() : null),
      dark:
          resolve(dark, wantsDark) ??
          (wantsDark && !wantsLight ? const ThemePalette() : null),
      buttonShape:
          _enum(shape?['button'], ButtonShape.values, 'shape.button') ??
          ButtonShape.circle,
      cornerRadius:
          _number(shape?['cornerRadius'], 0, 40, 'shape.cornerRadius') ?? 16,
      dpadShape:
          _enum(shape?['dpad'], DpadShape.values, 'shape.dpad') ??
          DpadShape.circle,
      buttonScale: _number(json['buttonScale'], 0.8, 1.3, 'buttonScale') ?? 1,
      background: _background(json['background']),
      builtIn: builtIn,
      source: text,
    );
  }

  /// Readability problems worth showing before the user applies a theme.
  List<String> contrastWarnings() {
    final warnings = <String>[];
    for (final (label, palette) in [('Light', light), ('Dark', dark)]) {
      if (palette == null) continue;
      for (final (what, fg, bg) in [
        ('button icons', palette.buttonIcon, palette.button),
        ('highlighted buttons', palette.accentButtonIcon, palette.accentButton),
        ('the OK button', palette.okText, palette.ok),
      ]) {
        if (fg == null || bg == null) continue;
        final ratio = contrastRatio(fg, bg);
        if (ratio < 3) {
          warnings.add(
            '$label: $what may be hard to see '
            '(contrast ${ratio.toStringAsFixed(1)}:1, aim for 3:1 or more).',
          );
        }
      }
    }
    return warnings;
  }

  static double contrastRatio(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
  }

  static String _slug(String name) {
    final slug = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return 'user.${slug.isEmpty ? 'theme' : slug}';
  }

  /// Trimmed, control characters removed, length-capped; null if empty.
  static String? _string(Object? value, {required int maxLength}) {
    if (value is! String) return null;
    var s = value.replaceAll(RegExp(r'[\u0000-\u001F\u007F]'), ' ').trim();
    if (s.isEmpty) return null;
    if (s.runes.length > maxLength) {
      s = String.fromCharCodes(s.runes.take(maxLength));
    }
    return s;
  }

  static Map<String, Object?>? _object(Object? value, String field) {
    if (value == null) return null;
    if (value is! Map<String, Object?>) {
      throw ThemeFormatException('"$field" must be an object.');
    }
    return value;
  }

  static ThemePalette? _palette(Object? value, String field) {
    final map = _object(value, field);
    if (map == null) return null;
    final colors = <String, Color>{};
    for (final key in ThemePalette.keys) {
      final raw = map[key];
      if (raw == null) continue;
      colors[key] = parseColor(raw, '$field.$key');
    }
    return ThemePalette.fromMap(colors);
  }

  /// Accepts "#RGB", "#RRGGBB" and "#AARRGGBB".
  static Color parseColor(Object? raw, String field) {
    if (raw is String) {
      var hex = raw.trim();
      if (hex.startsWith('#')) hex = hex.substring(1);
      if (RegExp(r'^[0-9a-fA-F]{3}$').hasMatch(hex)) {
        hex = hex.split('').map((c) => '$c$c').join();
      }
      if (RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(hex)) hex = 'FF$hex';
      if (RegExp(r'^[0-9a-fA-F]{8}$').hasMatch(hex)) {
        return Color(int.parse(hex, radix: 16));
      }
    }
    throw ThemeFormatException(
      '"$field" must be a colour like "#1E88E5" (got ${jsonEncode(raw)}).',
    );
  }

  static T? _enum<T extends Enum>(Object? raw, List<T> values, String field) {
    if (raw == null) return null;
    final match = values.where((v) => v.name == raw).firstOrNull;
    if (match == null) {
      throw ThemeFormatException(
        '"$field" must be one of '
        '${values.map((v) => '"${v.name}"').join(', ')}.',
      );
    }
    return match;
  }

  static double? _number(Object? raw, double min, double max, String field) {
    if (raw == null) return null;
    if (raw is! num || !raw.isFinite) {
      throw ThemeFormatException('"$field" must be a number.');
    }
    return raw.toDouble().clamp(min, max);
  }

  static ThemeBackground? _background(Object? value) {
    final map = _object(value, 'background');
    if (map == null) return null;
    final image = map['image'];
    if (image is! String) {
      throw const ThemeFormatException(
        '"background.image" must be a data URI (data:image/png;base64,...).',
      );
    }
    final match = RegExp(
      r'^data:image/(png|jpeg|jpg|webp);base64,(.+)$',
      dotAll: true,
    ).firstMatch(image.trim());
    if (match == null) {
      throw const ThemeFormatException(
        '"background.image" must be a PNG, JPEG or WebP data URI.',
      );
    }
    final Uint8List bytes;
    try {
      bytes = base64Decode(match.group(2)!.replaceAll(RegExp(r'\s'), ''));
    } on FormatException {
      throw const ThemeFormatException(
        '"background.image" is not valid base64.',
      );
    }
    if (bytes.length > maxBackgroundImageBytes) {
      throw const ThemeFormatException(
        'The background image is too large (max 2 MB).',
      );
    }
    if (!_looksLikeImage(bytes)) {
      throw const ThemeFormatException(
        '"background.image" is not a PNG, JPEG or WebP image.',
      );
    }
    return ThemeBackground(
      bytes: bytes,
      fit: switch (map['fit']) {
        null || 'cover' => BoxFit.cover,
        'contain' => BoxFit.contain,
        'fill' => BoxFit.fill,
        _ => throw const ThemeFormatException(
          '"background.fit" must be "cover", "contain" or "fill".',
        ),
      },
      opacity: _number(map['opacity'], 0, 1, 'background.opacity') ?? 1,
    );
  }

  /// Checks magic bytes so non-image data is never handed to the decoder.
  static bool _looksLikeImage(Uint8List b) {
    bool starts(List<int> sig, [int offset = 0]) =>
        b.length >= offset + sig.length &&
        Iterable<int>.generate(sig.length)
            .every((i) => b[offset + i] == sig[i]);
    return starts([0x89, 0x50, 0x4E, 0x47]) || // PNG
        starts([0xFF, 0xD8, 0xFF]) || // JPEG
        (starts('RIFF'.codeUnits) && starts('WEBP'.codeUnits, 8)); // WebP
  }
}
