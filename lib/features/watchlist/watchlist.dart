import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/content/content_link.dart';

/// Something to watch later, kept only on this phone.
class WatchItem {
  const WatchItem({
    required this.id,
    required this.title,
    required this.url,
    required this.addedAt,
    this.watched = false,
  });

  final String id;
  final String title;
  final String url;
  final DateTime addedAt;
  final bool watched;

  ContentLink? get link => ContentLink.parse(url);
  StreamingService get service => link?.service ?? StreamingService.other;

  WatchItem copyWith({String? title, bool? watched}) => WatchItem(
    id: id,
    title: title ?? this.title,
    url: url,
    addedAt: addedAt,
    watched: watched ?? this.watched,
  );

  Map<String, Object?> toRow() => {
    'id': id,
    'title': title,
    'url': url,
    'added_at': addedAt.millisecondsSinceEpoch,
    'watched': watched ? 1 : 0,
  };

  factory WatchItem.fromRow(Map<String, Object?> row) => WatchItem(
    id: row['id']! as String,
    title: row['title']! as String,
    url: row['url']! as String,
    addedAt: DateTime.fromMillisecondsSinceEpoch(row['added_at']! as int),
    watched: (row['watched'] as int? ?? 0) == 1,
  );
}

const watchlistFormatId = 'tv-remote-free-watchlist';

class Watchlist extends AsyncNotifier<List<WatchItem>> {
  @override
  Future<List<WatchItem>> build() async {
    final rows = await ref.watch(deviceRepositoryProvider).listWatchlist();
    return rows.map(WatchItem.fromRow).toList();
  }

  static String newId() =>
      'w-${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 20)}';

  /// Adds a link from shared or pasted text. Returns null if the text has
  /// no link; an item with the same URL is replaced, not duplicated.
  Future<WatchItem?> addFromText(String text, {String? title}) async {
    final link = ContentLink.parse(text);
    if (link == null) return null;
    final url = link.url.toString();
    final existing = (await future).where((i) => i.url == url).firstOrNull;
    final item = WatchItem(
      id: existing?.id ?? newId(),
      title: (title?.trim().isNotEmpty ?? false)
          ? title!.trim()
          : ContentLink.suggestTitle(text, link),
      url: url,
      addedAt: DateTime.now(),
    );
    await _save(item);
    return item;
  }

  Future<void> setWatched(WatchItem item, bool watched) =>
      _save(item.copyWith(watched: watched));

  Future<void> rename(WatchItem item, String title) =>
      _save(item.copyWith(title: title));

  Future<void> remove(WatchItem item) async {
    await ref.read(deviceRepositoryProvider).deleteWatchItem(item.id);
    ref.invalidateSelf();
    await future;
  }

  Future<void> _save(WatchItem item) async {
    await ref.read(deviceRepositoryProvider).saveWatchItem(item.toRow());
    ref.invalidateSelf();
    await future;
  }

  /// A backup file: titles, links and watched flags only.
  Future<String> export() async => const JsonEncoder.withIndent('  ').convert({
    'format': watchlistFormatId,
    'version': 1,
    'items': [
      for (final i in await future)
        {
          'title': i.title,
          'url': i.url,
          'added': i.addedAt.toUtc().toIso8601String(),
          'watched': i.watched,
        },
    ],
  });

  /// Merges a backup made by [export]. Returns how many items were added or
  /// updated. Throws [FormatException] for anything else.
  Future<int> import(String json) async {
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException {
      throw const FormatException('This is not a watchlist backup.');
    }
    if (decoded is! Map || decoded['format'] != watchlistFormatId) {
      throw const FormatException('This is not a watchlist backup.');
    }
    final items = decoded['items'];
    if (items is! List) return 0;
    final existing = {for (final i in await future) i.url: i};
    var count = 0;
    final repo = ref.read(deviceRepositoryProvider);
    for (final raw in items.take(5000)) {
      if (raw is! Map) continue;
      final link = ContentLink.parse('${raw['url']}');
      final title = raw['title'];
      if (link == null || title is! String || title.trim().isEmpty) continue;
      final url = link.url.toString();
      await repo.saveWatchItem(
        WatchItem(
          id: existing[url]?.id ?? newId(),
          title: title.trim().length > 120
              ? title.trim().substring(0, 120)
              : title.trim(),
          url: url,
          addedAt: DateTime.tryParse('${raw['added']}') ?? DateTime.now(),
          watched: raw['watched'] == true,
        ).toRow(),
      );
      count++;
    }
    ref.invalidateSelf();
    await future;
    return count;
  }
}

final watchlistProvider = AsyncNotifierProvider<Watchlist, List<WatchItem>>(
  Watchlist.new,
);
