import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tv_remote_free/core/storage/device_record.dart';
import 'package:tv_remote_free/core/storage/device_repository.dart';

import '../support/test_database.dart';

void main() {
  late DeviceRepository repo;

  setUp(() async => repo = await openTestRepository());
  tearDown(() => repo.close());

  DeviceRecord tv(String id, {bool favorite = false, int? last}) =>
      DeviceRecord(
        id: id,
        name: 'TV $id',
        protocol: Protocols.roku,
        ipAddress: '10.0.0.$id',
        isFavorite: favorite,
        lastConnected: last == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(last),
      );

  test('round-trips a device', () async {
    final device = tv('1')
        .copyWith(macAddress: 'aa:bb:cc:dd:ee:ff', room: 'Den', model: 'Ultra');
    await repo.upsertDevice(device);
    final loaded = (await repo.getDevice('1'))!;
    expect(loaded.toMap(), device.toMap());
  });

  test('lists favorites first, then most recently used', () async {
    await repo.upsertDevice(tv('1', last: 100));
    await repo.upsertDevice(tv('2', last: 300));
    await repo.upsertDevice(tv('3', favorite: true, last: 50));
    final ids = (await repo.listDevices()).map((d) => d.id);
    expect(ids, ['3', '2', '1']);
  });

  test('updating a device keeps its preferences', () async {
    await repo.upsertDevice(tv('1'));
    await repo.savePreferences(
      const RemotePreferences(deviceId: '1', hapticsEnabled: false),
    );
    await repo.upsertDevice(tv('1').copyWith(name: 'Renamed'));
    expect((await repo.getDevice('1'))!.name, 'Renamed');
    expect((await repo.getPreferences('1')).hapticsEnabled, isFalse);
  });

  test('deleting a device removes its preferences', () async {
    await repo.upsertDevice(tv('1'));
    await repo.savePreferences(
      const RemotePreferences(deviceId: '1', keyboardAutoOpen: false),
    );
    await repo.deleteDevice('1');
    expect(await repo.getDevice('1'), isNull);
    expect((await repo.getPreferences('1')).keyboardAutoOpen, isTrue);
  });

  test('stores app settings', () async {
    expect(await repo.getSetting('theme_mode'), isNull);
    await repo.setSetting('theme_mode', 'dark');
    await repo.setSetting('theme_mode', 'light');
    expect(await repo.getSetting('theme_mode'), 'light');
  });

  test('schema has no column for secrets', () async {
    final columns = tv('1').toMap().keys;
    expect(
      columns.where((c) => c.contains('key') || c.contains('token')),
      isEmpty,
    );
  });

  test('stores, replaces and deletes themes', () async {
    await repo.saveTheme('user.a', '{"v":1}');
    await repo.saveTheme('user.b', '{"v":2}');
    await repo.saveTheme('user.a', '{"v":3}');
    expect(await repo.listThemes(), [
      ('user.b', '{"v":2}'),
      ('user.a', '{"v":3}'),
    ]);
    await repo.deleteTheme('user.b');
    expect((await repo.listThemes()).map((t) => t.$1), ['user.a']);
  });

  test('upgrades a version 1 database without losing data', () async {
    sqfliteFfiInit();
    final dir = await Directory.systemTemp.createTemp('tvrf');
    final path = '${dir.path}/v1.db';
    // A database as created by the first release.
    final v1 = await databaseFactoryFfiNoIsolate.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE devices (id TEXT PRIMARY KEY, '
            'name TEXT NOT NULL, manufacturer TEXT, model TEXT, '
            'protocol TEXT NOT NULL, ip_address TEXT, mac_address TEXT, '
            'room TEXT, last_connected INTEGER, is_favorite INTEGER DEFAULT 0)',
          );
          await db.execute(
            'CREATE TABLE remote_preferences (device_id TEXT '
            'PRIMARY KEY, layout TEXT, haptics_enabled INTEGER, '
            'keyboard_auto_open INTEGER)',
          );
          await db.execute(
            'CREATE TABLE app_settings (key TEXT PRIMARY KEY, value TEXT)',
          );
          await db.insert('devices', {
            'id': 'roku:1',
            'name': 'Den',
            'protocol': 'roku',
          });
        },
      ),
    );
    await v1.close();

    final upgraded = await DeviceRepository.open(
      factory: databaseFactoryFfiNoIsolate,
      path: path,
    );
    expect((await upgraded.getDevice('roku:1'))?.name, 'Den');
    await upgraded.saveTheme('user.x', '{}');
    expect(await upgraded.listThemes(), hasLength(1));
    await upgraded.saveMacro('m', '{}');
    expect(await upgraded.listMacros(), [('m', '{}')]);
    expect(await upgraded.listWatchlist(), isEmpty);
    await upgraded.close();
    await dir.delete(recursive: true);
  });
}
