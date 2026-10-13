import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Persistent cache for app icons fetched from TVs, so they load instantly
/// and are not downloaded on every launch.
///
/// Files live in the app's cache directory (the OS may clear it to free
/// space; icons are then simply fetched again). Each TV's icons share a
/// filename prefix so forgetting a TV removes them.
class AppIconCache {
  AppIconCache(
    this.directory, {
    this.maxAge = const Duration(days: 30),
    this.missingAge = const Duration(days: 1),
    this.maxBytes = 20 * 1024 * 1024,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Directory directory;

  /// After this an icon is re-fetched (and kept if the TV is unreachable).
  final Duration maxAge;

  /// How long to remember that an app has no icon before asking again.
  final Duration missingAge;

  /// Total size cap; the least recently used icons go first.
  final int maxBytes;
  final DateTime Function() _clock;

  static String _hash(String s) =>
      sha256.convert(utf8.encode(s)).toString().substring(0, 24);

  static String _prefix(String deviceId) => _hash(deviceId);

  File _file(String deviceId, String appId, String? iconUrl) => File(
    '${directory.path}/${_prefix(deviceId)}_${_hash('$appId|${iconUrl ?? ''}')}.img',
  );

  /// The cached entry, or null if there is none.
  Future<CachedImage?> read(
    String deviceId,
    String appId,
    String? iconUrl,
  ) async {
    final file = _file(deviceId, appId, iconUrl);
    try {
      if (!await file.exists()) return null;
      final stat = await file.stat();
      final bytes = await file.readAsBytes();
      final age = _clock().difference(stat.modified);
      // Touch on use so the size cap evicts least recently used icons.
      await file.setLastAccessed(_clock());
      return CachedImage(
        bytes: bytes.isEmpty ? null : bytes,
        fresh: age < (bytes.isEmpty ? missingAge : maxAge),
      );
    } on FileSystemException {
      return null;
    }
  }

  /// Stores [bytes], or remembers that the app has no icon when null.
  Future<void> write(
    String deviceId,
    String appId,
    String? iconUrl,
    Uint8List? bytes,
  ) async {
    try {
      await directory.create(recursive: true);
      final file = _file(deviceId, appId, iconUrl);
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsBytes(bytes ?? const [], flush: true);
      await tmp.rename(file.path);
      await file.setLastModified(_clock());
      await file.setLastAccessed(_clock());
    } on FileSystemException {
      // A full or read-only disk only costs a re-download.
    }
  }

  Future<List<File>> _files() async {
    if (!await directory.exists()) return const [];
    return directory
        .list()
        .where((e) => e is File && e.path.endsWith('.img'))
        .cast<File>()
        .toList();
  }

  /// Removes one TV's icons (forgotten TV, or a forced refresh).
  Future<void> clearDevice(String deviceId) async {
    final prefix = '${directory.path}/${_prefix(deviceId)}_';
    for (final f in await _files()) {
      if (f.path.startsWith(prefix)) await f.delete().catchError((_) => f);
    }
  }

  Future<void> clearAll() async {
    for (final f in await _files()) {
      await f.delete().catchError((_) => f);
    }
  }

  Future<int> sizeInBytes() async {
    var total = 0;
    for (final f in await _files()) {
      total += await f.length().catchError((_) => 0);
    }
    return total;
  }

  /// Deletes least recently used icons until under [maxBytes].
  Future<void> prune() async {
    final entries = <(File, DateTime, int)>[];
    var total = 0;
    for (final f in await _files()) {
      try {
        final stat = await f.stat();
        entries.add((f, stat.accessed, stat.size));
        total += stat.size;
      } on FileSystemException {
        continue;
      }
    }
    if (total <= maxBytes) return;
    entries.sort((a, b) => a.$2.compareTo(b.$2));
    for (final (file, _, size) in entries) {
      if (total <= maxBytes) break;
      await file.delete().catchError((_) => file);
      total -= size;
    }
  }
}

class CachedImage {
  const CachedImage({required this.bytes, required this.fresh});

  /// Null when the TV had no icon for the app.
  final Uint8List? bytes;

  /// False when old enough to ask the TV again.
  final bool fresh;
}
