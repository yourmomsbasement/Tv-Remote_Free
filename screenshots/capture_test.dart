// Renders store screenshots of the real app driving the demo TV.
//
//   flutter test screenshots/capture_test.dart --update-goldens
//
// Raw screens land in screenshots/raw/; tool/make_store_images.py frames
// them for the App Store and Google Play.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_remote_free/app/app.dart';
import 'package:tv_remote_free/app/providers.dart';
import 'package:tv_remote_free/core/adapter/smart_tv_adapter.dart';
import 'package:tv_remote_free/core/discovery/discovery_service.dart';
import 'package:tv_remote_free/core/security/credential_store.dart';
import 'package:tv_remote_free/core/storage/device_record.dart';
import 'package:tv_remote_free/core/storage/device_repository.dart';
import 'package:tv_remote_free/features/settings/app_settings.dart';
import 'package:tv_remote_free/features/watchlist/watchlist.dart';
import 'package:tv_remote_free/protocols/demo/demo_adapter.dart';
import 'package:tv_remote_free/protocols/demo/demo_driver.dart';

import '../test/support/fake_driver.dart' show NoSsdp;
import '../test/support/test_database.dart';

class _InstantDemoDriver extends DemoDriver {
  @override
  SmartTVAdapter createAdapter(DeviceRecord device) =>
      DemoAdapter(latency: Duration.zero);
}

Future<void> _loadFonts() async {
  final sdk = File(Platform.resolvedExecutable)
      .parent
      .parent
      .parent
      .parent
      .parent
      .parent
      .path;
  final fonts = '$sdk/bin/cache/artifacts/material_fonts';
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      final bytes = File('$fonts/$f').readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }

  await load('Roboto', [
    'Roboto-Regular.ttf',
    'Roboto-Medium.ttf',
    'Roboto-Bold.ttf',
    'Roboto-Light.ttf',
  ]);
  await load('MaterialIcons', ['MaterialIcons-Regular.otf']);
}

void main() {
  late DeviceRepository repo;

  setUpAll(() async {
    await _loadFonts();
  });

  Future<void> settle(WidgetTester tester, [int rounds = 6]) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> shot(WidgetTester tester, String name) async {
    await settle(tester, 3);
    await expectLater(
      find.byType(TvRemoteApp),
      matchesGoldenFile('raw/$name.png'),
    );
  }

  testWidgets('store screenshots', (tester) async {
    tester.view
      ..physicalSize = const Size(1320, 2868)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    // Tests draw shadows as black outlines unless told otherwise.
    debugDisableShadows = false;
    // Touch screenshots: no keyboard-focus outlines.
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTouch;

    await tester.runAsync(() async {
      repo = await openTestRepository();
      for (final d in const [
        DeviceRecord(
          id: 'shot:1',
          name: 'Living Room',
          protocol: Protocols.samsung,
          ipAddress: '192.168.1.20',
          room: 'Downstairs',
          isFavorite: true,
        ),
        DeviceRecord(
          id: 'shot:2',
          name: 'Kitchen',
          protocol: Protocols.roku,
          ipAddress: '192.168.1.31',
          room: 'Downstairs',
        ),
        DeviceRecord(
          id: 'shot:3',
          name: 'Bedroom',
          protocol: Protocols.lgWebOs,
          ipAddress: '192.168.1.42',
          room: 'Upstairs',
        ),
        DeviceRecord(
          id: 'shot:4',
          name: 'Kids Room',
          protocol: Protocols.androidTv,
          ipAddress: '192.168.1.57',
          room: 'Upstairs',
        ),
      ]) {
        await repo.upsertDevice(d);
      }
    });
    final drivers = [_InstantDemoDriver()];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          deviceRepositoryProvider.overrideWithValue(repo),
          credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
          driversProvider.overrideWithValue(drivers),
          discoveryServiceProvider.overrideWithValue(
            DiscoveryService(drivers, ssdp: NoSsdp()),
          ),
        ],
        child: const TvRemoteApp(),
      ),
    );
    await settle(tester, 10);
    await shot(tester, '1_tvs');

    await tester.tap(find.text('Try the demo TV'));
    await settle(tester, 10);
    // Start a movie so the remote shows what's playing.
    await tester.tap(find.text('Apps'));
    await settle(tester);
    await shot(tester, '4_apps');
    await tester.tap(find.text('Movies').last);
    await settle(tester);
    await tester.tap(find.text('Remote'));
    await settle(tester);
    await shot(tester, '2_remote');

    await tester.tap(find.text('Touchpad'));
    await settle(tester);
    await shot(tester, '5_touchpad');

    await tester.tap(find.text('Keyboard'));
    await settle(tester);
    await tester.enterText(
      find.byType(TextField).first,
      'nature documentaries',
    );
    await settle(tester);
    await shot(tester, '3_keyboard');

    final container = ProviderScope.containerOf(
      tester.element(find.byType(TvRemoteApp)),
    );
    await tester.runAsync(() async {
      final watchlist = container.read(watchlistProvider.notifier);
      await container.read(watchlistProvider.future);
      for (final (url, title) in const [
        ('https://www.youtube.com/watch?v=aqz-KE-bpKQ', 'Big Buck Bunny'),
        ('https://www.netflix.com/title/80057281', 'Stranger Things'),
        ('https://www.disneyplus.com/movies/x/abc', 'Weekend movie night'),
        ('https://www.primevideo.com/detail/0ABC', 'The Grand Tour'),
      ]) {
        await watchlist.addFromText(url, title: title);
      }
    });
    await tester.tap(find.text('Watchlist'));
    await settle(tester);
    await shot(tester, '6_watchlist');

    await tester.runAsync(() async {
      final settings = container.read(appSettingsProvider.notifier);
      await settings.save(
        container.read(settingsProvider).copyWith(themeId: 'builtin.midnight'),
      );
    });
    await tester.tap(find.text('Remote'));
    await settle(tester, 10);
    await shot(tester, '7_theme');

    await tester.pumpWidget(const SizedBox());
    await settle(tester);
    await tester.runAsync(() => repo.close());
    debugDisableShadows = true;
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic;
  });
}
