import 'package:flutter/material.dart';

import '../../features/themes/theme_definition.dart';

/// Resolved look of the remote controls, carried on [ThemeData] so buttons
/// and the D-pad can style themselves from the active user theme.
@immutable
class RemoteStyle extends ThemeExtension<RemoteStyle> {
  const RemoteStyle({
    required this.button,
    required this.buttonIcon,
    required this.accentButton,
    required this.accentButtonIcon,
    required this.dpadRing,
    required this.ok,
    required this.okText,
    this.buttonShape = ButtonShape.circle,
    this.cornerRadius = 16,
    this.dpadShape = DpadShape.circle,
    this.buttonScale = 1,
    this.background,
  });

  /// Fills gaps in [palette] from [scheme].
  factory RemoteStyle.resolve(
    ColorScheme scheme,
    ThemePalette? palette,
    ThemeDefinition? theme,
  ) => RemoteStyle(
    button: palette?.button ?? scheme.surfaceContainerHighest,
    buttonIcon: palette?.buttonIcon ?? scheme.onSurfaceVariant,
    accentButton: palette?.accentButton ?? scheme.primaryContainer,
    accentButtonIcon: palette?.accentButtonIcon ?? scheme.onPrimaryContainer,
    dpadRing: palette?.dpadRing ?? scheme.surfaceContainer,
    ok: palette?.ok ?? scheme.primary,
    okText: palette?.okText ?? scheme.onPrimary,
    buttonShape: theme?.buttonShape ?? ButtonShape.circle,
    cornerRadius: theme?.cornerRadius ?? 16,
    dpadShape: theme?.dpadShape ?? DpadShape.circle,
    buttonScale: theme?.buttonScale ?? 1,
    background: theme?.background,
  );

  final Color button;
  final Color buttonIcon;
  final Color accentButton;
  final Color accentButtonIcon;
  final Color dpadRing;
  final Color ok;
  final Color okText;
  final ButtonShape buttonShape;
  final double cornerRadius;
  final DpadShape dpadShape;
  final double buttonScale;
  final ThemeBackground? background;

  static RemoteStyle of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<RemoteStyle>() ??
        RemoteStyle.resolve(theme.colorScheme, null, null);
  }

  ShapeBorder buttonBorder() => switch (buttonShape) {
    ButtonShape.circle => const CircleBorder(),
    ButtonShape.rounded => RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(cornerRadius),
    ),
    ButtonShape.square => const RoundedRectangleBorder(),
  };

  @override
  RemoteStyle copyWith() => this;

  @override
  RemoteStyle lerp(RemoteStyle? other, double t) {
    if (other == null) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    final near = t < 0.5 ? this : other;
    return RemoteStyle(
      button: c(button, other.button),
      buttonIcon: c(buttonIcon, other.buttonIcon),
      accentButton: c(accentButton, other.accentButton),
      accentButtonIcon: c(accentButtonIcon, other.accentButtonIcon),
      dpadRing: c(dpadRing, other.dpadRing),
      ok: c(ok, other.ok),
      okText: c(okText, other.okText),
      buttonShape: near.buttonShape,
      cornerRadius: near.cornerRadius,
      dpadShape: near.dpadShape,
      buttonScale: near.buttonScale,
      background: near.background,
    );
  }
}
