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
import 'package:tv_remote_free/features/keyboard/keyboard_controller.dart';
import 'package:tv_remote_free/features/remote/remote_session.dart';

import '../support/fake_adapter.dart';
import '../support/fake_driver.dart';
import '../support/test_database.dart';

void main() {
  late FakeAdapter tv;
  late DeviceRepository repo;
  late InMemoryCredentialStore credentials;
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
        keys: {RemoteKey.up, RemoteKey.select, RemoteKey.home},
        textInput: true,
      ),
    );
    repo = await openTestRepository();
    credentials = InMemoryCredentialStore();
    final drivers = [FakeDriver(tv)];
    container = ProviderContainer(
      overrides: [
        deviceRepositoryProvider.overrideWithValue(repo),
        credentialStoreProvider.overrideWithValue(credentials),
        driversProvider.overrideWithValue(drivers),
        discoveryServiceProvider.overrideWithValue(
          DiscoveryService(drivers, ssdp: NoSsdp()),
        ),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await repo.close();
  });

  RemoteSession session() => container.read(remoteSessionProvider.notifier);
  RemoteSessionState state() => container.read(remoteSessionProvider);

  test('connecting saves the TV and loads its capabilities', () async {
    container.listen(remoteSessionProvider, (_, _) {});
    await session().connect(device);
    expect(state().isConnected, isTrue);
    expect(state().capabilities.supportsKey(RemoteKey.home), isTrue);
    final saved = await repo.getDevice('fake:1');
    expect(saved?.name, 'Den TV');
    expect(saved?.lastConnected, isNotNull);
    expect(session().keyboard.state, KeyboardState.connected);
  });

  test('supported keys reach the TV; unsupported ones are refused', () async {
    container.listen(remoteSessionProvider, (_, _) {});
    await session().connect(device);
    expect(await session().sendKey(RemoteKey.home), isTrue);
    expect(await session().sendKey(RemoteKey.volumeUp), isFalse);
    expect(state().error?.code, TvErrorCode.unsupported);
    expect(tv.calls.where((c) => c.startsWith('key:')), ['key:home']);
  });

  test('pairing secrets go to the credential store, not SQLite', () async {
    container.listen(remoteSessionProvider, (_, _) {});
    await session().connect(device);
    tv.eventController.add(const PairingCompleted('secret-key'));
    tv.eventController.add(
      const DeviceInfoUpdated(macAddress: 'aa:bb:cc:dd:ee:ff'),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(await credentials.read('fake:1'), 'secret-key');
    final saved = (await repo.getDevice('fake:1'))!;
    expect(saved.macAddress, 'aa:bb:cc:dd:ee:ff');
    expect(saved.toMap().values, isNot(contains('secret-key')));
    expect(state().canPowerOn, isTrue);
  });

  test('TV text-field focus reaches the keyboard controller', () async {
    container.listen(remoteSessionProvider, (_, _) {});
    await session().connect(device);
    tv.eventController.add(const TextFieldFocusChanged(focused: true));
    await Future<void>.delayed(Duration.zero);
    expect(state().textFieldFocused, isTrue);
    expect(session().keyboard.state, KeyboardState.textFieldDetected);
  });

  test('an unexpected disconnect detaches the keyboard and retries', () async {
    container.listen(remoteSessionProvider, (_, _) {});
    await session().connect(device);
    tv.eventController.add(
      const ConnectionStatusChanged(ConnectionStatus.disconnected),
    );
    await Future<void>.delayed(Duration.zero);
    expect(state().isConnected, isFalse);
    expect(state().reconnecting, isTrue);
    expect(session().keyboard.state, KeyboardState.disconnected);
    await session().disconnect();
    expect(state().reconnecting, isFalse);
  });

  test('PIN pairing: prompt, wrong code message, then success', () async {
    container.listen(remoteSessionProvider, (_, _) {});
    await session().connect(device);
    tv.eventController.add(const PairingPromptShown(needsPin: true));
    await Future<void>.delayed(Duration.zero);
    expect(state().awaitingPin, isTrue);

    tv.failNext = const TvRemoteException(
      TvErrorCode.pairingRejected,
      'That code does not match.',
    );
    expect(await session().submitPin('000000'), 'That code does not match.');
    expect(state().awaitingPin, isTrue);

    expect(await session().submitPin('A1B2C3'), isNull);
    expect(state().awaitingPin, isFalse);
    expect(tv.calls, contains('pair:A1B2C3'));
  });
}
