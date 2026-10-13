import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_remote_free/app/providers.dart';
import 'package:tv_remote_free/core/discovery/discovery_service.dart';
import 'package:tv_remote_free/core/security/credential_store.dart';
import 'package:tv_remote_free/core/storage/app_icon_cache.dart';
import 'package:tv_remote_free/core/storage/device_record.dart';
import 'package:tv_remote_free/core/storage/device_repository.dart';
import 'package:tv_remote_free/features/applications/apps_panel.dart';
import 'package:tv_remote_free/features/remote/remote_session.dart';

import '../support/fake_adapter.dart';
import '../support/fake_driver.dart';
import '../support/test_database.dart';

void main() {
  late Directory dir;
  late DateTime now;
  final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 1, 2, 3]);

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('icons');
    now = DateTime(2026, 10, 13, 12);
  });
  tearDown(() => dir.delete(recursive: true));

  AppIconCache cache({int maxBytes = 1 << 20}) =>
      AppIconCache(dir, clock: () => now, maxBytes: maxBytes);

  test('stores icons and reports when they are due for a refresh', () async {
    final c = cache();
    expect(await c.read('tv1', '12', 'u'), isNull);
    await c.write('tv1', '12', 'u', png);
    final hit = (await c.read('tv1', '12', 'u'))!;
    expect(hit.bytes, png);
    expect(hit.fresh, isTrue);
    // A changed icon URL is a different entry.
    expect(await c.read('tv1', '12', 'other'), isNull);

    now = now.add(const Duration(days: 31));
    final old = (await c.read('tv1', '12', 'u'))!;
    expect(old.fresh, isFalse);
    expect(old.bytes, png, reason: 'stale icons are still available');
  });

  test('remembers apps without an icon for a day', () async {
    final c = cache();
    await c.write('tv1', 'x', null, null);
    final miss = (await c.read('tv1', 'x', null))!;
    expect(miss.bytes, isNull);
    expect(miss.fresh, isTrue);
    now = now.add(const Duration(days: 2));
    expect((await c.read('tv1', 'x', null))!.fresh, isFalse);
  });

  test('clears one TV, or everything', () async {
    final c = cache();
    await c.write('tv1', 'a', null, png);
    await c.write('tv2', 'a', null, png);
    await c.clearDevice('tv1');
    expect(await c.read('tv1', 'a', null), isNull);
    expect(await c.read('tv2', 'a', null), isNotNull);
    expect(await c.sizeInBytes(), png.length);
    await c.clearAll();
    expect(await c.sizeInBytes(), 0);
  });

  test('prunes least recently used icons over the size cap', () async {
    final c = cache(maxBytes: png.length * 2);
    for (final id in ['a', 'b', 'c']) {
      await c.write('tv', id, null, png);
      now = now.add(const Duration(minutes: 1));
    }
    await c.read('tv', 'a', null); // 'a' used most recently now
    await c.prune();
    expect(await c.read('tv', 'b', null), isNull);
    expect(await c.read('tv', 'a', null), isNotNull);
    expect(await c.read('tv', 'c', null), isNotNull);
  });

  group('with the app', () {
    late FakeAdapter tv;
    late DeviceRepository repo;
    const device = DeviceRecord(
      id: 'fake:1',
      name: 'Den',
      protocol: 'fake',
      ipAddress: '10.0.0.1',
    );

    Future<ProviderContainer> launch() async {
      final drivers = [FakeDriver(tv)];
      final c = ProviderContainer(
        overrides: [
          deviceRepositoryProvider.overrideWithValue(repo),
          credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
          driversProvider.overrideWithValue(drivers),
          discoveryServiceProvider.overrideWithValue(
            DiscoveryService(drivers, ssdp: NoSsdp()),
          ),
          appIconCacheProvider.overrideWithValue(cache()),
        ],
      );
      c.listen(remoteSessionProvider, (_, _) {});
      await c.read(remoteSessionProvider.notifier).connect(device);
      return c;
    }

    setUp(() async {
      tv = FakeAdapter()..icons['12'] = png;
      repo = await openTestRepository();
    });
    tearDown(() => repo.close());

    test('icons survive a relaunch without asking the TV again', () async {
      final first = await launch();
      expect(
        await first.read(appIconProvider(('fake:1', '12', 'u')).future),
        png,
      );
      expect(tv.calls.where((c) => c.startsWith('icon:')), ['icon:12']);
      first.dispose();

      tv.calls.clear();
      final second = await launch();
      expect(
        await second.read(appIconProvider(('fake:1', '12', 'u')).future),
        png,
      );
      expect(tv.calls.where((c) => c.startsWith('icon:')), isEmpty);
      second.dispose();
    });

    test('an old icon is refreshed, but kept if the TV has none now', () async {
      await cache().write('fake:1', '12', 'u', png);
      now = now.add(const Duration(days: 40));
      tv.icons.clear(); // e.g. the TV failed to serve it this time
      final c = await launch();
      expect(await c.read(appIconProvider(('fake:1', '12', 'u')).future), png);
      expect(tv.calls, contains('icon:12'));
      c.dispose();
    });
  });
}
