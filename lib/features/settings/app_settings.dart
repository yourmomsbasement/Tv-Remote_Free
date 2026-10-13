import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/platform/haptics.dart';

class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.leftHanded = false,
    this.hapticStrength = HapticStrength.medium,
    this.keyboardAutoOpen = true,
    this.keyboardBatchMs = 40,
    this.themeId = 'builtin.default',
    this.touchpadSensitivity = 1,
    this.rememberSearches = true,
    this.adaptiveLayout = true,
  });

  final ThemeMode themeMode;

  /// Mirrors the remote layout so primary controls sit under the left thumb.
  final bool leftHanded;
  final HapticStrength hapticStrength;

  /// Open the phone keyboard when the TV reports a focused text field.
  final bool keyboardAutoOpen;

  /// Keystroke batching window, 20–75 ms.
  final int keyboardBatchMs;

  /// The selected remote theme (see features/themes).
  final String themeId;

  /// Touchpad speed multiplier, 0.5–3.
  final double touchpadSensitivity;

  /// Keep a local history of submitted (non-password) searches.
  final bool rememberSearches;

  /// Adapt the remote to what the TV is doing (playback controls while
  /// playing, touchpad hint in a browser).
  final bool adaptiveLayout;

  AppSettings copyWith({
    ThemeMode? themeMode,
    bool? leftHanded,
    HapticStrength? hapticStrength,
    bool? keyboardAutoOpen,
    int? keyboardBatchMs,
    String? themeId,
    double? touchpadSensitivity,
    bool? rememberSearches,
    bool? adaptiveLayout,
  }) => AppSettings(
    themeMode: themeMode ?? this.themeMode,
    leftHanded: leftHanded ?? this.leftHanded,
    hapticStrength: hapticStrength ?? this.hapticStrength,
    keyboardAutoOpen: keyboardAutoOpen ?? this.keyboardAutoOpen,
    keyboardBatchMs: keyboardBatchMs ?? this.keyboardBatchMs,
    themeId: themeId ?? this.themeId,
    touchpadSensitivity: touchpadSensitivity ?? this.touchpadSensitivity,
    rememberSearches: rememberSearches ?? this.rememberSearches,
    adaptiveLayout: adaptiveLayout ?? this.adaptiveLayout,
  );
}

/// Global preferences stored in the `app_settings` table.
class AppSettingsNotifier extends AsyncNotifier<AppSettings> {
  static const minBatchMs = 20;
  static const maxBatchMs = 75;
  static const minSensitivity = 0.5;
  static const maxSensitivity = 3.0;

  @override
  Future<AppSettings> build() async {
    final repo = ref.watch(deviceRepositoryProvider);
    Future<String?> get(String key) => repo.getSetting(key);
    const defaults = AppSettings();
    final theme = await get('theme_mode');
    final batch = int.tryParse(await get('keyboard_batch_ms') ?? '');
    return AppSettings(
      themeMode: ThemeMode.values.asNameMap()[theme] ?? defaults.themeMode,
      leftHanded: await get('left_handed') == 'true',
      hapticStrength: _strength(
        await get('haptic_strength'),
        legacyEnabled: await get('haptics'),
      ),
      keyboardAutoOpen: await get('keyboard_auto_open') != 'false',
      keyboardBatchMs: (batch ?? defaults.keyboardBatchMs).clamp(
        minBatchMs,
        maxBatchMs,
      ),
      themeId: await get('theme_id') ?? defaults.themeId,
      touchpadSensitivity:
          (double.tryParse(await get('touchpad_sensitivity') ?? '') ?? 1).clamp(
            minSensitivity,
            maxSensitivity,
          ),
      rememberSearches: await get('remember_searches') != 'false',
      adaptiveLayout: await get('adaptive_layout') != 'false',
    );
  }

  /// Older builds stored an on/off switch under `haptics`.
  static HapticStrength _strength(String? stored, {String? legacyEnabled}) =>
      HapticStrength.values.asNameMap()[stored] ??
      (legacyEnabled == 'false' ? HapticStrength.off : HapticStrength.medium);

  Future<void> save(AppSettings settings) async {
    final repo = ref.read(deviceRepositoryProvider);
    state = AsyncData(settings);
    await repo.setSetting('theme_mode', settings.themeMode.name);
    await repo.setSetting('left_handed', '${settings.leftHanded}');
    await repo.setSetting('haptic_strength', settings.hapticStrength.name);
    await repo.setSetting('keyboard_auto_open', '${settings.keyboardAutoOpen}');
    await repo.setSetting('keyboard_batch_ms', '${settings.keyboardBatchMs}');
    await repo.setSetting('theme_id', settings.themeId);
    await repo.setSetting(
      'touchpad_sensitivity',
      '${settings.touchpadSensitivity}',
    );
    await repo.setSetting('remember_searches', '${settings.rememberSearches}');
    await repo.setSetting('adaptive_layout', '${settings.adaptiveLayout}');
  }
}

final appSettingsProvider =
    AsyncNotifierProvider<AppSettingsNotifier, AppSettings>(
      AppSettingsNotifier.new,
    );

/// Settings with defaults while loading.
final settingsProvider = Provider<AppSettings>(
  (ref) => ref.watch(appSettingsProvider).value ?? const AppSettings(),
);
