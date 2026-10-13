import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_remote_free/app/providers.dart';
import 'package:tv_remote_free/core/adapter/smart_tv_adapter.dart';
import 'package:tv_remote_free/core/capabilities/device_capabilities.dart';
import 'package:tv_remote_free/core/capabilities/remote_key.dart';
import 'package:tv_remote_free/core/discovery/discovery_service.dart';
import 'package:tv_remote_free/core/errors.dart';
import 'package:tv_remote_free/core/security/credential_store.dart';
import 'package:tv_remote_free/core/storage/device_record.dart';
import 'package:tv_remote_free/core/storage/device_repository.dart';
import 'package:tv_remote_free/features/macros/macro.dart';
import 'package:tv_remote_free/features/macros/macro_library.dart';
import 'package:tv_remote_free/features/macros/macro_runner.dart';
import 'package:tv_remote_free/features/remote/remote_session.dart';
import 'package:tv_remote_free/features/remote/sleep_timer.dart';

import '../support/fake_adapter.dart';
import '../support/fake_driver.dart';
import '../support/test_database.dart';

void main() {
  group('model', () {
    test('round-trips through JSON', () {
      final macro = Macro(
        id: 'm1',
        name: 'Movie night',
        deviceId: 'roku:1',
        stopOnError: false,
        steps: const [
          PowerOnStep(),
          WaitConnectedStep(timeoutSeconds: 20),
          KeyStep(RemoteKey.down, times: 3),
          LaunchAppStep(appId: '12', appName: 'Netflix'),
          VolumeStep(18),
          DelayStep(1500),
          TextStep('news', submit: true),
        ],
      );
      final back = Macro.decode('m1', macro.encode());
      expect(back.encode(), macro.encode());
      expect(back.steps.map((s) => s.describe()), [
        'Turn on the TV',
        'Wait for the TV (up to 20 s)',
        'Press Down ×3',
        'Open Netflix',
        'Set volume to 18',
        'Wait 1.5 s',
        'Type "news" and press Enter',
      ]);
    });

    test('clamps values and rejects unknown steps', () {
      final step = MacroStep.fromJson({'type': 'volume', 'level': 900});
      expect((step as VolumeStep).level, 100);
      expect(
        () => MacroStep.fromJson({'type': 'self_destruct'}),
        throwsFormatException,
      );
    });

    test('reports why a TV cannot run a step', () {
      const caps = DeviceCapabilities(keys: {RemoteKey.home});
      expect(const KeyStep(RemoteKey.home).unsupportedReason(caps), isNull);
      expect(
        const KeyStep(RemoteKey.mute).unsupportedReason(caps),
        contains('Mute'),
      );
      expect(const VolumeStep(5).unsupportedReason(caps), isNotNull);
      expect(
        const LaunchAppStep(appId: 'x', appName: 'X').unsupportedReason(caps),
        isNotNull,
      );
    });
  });

  group('runner, volume limit and sleep timer', () {
    late FakeAdapter tv;
    late DeviceRepository repo;
    late ProviderContainer container;
    const device = DeviceRecord(
      id: 'fake:1',
      name: 'Den TV',
      protocol: 'fake',
      ipAddress: '10.0.0.1',
    );

    setUp(() async {
      tv = FakeAdapter(
        capabilities: const DeviceCapabilities(
          keys: {
            RemoteKey.home,
            RemoteKey.down,
            RemoteKey.volumeUp,
            RemoteKey.powerOff,
          },
          volumeSet: true,
          powerOff: true,
          appLaunch: true,
          textInput: true,
        ),
      );
      repo = await openTestRepository();
      final drivers = [FakeDriver(tv)];
      container = ProviderContainer(
        overrides: [
          deviceRepositoryProvider.overrideWithValue(repo),
          credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
          driversProvider.overrideWithValue(drivers),
          discoveryServiceProvider.overrideWithValue(
            DiscoveryService(drivers, ssdp: NoSsdp()),
          ),
        ],
      );
      container.listen(remoteSessionProvider, (_, _) {});
      container.listen(macroRunnerProvider, (_, _) {});
      await container.read(remoteSessionProvider.notifier).connect(device);
    });

    tearDown(() async {
      container.dispose();
      await repo.close();
    });

    MacroRunner runner() => container.read(macroRunnerProvider.notifier);
    RemoteSession session() => container.read(remoteSessionProvider.notifier);

    test('runs steps in order, skipping what the TV cannot do', () async {
      final result = await runner().run(
        const Macro(
          id: 'm',
          name: 'M',
          steps: [
            KeyStep(RemoteKey.home),
            KeyStep(RemoteKey.mute), // not supported
            KeyStep(RemoteKey.down, times: 2),
            LaunchAppStep(appId: '12', appName: 'Netflix'),
            VolumeStep(18),
            TextStep('cats', submit: true),
            DelayStep(100),
          ],
        ),
      );
      expect(result.succeeded, isTrue);
      expect(result.outcomes.map((o) => o.status), [
        StepStatus.done,
        StepStatus.skipped,
        StepStatus.done,
        StepStatus.done,
        StepStatus.done,
        StepStatus.done,
        StepStatus.done,
      ]);
      expect(tv.calls.skip(1), [
        'key:home',
        'key:down',
        'key:down',
        'launch:12',
        'volume:18',
        'text:cats',
        'submit',
      ]);
    });

    test('a failing step stops the macro, or is skipped past', () async {
      tv.failNext = const TvRemoteException(TvErrorCode.unreachable, 'gone');
      const steps = [KeyStep(RemoteKey.home), KeyStep(RemoteKey.down)];
      final stopped = await runner().run(
        const Macro(id: 'a', name: 'A', steps: steps),
      );
      expect(stopped.outcomes.map((o) => o.status), [
        StepStatus.failed,
        StepStatus.notRun,
      ]);
      expect(stopped.outcomes.first.message, 'gone');

      await session().reconnect();
      tv.failNext = const TvRemoteException(TvErrorCode.protocol, 'refused');
      final continued = await runner().run(
        const Macro(id: 'b', name: 'B', steps: steps, stopOnError: false),
      );
      expect(continued.outcomes.map((o) => o.status), [
        StepStatus.failed,
        StepStatus.done,
      ]);
    });

    test('cancel stops before the next step', () async {
      final run = runner().run(
        const Macro(
          id: 'c',
          name: 'C',
          steps: [DelayStep(5000), KeyStep(RemoteKey.home)],
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      runner().cancel();
      final result = await run;
      expect(result.outcomes.last.status, StepStatus.notRun);
      expect(tv.calls, isNot(contains('key:home')));
    });

    test('macros are saved and listed', () async {
      container.listen(macroLibraryProvider, (_, _) {});
      final lib = container.read(macroLibraryProvider.notifier);
      await lib.save(Macro.movieNight('m1'));
      await lib.save(Macro.movieNight('m2').copyWith(name: 'Second'));
      await lib.save(Macro.movieNight('m1').copyWith(name: 'Renamed'));
      final macros = await container.read(macroLibraryProvider.future);
      expect(macros.map((m) => m.name), ['Renamed', 'Second']);
      await lib.remove(macros.first);
      expect(await container.read(macroLibraryProvider.future), hasLength(1));
    });

    test(
      'volume limit blocks Volume up, clamps and pulls the TV back',
      () async {
        await session().setVolumeLimit(20);
        tv.eventController.add(const VolumeChanged(level: 20));
        await Future<void>.delayed(Duration.zero);
        expect(await session().sendKey(RemoteKey.volumeUp), isFalse);
        expect(
          container.read(remoteSessionProvider).error?.message,
          contains('Volume limit (20)'),
        );

        await session().setVolume(80);
        expect(tv.calls.last, 'volume:20');

        // Raised with the TV's own remote: turned back down.
        tv.calls.clear();
        tv.eventController.add(const VolumeChanged(level: 35));
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(tv.calls, ['volume:20']);

        // The limit belongs to this TV and survives reconnecting.
        expect(await repo.getSetting('volume_limit.fake:1'), '20');
        await session().reconnect();
        expect(container.read(remoteSessionProvider).volumeLimit, 20);
        await session().setVolumeLimit(null);
        expect(container.read(remoteSessionProvider).volumeLimit, isNull);
      },
    );

    test('sleep timer turns the TV off when it expires', () async {
      container.listen(sleepTimerProvider, (_, _) {});
      final timer = container.read(sleepTimerProvider.notifier);
      timer.start(const Duration(milliseconds: 50));
      expect(container.read(sleepTimerProvider).active, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(tv.calls.last, 'key:powerOff');
      expect(container.read(sleepTimerProvider).active, isFalse);
    });

    test('a cancelled sleep timer does nothing', () async {
      container.listen(sleepTimerProvider, (_, _) {});
      final timer = container.read(sleepTimerProvider.notifier);
      timer.start(const Duration(milliseconds: 50));
      timer.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(tv.calls, isNot(contains('key:powerOff')));
    });
  });
}
