import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../settings/app_settings.dart';

/// Recently submitted keyboard entries, newest first, kept only on this
/// phone. Never includes password fields. Turning the setting off clears it.
class SearchHistory extends AsyncNotifier<List<String>> {
  static const maxEntries = 20;
  static const maxLength = 200;
  static const _key = 'search_history';

  @override
  Future<List<String>> build() async {
    final enabled = ref.watch(
      settingsProvider.select((s) => s.rememberSearches),
    );
    final repo = ref.watch(deviceRepositoryProvider);
    if (!enabled) {
      await repo.setSetting(_key, '[]');
      return const [];
    }
    try {
      final raw = jsonDecode(await repo.getSetting(_key) ?? '[]');
      return [
        for (final e in raw as List)
          if (e is String) e,
      ];
    } on Object {
      return const [];
    }
  }

  /// Records [text] unless history is off or the text is unsuitable.
  Future<void> record(String text) async {
    if (!ref.read(settingsProvider).rememberSearches) return;
    final entry = text.trim();
    if (entry.isEmpty || entry.length > maxLength) return;
    final current = await future;
    final next = [
      entry,
      for (final e in current)
        if (e.toLowerCase() != entry.toLowerCase()) e,
    ].take(maxEntries).toList();
    await _save(next);
  }

  Future<void> remove(String entry) async => _save([
    for (final e in await future)
      if (e != entry) e,
  ]);

  Future<void> clear() => _save(const []);

  Future<void> _save(List<String> entries) async {
    state = AsyncData(entries);
    await ref
        .read(deviceRepositoryProvider)
        .setSetting(_key, jsonEncode(entries));
  }
}

final searchHistoryProvider =
    AsyncNotifierProvider<SearchHistory, List<String>>(SearchHistory.new);
