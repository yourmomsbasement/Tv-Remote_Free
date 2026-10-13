import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_remote_free/app/app.dart';
import 'package:tv_remote_free/app/providers.dart';
import 'package:tv_remote_free/core/adapter/smart_tv_adapter.dart';
import 'package:tv_remote_free/core/capabilities/device_capabilities.dart';
import 'package:tv_remote_free/core/capabilities/remote_key.dart';
import 'package:tv_remote_free/core/discovery/discovery_service.dart';
import 'package:tv_remote_free/core/security/credential_store.dart';
import 'package:tv_remote_free/core/storage/device_record.dart';
import 'package:tv_remote_free/core/storage/device_repository.dart';
import 'package:tv_remote_free/features/themes/theme_definition.dart';
import 'package:tv_remote_free/features/themes/themes_screen.dart';
import 'package:tv_remote_free/ui/themes/remote_style.dart';

import 'support/fake_adapter.dart';
import 'support/fake_driver.dart';
import 'support/test_database.dart';

void main() {
  late DeviceRepository repo;
  late FakeAdapter tv;

  Future<void> pumpApp(WidgetTester tester) async {
    final drivers = [FakeDriver(tv)];
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
    // Let the real SQLite futures complete.
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
  }

  setUp(() async {
    tv = FakeAdapter(
      capabilities: const DeviceCapabilities(
        keys: {
          RemoteKey.up,
          RemoteKey.down,
          RemoteKey.left,
          RemoteKey.right,
          RemoteKey.select,
          RemoteKey.home,
          RemoteKey.back,
        },
        textInput: true,
      ),
    );
  });

  testWidgets('lists saved TVs and opens a remote with only supported keys', (
    tester,
  ) async {
    await tester.runAsync(() async {
      repo = await openTestRepository();
      await repo.upsertDevice(
        const DeviceRecord(
          id: 'fake:1',
          name: 'Bedroom TV',
          protocol: 'fake',
          ipAddress: '10.0.0.5',
          room: 'Upstairs',
        ),
      );
    });
    await pumpApp(tester);

    expect(find.text('Bedroom TV'), findsOneWidget);
    expect(find.text('Upstairs'), findsOneWidget);

    await tester.tap(find.text('Bedroom TV'));
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pumpAndSettle();
    }

    expect(find.text('Connected'), findsOneWidget);
    expect(find.text('OK'), findsOneWidget);
    expect(find.bySemanticsLabel('Home'), findsOneWidget);
    // This TV has no volume keys, so none are shown.
    expect(find.bySemanticsLabel('Volume up'), findsNothing);

    await tester.tap(find.text('OK'));
    await tester.pump();
    expect(tv.calls, contains('key:select'));

    await tester.runAsync(() => repo.close());
  });

  testWidgets('leaving the Keyboard tab hides the phone keyboard', (
    tester,
  ) async {
    await tester.runAsync(() async {
      repo = await openTestRepository();
      await repo.upsertDevice(
        const DeviceRecord(
          id: 'fake:1',
          name: 'Bedroom TV',
          protocol: 'fake',
          ipAddress: '10.0.0.5',
        ),
      );
    });
    await pumpApp(tester);
    await tester.tap(find.text('Bedroom TV'));
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pumpAndSettle();
    }

    Future<void> openKeyboardTab() async {
      await tester.tap(find.widgetWithText(Tab, 'Keyboard'));
      await tester.pumpAndSettle();
      await tester.showKeyboard(find.byType(TextField));
      expect(tester.testTextInput.isVisible, isTrue);
    }

    // Tapping another tab.
    await openKeyboardTab();
    await tester.tap(find.widgetWithText(Tab, 'Remote'));
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isFalse);

    // Swiping to the neighbouring tab.
    await openKeyboardTab();
    await tester.fling(find.byType(TabBarView), const Offset(400, 0), 1000);
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isFalse);

    // The auto-open path (keyboard icon in the app bar) still focuses it.
    await tester.tap(find.byTooltip('Keyboard'));
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isTrue);

    await tester.runAsync(() => repo.close());
  });

  testWidgets('the Apps tab shows icons fetched from the TV', (tester) async {
    tv.capabilities = DeviceCapabilities(
      keys: tv.capabilities.keys,
      textInput: true,
      appList: true,
      appLaunch: true,
    );
    tv.apps = const [
      TvApp(id: 'yt', name: 'YouTube', iconUrl: 'http://tv/yt.png'),
      TvApp(id: 'nf', name: 'Netflix'),
    ];
    // A 1x1 transparent PNG.
    tv.icons['yt'] = Uint8List.fromList([
      0x89,
      0x50,
      0x4E,
      0x47,
      0x0D,
      0x0A,
      0x1A,
      0x0A,
      0x00,
      0x00,
      0x00,
      0x0D,
      0x49,
      0x48,
      0x44,
      0x52,
      0x00,
      0x00,
      0x00,
      0x01,
      0x00,
      0x00,
      0x00,
      0x01,
      0x08,
      0x06,
      0x00,
      0x00,
      0x00,
      0x1F,
      0x15,
      0xC4,
      0x89,
      0x00,
      0x00,
      0x00,
      0x0D,
      0x49,
      0x44,
      0x41,
      0x54,
      0x78,
      0x9C,
      0x63,
      0x00,
      0x01,
      0x00,
      0x00,
      0x05,
      0x00,
      0x01,
      0x0D,
      0x0A,
      0x2D,
      0xB4,
      0x00,
      0x00,
      0x00,
      0x00,
      0x49,
      0x45,
      0x4E,
      0x44,
      0xAE,
      0x42,
      0x60,
      0x82,
    ]);
    await tester.runAsync(() async {
      repo = await openTestRepository();
      await repo.upsertDevice(
        const DeviceRecord(
          id: 'fake:1',
          name: 'Den TV',
          protocol: 'fake',
          ipAddress: '10.0.0.5',
        ),
      );
    });
    await pumpApp(tester);
    await tester.tap(find.text('Den TV'));
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pumpAndSettle();
    }
    await tester.tap(find.widgetWithText(Tab, 'Apps'));
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pumpAndSettle();
    }
    expect(find.text('YouTube'), findsOneWidget);
    expect(find.text('Netflix'), findsOneWidget);
    // YouTube has an icon; Netflix falls back to its letter.
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('N'), findsOneWidget);

    await tester.tap(find.text('Netflix'));
    await tester.pump();
    expect(tv.calls, contains('launch:nf'));
    await tester.runAsync(() => repo.close());
  });

  testWidgets('apply a built-in theme, then import one from the clipboard', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    const pasted =
        '{"format":"tv-remote-free-theme","version":1,'
        '"id":"user.lime","name":"Lime","colors":{"seed":"#76FF03"},'
        '"shape":{"button":"square"}}';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.getData') return {'text': pasted};
          return null;
        });

    await tester.runAsync(() async => repo = await openTestRepository());
    await pumpApp(tester);
    // Loading spinners never "settle" while real async work (SQLite, asset
    // loading) runs outside the fake clock, so pump in fixed steps instead.
    Future<void> settle() async {
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Future<void> waitFor(Finder finder) async {
      for (var i = 0; i < 100 && finder.evaluate().isEmpty; i++) {
        await settle();
      }
      expect(finder, findsWidgets);
    }

    RemoteStyle style() =>
        RemoteStyle.of(tester.element(find.byType(ThemesScreen)));

    await tester.tap(find.byTooltip('Settings'));
    await settle();
    await tester.tap(find.text('Remote theme'));
    await settle();
    await waitFor(find.text('Midnight OLED'));
    expect(style().buttonShape, ButtonShape.circle);

    await tester.scrollUntilVisible(find.text('Retro Remote'), 200);
    await tester.ensureVisible(find.text('Retro Remote'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retro Remote'));
    await settle();
    expect(style().buttonShape, ButtonShape.rounded);
    expect(
      await tester.runAsync(() => repo.getSetting('theme_id')),
      'builtin.retro',
    );

    await tester.tap(find.byTooltip('Import theme'));
    await settle();
    await tester.tap(find.text('Paste from clipboard'));
    await settle();
    expect(find.text('Import "Lime"?'), findsOneWidget);
    await tester.tap(find.text('Add & apply'));
    await settle();
    expect(style().buttonShape, ButtonShape.square);
    expect(await tester.runAsync(() => repo.listThemes()), hasLength(1));

    await tester.runAsync(() => repo.close());
  });
}
