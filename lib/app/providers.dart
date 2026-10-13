import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/adapter/protocol_driver.dart';
import '../core/discovery/discovery_service.dart';
import '../core/security/credential_store.dart';
import '../core/storage/device_repository.dart';
import '../protocols/registry.dart';

/// Overridden in tests with in-memory implementations.
final credentialStoreProvider = Provider<CredentialStore>(
  (ref) => SecureCredentialStore(),
);

final driversProvider = Provider<List<ProtocolDriver>>(
  (ref) => defaultDrivers(),
);

final discoveryServiceProvider = Provider(
  (ref) => DiscoveryService(ref.watch(driversProvider)),
);

/// Opened once in main() and injected with an override.
final deviceRepositoryProvider = Provider<DeviceRepository>(
  (ref) => throw UnimplementedError('deviceRepositoryProvider not overridden'),
);
