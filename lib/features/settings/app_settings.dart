import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';

class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.leftHanded = false,
    this.hapticsEnabled = true,
    this.keyboardAutoOpen = true,
    this.keyboardBatchMs = 40,
  });

  final ThemeMode themeMode;

  /// Mirrors the remote layout so primary controls sit under the left thumb.
  final bool leftHanded;
  final bool hapticsEnabled;

  /// Open the phone keyboard when the TV reports a focused text field.
  final bool keyboardAutoOpen;

  /// Keystroke batching window, 20–75 ms.
  final int keyboardBatchMs;

  AppSettings copyWith({
    ThemeMode? themeMode,
    bool? leftHanded,
    bool? hapticsEnabled,
    bool? keyboardAutoOpen,
    int? keyboardBatchMs,
  }) => AppSettings(
    themeMode: themeMode ?? this.themeMode,
    leftHanded: leftHanded ?? this.leftHanded,
    hapticsEnabled: hapticsEnabled ?? this.hapticsEnabled,
    keyboardAutoOpen: keyboardAutoOpen ?? this.keyboardAutoOpen,
    keyboardBatchMs: keyboardBatchMs ?? this.keyboardBatchMs,
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
      hapticsEnabled: await get('haptics') != 'false',
      keyboardAutoOpen: await get('keyboard_auto_open') != 'false',
      keyboardBatchMs: (batch ?? defaults.keyboardBatchMs).clamp(
        minBatchMs,
        maxBatchMs,
      ),
    );
  }

  Future<void> save(AppSettings settings) async {
    final repo = ref.read(deviceRepositoryProvider);
    state = AsyncData(settings);
    await repo.setSetting('theme_mode', settings.themeMode.name);
    await repo.setSetting('left_handed', '${settings.leftHanded}');
    await repo.setSetting('haptics', '${settings.hapticsEnabled}');
    await repo.setSetting('keyboard_auto_open', '${settings.keyboardAutoOpen}');
    await repo.setSetting('keyboard_batch_ms', '${settings.keyboardBatchMs}');
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
