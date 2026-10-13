import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tv_remote_free/core/storage/device_repository.dart';

/// An in-memory SQLite repository using the host's sqlite3 library.
Future<DeviceRepository> openTestRepository() {
  sqfliteFfiInit();
  return DeviceRepository.open(
    factory: databaseFactoryFfiNoIsolate,
    path: inMemoryDatabasePath,
  );
}
