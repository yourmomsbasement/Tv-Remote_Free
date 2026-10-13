import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_remote_free/app/providers.dart';
import 'package:tv_remote_free/core/security/credential_store.dart';
import 'package:tv_remote_free/core/storage/device_repository.dart';
import 'package:tv_remote_free/features/profiles/profile.dart';
import 'package:tv_remote_free/features/profiles/profiles.dart';
import 'package:tv_remote_free/features/remote/remote_session.dart';

import '../support/test_database.dart';

void main() {
  group('viewing schedule', () {
    // 2026-10-12 is a Monday.
    DateTime at(int day, int hour, [int minute = 0]) =>
        DateTime(2026, 10, 11 + day, hour, minute);

    test('daytime window on chosen days', () {
      const s = ViewingSchedule(
        days: {1, 2, 3, 4, 5},
        start: TimeOfDay(hour: 7, minute: 0),
        end: TimeOfDay(hour: 19, minute: 30),
      );
      expect(s.allows(at(1, 7)), isTrue);
      expect(s.allows(at(1, 19, 29)), isTrue);
      expect(s.allows(at(1, 19, 30)), isFalse);
      expect(s.allows(at(1, 6, 59)), isFalse);
      expect(s.allows(at(6, 12)), isFalse); // Saturday
    });

    test('overnight window belongs to the day it starts', () {
      const s = ViewingSchedule(
        days: {5}, // Friday night
        start: TimeOfDay(hour: 20, minute: 0),
        end: TimeOfDay(hour: 1, minute: 0),
      );
      expect(s.allows(at(5, 22)), isTrue); // Friday 22:00
      expect(s.allows(at(6, 0, 30)), isTrue); // early Saturday
      expect(s.allows(at(6, 22)), isFalse); // Saturday night
      expect(s.allows(at(5, 0, 30)), isFalse); // early Friday (Thu night)
    });

    test('profiles round-trip through JSON', () {
      const p = Profile(
        id: 'p1',
        name: 'Kids',
        child: true,
        simplified: true,
        allowedApps: {'YouTube Kids', 'Netflix'},
        maxVolume: 20,
        schedule: ViewingSchedule(
          days: {6, 7},
          start: TimeOfDay(hour: 8, minute: 15),
          end: TimeOfDay(hour: 18, minute: 0),
        ),
      );
      final back = Profile.fromJson(p.toJson());
      expect(back.toJson(), p.toJson());
      expect(back.allowsApp('netflix'), isTrue);
      expect(back.allowsApp('YouTube'), isFalse);
    });
  });

  group('household profiles', () {
    late DeviceRepository repo;
    late InMemoryCredentialStore secrets;
    late ProviderContainer container;

    setUp(() async {
      repo = await openTestRepository();
      secrets = InMemoryCredentialStore();
      container = ProviderContainer(
        overrides: [
          deviceRepositoryProvider.overrideWithValue(repo),
          credentialStoreProvider.overrideWithValue(secrets),
        ],
      );
      container.listen(profilesProvider, (_, _) {});
      container.listen(remoteSessionProvider, (_, _) {});
    });

    tearDown(() async {
      container.dispose();
      await repo.close();
    });

    Profiles profiles() => container.read(profilesProvider.notifier);
    Future<ProfilesState> state() => container.read(profilesProvider.future);

    test('child profiles are locked behind a hashed PIN', () async {
      const kids = Profile(id: 'kids', name: 'Kids', child: true);
      await profiles().save(kids);
      await profiles().setPin('2468');
      final stored = await secrets.read('app:profile_pin');
      expect(stored, isNot(contains('2468')));

      expect(await profiles().activate('kids'), isTrue);
      expect(container.read(activeProfileProvider).name, 'Kids');

      expect(await profiles().activate(Profile.everyoneId), isFalse);
      expect(
        await profiles().activate(Profile.everyoneId, pin: '1111'),
        isFalse,
      );
      expect(container.read(activeProfileProvider).id, 'kids');
      expect(
        await profiles().activate(Profile.everyoneId, pin: '2468'),
        isTrue,
      );
      expect(container.read(activeProfileProvider).id, Profile.everyoneId);
    });

    test(
      'persist across restarts; deleting the active profile resets',
      () async {
        await profiles().save(const Profile(id: 'teen', name: 'Teen'));
        await profiles().activate('teen');
        final second = ProviderContainer(
          overrides: [
            deviceRepositoryProvider.overrideWithValue(repo),
            credentialStoreProvider.overrideWithValue(secrets),
          ],
        );
        second.listen(profilesProvider, (_, _) {});
        final restored = await second.read(profilesProvider.future);
        expect(restored.active.name, 'Teen');
        second.dispose();

        await profiles().remove((await state()).active);
        expect((await state()).activeId, Profile.everyoneId);
        expect((await state()).profiles, hasLength(1));
      },
    );

    test('the lower of the TV and profile volume limits applies', () {
      const s = RemoteSessionState(volumeLimit: 40, profileVolumeLimit: 25);
      expect(s.effectiveVolumeLimit, 25);
      expect(
        const RemoteSessionState(
          volumeLimit: 10,
          profileVolumeLimit: 25,
        ).effectiveVolumeLimit,
        10,
      );
      expect(
        const RemoteSessionState(profileVolumeLimit: 25).effectiveVolumeLimit,
        25,
      );
      expect(const RemoteSessionState().effectiveVolumeLimit, isNull);
    });

    test('PIN format', () {
      expect(Profiles.validPin('1234'), isTrue);
      expect(Profiles.validPin('123'), isFalse);
      expect(Profiles.validPin('12a4'), isFalse);
      expect(Profiles.validPin('123456789'), isFalse);
    });
  });
}
