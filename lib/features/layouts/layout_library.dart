import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/capabilities/remote_key.dart';
import 'remote_layout.dart';

LayoutItem _k(String id, RemoteKey key, {int w = 1, int h = 1, String? icon}) =>
    LayoutItem(id: id, action: KeyAction(key), width: w, height: h, icon: icon);

/// Music: big transport controls and what's playing. Track names, artwork,
/// shuffle and queues aren't available from these TVs' remote protocols.
final musicLayout = RemoteLayout(
  id: 'builtin.music',
  name: 'Music',
  builtIn: true,
  items: [
    const LayoutItem(id: 'np', action: NowPlayingAction(), width: 4),
    _k('prev', RemoteKey.previousTrack),
    _k('rew', RemoteKey.rewind),
    _k('ff', RemoteKey.fastForward),
    _k('next', RemoteKey.nextTrack),
    _k('pp', RemoteKey.playPause, w: 4, h: 2),
    _k('vd', RemoteKey.volumeDown),
    _k('mute', RemoteKey.mute, w: 2),
    _k('vu', RemoteKey.volumeUp),
    _k('back', RemoteKey.back, w: 2),
    _k('home', RemoteKey.home, w: 2),
  ],
);

/// Minimal: the handful of buttons most people use.
final minimalLayout = RemoteLayout(
  id: 'builtin.minimal',
  name: 'Minimal',
  builtIn: true,
  items: [
    _k('back', RemoteKey.back, w: 2),
    _k('home', RemoteKey.home, w: 2),
    const LayoutItem(id: 'dpad', action: DpadAction(), width: 4, height: 3),
    _k('vd', RemoteKey.volumeDown),
    _k('pp', RemoteKey.playPause, w: 2),
    _k('vu', RemoteKey.volumeUp),
  ],
);

/// Built-in and user layouts; the standard remote is represented by
/// [RemoteLayout.standardId] and has no grid.
class LayoutLibrary extends AsyncNotifier<List<RemoteLayout>> {
  static const _key = 'remote_layouts';

  @override
  Future<List<RemoteLayout>> build() async {
    final raw = await ref.watch(deviceRepositoryProvider).getSetting(_key);
    final user = <RemoteLayout>[];
    try {
      for (final l in (jsonDecode(raw ?? '[]') as List)) {
        try {
          user.add(RemoteLayout.fromJson((l as Map).cast<String, Object?>()));
        } on Object {
          // Skip a layout that no longer validates rather than losing all.
        }
      }
    } on Object {
      // Corrupt setting: start empty.
    }
    return [musicLayout, minimalLayout, ...user];
  }

  static String newId() =>
      'layout-${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 20)}';

  static String newItemId() =>
      'i${DateTime.now().microsecondsSinceEpoch}${Random().nextInt(1000)}';

  Future<void> _store(List<RemoteLayout> all) async {
    await ref
        .read(deviceRepositoryProvider)
        .setSetting(
          _key,
          jsonEncode([
            for (final l in all)
              if (!l.builtIn) l.toJson(),
          ]),
        );
    ref.invalidateSelf();
    await future;
  }

  Future<void> save(RemoteLayout layout) async {
    final all = await future;
    final exists = all.any((l) => l.id == layout.id);
    await _store([
      for (final l in all) l.id == layout.id ? layout : l,
      if (!exists) layout,
    ]);
  }

  Future<void> remove(RemoteLayout layout) async {
    await _store([
      for (final l in await future)
        if (l.id != layout.id) l,
    ]);
    final settings = ref.read(deviceRepositoryProvider);
    if (await settings.getSetting(activeLayoutKey) == layout.id) {
      await setActive(RemoteLayout.standardId);
    }
  }

  static const activeLayoutKey = 'active_layout';

  Future<void> setActive(String id) async {
    await ref.read(deviceRepositoryProvider).setSetting(activeLayoutKey, id);
    ref.invalidate(activeLayoutIdProvider);
  }
}

final layoutLibraryProvider =
    AsyncNotifierProvider<LayoutLibrary, List<RemoteLayout>>(LayoutLibrary.new);

final activeLayoutIdProvider = FutureProvider<String>(
  (ref) async =>
      await ref
          .watch(deviceRepositoryProvider)
          .getSetting(LayoutLibrary.activeLayoutKey) ??
      RemoteLayout.standardId,
);

/// The grid layout to show instead of the standard remote, if any.
final activeLayoutProvider = Provider<RemoteLayout?>((ref) {
  final id = ref.watch(activeLayoutIdProvider).value;
  if (id == null || id == RemoteLayout.standardId) return null;
  final layouts = ref.watch(layoutLibraryProvider).value ?? const [];
  return layouts.where((l) => l.id == id).firstOrNull;
});
