import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_remote_free/features/themes/theme_definition.dart';
import 'package:tv_remote_free/ui/themes/app_theme.dart';
import 'package:tv_remote_free/ui/themes/remote_style.dart';

String themeJson(Map<String, Object?> fields) => jsonEncode({
  'format': 'tv-remote-free-theme',
  'version': 1,
  'name': 'Test',
  ...fields,
});

Matcher throwsThemeError(String fragment) => throwsA(
  isA<ThemeFormatException>().having(
    (e) => e.message,
    'message',
    contains(fragment),
  ),
);

void main() {
  test('the smallest theme is a name and a seed', () {
    final t = ThemeDefinition.parse(
      themeJson({
        'name': 'Forest Green!',
        'colors': {'seed': '#2E7D32'},
      }),
    );
    expect(t.id, 'user.forest-green');
    expect(t.supportsLight && t.supportsDark, isTrue);
    expect(t.paletteFor(Brightness.dark)!.seed, const Color(0xFF2E7D32));
    expect(t.buttonShape, ButtonShape.circle);
    expect(t.buttonScale, 1);
  });

  test('per-mode palettes override shared colours key by key', () {
    final t = ThemeDefinition.parse(
      themeJson({
        'colors': {'seed': '#111', 'ok': '#222222'},
        'dark': {'ok': '#80FF0000'},
      }),
    );
    final dark = t.paletteFor(Brightness.dark)!;
    final light = t.paletteFor(Brightness.light)!;
    expect(dark.seed, const Color(0xFF111111));
    expect(dark.ok, const Color(0x80FF0000));
    expect(light.ok, const Color(0xFF222222));
  });

  test('a single-mode theme supports only that mode', () {
    final t = ThemeDefinition.parse(
      themeJson({
        'modes': ['dark'],
        'colors': {'seed': '#000000'},
      }),
    );
    expect(t.supportsDark, isTrue);
    expect(t.supportsLight, isFalse);
  });

  test('shapes, scale and ranges are validated and clamped', () {
    final t = ThemeDefinition.parse(
      themeJson({
        'shape': {'button': 'rounded', 'cornerRadius': 999, 'dpad': 'rounded'},
        'buttonScale': 5,
      }),
    );
    expect(t.buttonShape, ButtonShape.rounded);
    expect(t.cornerRadius, 40);
    expect(t.dpadShape, DpadShape.rounded);
    expect(t.buttonScale, 1.3);
  });

  test(
    'text fields are trimmed, stripped of control characters and capped',
    () {
      final t = ThemeDefinition.parse(
        themeJson({
          'name': '  Evil\u0000\nName ${'x' * 100}',
          'author': 'A\tB',
        }),
      );
      expect(t.name.contains('\n'), isFalse);
      expect(t.name.runes.length, 40);
      expect(t.author, 'A B');
    },
  );

  test('rejects files that are not themes or are malformed', () {
    expect(() => ThemeDefinition.parse('not json'), throwsThemeError('JSON'));
    expect(() => ThemeDefinition.parse('[]'), throwsThemeError('not a valid'));
    expect(
      () => ThemeDefinition.parse(jsonEncode({'name': 'x'})),
      throwsThemeError('format'),
    );
    expect(
      () => ThemeDefinition.parse(themeJson({'version': 2})),
      throwsThemeError('newer version'),
    );
    expect(
      () => ThemeDefinition.parse(themeJson({'name': '  '})),
      throwsThemeError('name'),
    );
    expect(
      () => ThemeDefinition.parse(
        themeJson({
          'colors': {'ok': 'red'},
        }),
      ),
      throwsThemeError('colors.ok'),
    );
    expect(
      () => ThemeDefinition.parse(
        themeJson({
          'shape': {'button': 'hexagon'},
        }),
      ),
      throwsThemeError('shape.button'),
    );
    expect(
      () => ThemeDefinition.parse(themeJson({'buttonScale': 'big'})),
      throwsThemeError('buttonScale'),
    );
    expect(
      () => ThemeDefinition.parse(
        themeJson({
          'modes': ['sepia'],
        }),
      ),
      throwsThemeError('modes'),
    );
  });

  test('imported themes cannot claim built-in ids', () {
    expect(
      () => ThemeDefinition.parse(themeJson({'id': 'builtin.default'})),
      throwsThemeError('reserved'),
    );
  });

  test('background images must be real, small images', () {
    String uri(List<int> bytes, [String type = 'png']) =>
        'data:image/$type;base64,${base64Encode(bytes)}';
    final png = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
    final ok = ThemeDefinition.parse(
      themeJson({
        'background': {'image': uri(png), 'fit': 'contain', 'opacity': 2},
      }),
    );
    expect(ok.background!.bytes, png);
    expect(ok.background!.fit, BoxFit.contain);
    expect(ok.background!.opacity, 1);

    expect(
      () => ThemeDefinition.parse(
        themeJson({
          'background': {'image': uri(utf8.encode('<svg/>'))},
        }),
      ),
      throwsThemeError('not a PNG'),
    );
    expect(
      () => ThemeDefinition.parse(
        themeJson({
          'background': {'image': 'https://example.com/x.png'},
        }),
      ),
      throwsThemeError('data URI'),
    );
    expect(
      () => ThemeDefinition.parse(
        themeJson({
          'background': {
            'image': uri([...png, ...List.filled(maxBackgroundImageBytes, 0)]),
          },
        }),
      ),
      throwsThemeError('too large'),
    );
  });

  test('flags hard-to-read colour pairs', () {
    final t = ThemeDefinition.parse(
      themeJson({
        'colors': {
          'button': '#777777',
          'buttonIcon': '#888888',
          'ok': '#000000',
          'okText': '#FFFFFF',
        },
      }),
    );
    final warnings = t.contrastWarnings();
    expect(warnings, hasLength(2)); // light and dark button icons
    expect(warnings.first, contains('button icons'));
  });

  test('every bundled and example theme parses cleanly', () {
    final files = [
      ...Directory('assets/themes').listSync(),
      ...Directory('docs/example-themes').listSync(),
    ].whereType<File>().where((f) => f.path.endsWith('.json')).toList();
    expect(files.length, greaterThanOrEqualTo(5));
    for (final file in files) {
      final builtIn = file.path.startsWith('assets/');
      final theme = ThemeDefinition.parse(
        file.readAsStringSync(),
        builtIn: builtIn,
      );
      expect(theme.contrastWarnings(), isEmpty, reason: file.path);
      if (builtIn) expect(theme.id, startsWith('builtin.'), reason: file.path);
    }
  });

  test('the theme flows into ThemeData and RemoteStyle', () {
    final t = ThemeDefinition.parse(
      themeJson({
        'colors': {
          'background': '#101010',
          'button': '#202020',
          'ok': '#FF0000',
        },
        'shape': {'button': 'square'},
        'buttonScale': 1.2,
      }),
    );
    final data = AppTheme.build(Brightness.dark, t);
    final style = data.extension<RemoteStyle>()!;
    expect(data.scaffoldBackgroundColor, const Color(0xFF101010));
    expect(style.button, const Color(0xFF202020));
    expect(style.ok, const Color(0xFFFF0000));
    expect(style.buttonScale, 1.2);
    expect(style.buttonBorder(), isA<RoundedRectangleBorder>());
    // Unset colours fall back to the generated scheme.
    expect(style.okText, data.colorScheme.onPrimary);
  });
}
