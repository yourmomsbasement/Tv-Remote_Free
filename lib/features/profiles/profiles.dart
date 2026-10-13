import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import 'profile.dart';

class ProfilesState {
  const ProfilesState({
    this.profiles = const [Profile.everyone],
    this.activeId = Profile.everyoneId,
    this.hasPin = false,
  });

  final List<Profile> profiles;
  final String activeId;

  /// A household PIN is set (required once a child profile exists).
  final bool hasPin;

  Profile get active =>
      profiles.where((p) => p.id == activeId).firstOrNull ?? Profile.everyone;
}

/// Household profiles, the active one, and the PIN guarding child mode.
///
/// The PIN is stored only as a salted SHA-256 hash in the secure store.
class Profiles extends AsyncNotifier<ProfilesState> {
  static const _listKey = 'profiles';
  static const _activeKey = 'active_profile';
  static const _pinKey = 'app:profile_pin';

  @override
  Future<ProfilesState> build() async {
    final repo = ref.watch(deviceRepositoryProvider);
    final profiles = <Profile>[Profile.everyone];
    try {
      final raw = jsonDecode(await repo.getSetting(_listKey) ?? '[]');
      for (final p in raw as List) {
        if (p is Map<String, Object?> && p['id'] != Profile.everyoneId) {
          profiles.add(Profile.fromJson(p));
        }
      }
    } on Object {
      // Corrupt settings: fall back to Everyone only.
    }
    final active = await repo.getSetting(_activeKey);
    final pin = await ref.read(credentialStoreProvider).read(_pinKey);
    return ProfilesState(
      profiles: profiles,
      activeId: profiles.any((p) => p.id == active)
          ? active!
          : Profile.everyoneId,
      hasPin: pin != null,
    );
  }

  static String newId() =>
      'p-${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 20)}';

  Future<void> _store(List<Profile> profiles, String activeId) async {
    final repo = ref.read(deviceRepositoryProvider);
    await repo.setSetting(
      _listKey,
      jsonEncode([
        for (final p in profiles)
          if (p.id != Profile.everyoneId) p.toJson(),
      ]),
    );
    await repo.setSetting(_activeKey, activeId);
    final current = await future;
    state = AsyncData(
      ProfilesState(
        profiles: profiles,
        activeId: activeId,
        hasPin: current.hasPin,
      ),
    );
  }

  Future<void> save(Profile profile) async {
    final current = await future;
    final exists = current.profiles.any((p) => p.id == profile.id);
    await _store([
      for (final p in current.profiles) p.id == profile.id ? profile : p,
      if (!exists) profile,
    ], current.activeId);
  }

  Future<void> remove(Profile profile) async {
    if (profile.id == Profile.everyoneId) return;
    final current = await future;
    await _store([
      for (final p in current.profiles)
        if (p.id != profile.id) p,
    ], current.activeId == profile.id ? Profile.everyoneId : current.activeId);
  }

  /// Switches profile. Leaving a child profile needs the PIN; returns false
  /// if it is missing or wrong.
  Future<bool> activate(String id, {String? pin}) async {
    final current = await future;
    if (current.active.child && !await checkPin(pin ?? '')) return false;
    await _store(current.profiles, id);
    return true;
  }

  static String _hash(String salt, String pin) =>
      sha256.convert(utf8.encode('$salt:$pin')).toString();

  Future<void> setPin(String pin) async {
    final salt = base64Url.encode(
      List<int>.generate(16, (_) => Random.secure().nextInt(256)),
    );
    await ref
        .read(credentialStoreProvider)
        .write(_pinKey, '$salt:${_hash(salt, pin)}');
    final current = await future;
    state = AsyncData(
      ProfilesState(
        profiles: current.profiles,
        activeId: current.activeId,
        hasPin: true,
      ),
    );
  }

  Future<bool> checkPin(String pin) async {
    final stored = await ref.read(credentialStoreProvider).read(_pinKey);
    if (stored == null) return true; // no PIN set yet
    final i = stored.indexOf(':');
    if (i < 0) return false;
    return _hash(stored.substring(0, i), pin) == stored.substring(i + 1);
  }

  static bool validPin(String pin) => RegExp(r'^\d{4,8}$').hasMatch(pin);
}

final profilesProvider = AsyncNotifierProvider<Profiles, ProfilesState>(
  Profiles.new,
);

/// The active profile (Everyone while loading).
final activeProfileProvider = Provider<Profile>(
  (ref) => ref.watch(profilesProvider).value?.active ?? Profile.everyone,
);
