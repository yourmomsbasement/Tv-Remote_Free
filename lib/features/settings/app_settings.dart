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

  AppSettings copyWith({
    ThemeMode? themeMode,
    bool? leftHanded,
    HapticStrength? hapticStrength,
    bool? keyboardAutoOpen,
    int? keyboardBatchMs,
    String? themeId,
  }) => AppSettings(
    themeMode: themeMode ?? this.themeMode,
    leftHanded: leftHanded ?? this.leftHanded,
    hapticStrength: hapticStrength ?? this.hapticStrength,
    keyboardAutoOpen: keyboardAutoOpen ?? this.keyboardAutoOpen,
    keyboardBatchMs: keyboardBatchMs ?? this.keyboardBatchMs,
    themeId: themeId ?? this.themeId,
  );
}

/// Global preferences stored in the `app_settings` table.
class AppSettingsNotifier extends AsyncNotifier<AppSettings> {
  static const minBatchMs = 20;
  static const maxBatchMs = 75;

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
