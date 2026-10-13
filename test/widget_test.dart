import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_remote_free/app/app.dart';
import 'package:tv_remote_free/app/providers.dart';
import 'package:tv_remote_free/core/capabilities/device_capabilities.dart';
import 'package:tv_remote_free/core/capabilities/remote_key.dart';
import 'package:tv_remote_free/core/discovery/discovery_service.dart';
import 'package:tv_remote_free/core/security/credential_store.dart';
import 'package:tv_remote_free/core/storage/device_record.dart';
import 'package:tv_remote_free/core/storage/device_repository.dart';

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
}
