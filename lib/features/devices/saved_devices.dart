import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/storage/device_record.dart';

/// Saved TVs, favorites first.
class SavedDevicesNotifier extends AsyncNotifier<List<DeviceRecord>> {
  @override
  Future<List<DeviceRecord>> build() =>
      ref.watch(deviceRepositoryProvider).listDevices();

  Future<void> save(DeviceRecord device) async {
    await ref.read(deviceRepositoryProvider).upsertDevice(device);
    ref.invalidateSelf();
    await future;
  }

  Future<void> toggleFavorite(DeviceRecord device) =>
      save(device.copyWith(isFavorite: !device.isFavorite));

  /// Forgets the TV and its pairing secret.
  Future<void> remove(DeviceRecord device) async {
    await ref.read(credentialStoreProvider).delete(device.id);
    await ref.read(deviceRepositoryProvider).deleteDevice(device.id);
    ref.invalidateSelf();
    await future;
  }
}

final savedDevicesProvider =
    AsyncNotifierProvider<SavedDevicesNotifier, List<DeviceRecord>>(
      SavedDevicesNotifier.new,
    );
