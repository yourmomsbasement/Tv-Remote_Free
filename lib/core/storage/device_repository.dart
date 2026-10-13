import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'device_record.dart';

/// SQLite persistence for saved TVs, per-device preferences and app settings.
class DeviceRepository {
  DeviceRepository(this._db);

  final Database _db;

  static const _schemaVersion = 1;

  static Future<DeviceRepository> open({
    DatabaseFactory? factory,
    String? path,
  }) async {
    final dbFactory = factory ?? databaseFactory;
    final dbPath =
        path ?? p.join(await dbFactory.getDatabasesPath(), 'tv_remote.db');
    final db = await dbFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: _schemaVersion,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE devices (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              manufacturer TEXT,
              model TEXT,
              protocol TEXT NOT NULL,
              ip_address TEXT,
              mac_address TEXT,
              room TEXT,
              last_connected INTEGER,
              is_favorite INTEGER DEFAULT 0
            )''');
          await db.execute('''
            CREATE TABLE remote_preferences (
              device_id TEXT PRIMARY KEY,
              layout TEXT DEFAULT 'standard',
              haptics_enabled INTEGER DEFAULT 1,
              keyboard_auto_open INTEGER DEFAULT 1,
              FOREIGN KEY (device_id) REFERENCES devices(id) ON DELETE CASCADE
            )''');
          await db.execute('''
            CREATE TABLE app_settings (
              key TEXT PRIMARY KEY,
              value TEXT
            )''');
        },
      ),
    );
    return DeviceRepository(db);
  }

  /// Favorites first, then most recently connected.
  Future<List<DeviceRecord>> listDevices() async {
    final rows = await _db.query(
      'devices',
      orderBy: 'is_favorite DESC, last_connected DESC, name COLLATE NOCASE',
    );
    return rows.map(DeviceRecord.fromMap).toList();
  }

  Future<DeviceRecord?> getDevice(String id) async {
    final rows = await _db.query('devices', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : DeviceRecord.fromMap(rows.first);
  }

  /// Inserts or updates in place. (INSERT OR REPLACE would delete the old row
  /// and cascade-delete its preferences.)
  Future<void> upsertDevice(DeviceRecord device) =>
      _db.transaction((txn) async {
        final updated = await txn.update(
          'devices',
          device.toMap(),
          where: 'id = ?',
          whereArgs: [device.id],
        );
        if (updated == 0) await txn.insert('devices', device.toMap());
      });

  Future<void> deleteDevice(String id) =>
      _db.delete('devices', where: 'id = ?', whereArgs: [id]);

  Future<RemotePreferences> getPreferences(String deviceId) async {
    final rows = await _db.query(
      'remote_preferences',
      where: 'device_id = ?',
      whereArgs: [deviceId],
    );
    return rows.isEmpty
        ? RemotePreferences(deviceId: deviceId)
        : RemotePreferences.fromMap(rows.first);
  }

  Future<void> savePreferences(RemotePreferences prefs) => _db.insert(
    'remote_preferences',
    prefs.toMap(),
    conflictAlgorithm: ConflictAlgorithm.replace,
  );

  Future<String?> getSetting(String key) async {
    final rows = await _db.query(
      'app_settings',
      where: 'key = ?',
      whereArgs: [key],
    );
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  Future<void> setSetting(String key, String value) => _db.insert(
    'app_settings',
    {'key': key, 'value': value},
    conflictAlgorithm: ConflictAlgorithm.replace,
  );

  Future<void> close() => _db.close();
}
