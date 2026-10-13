import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'device_record.dart';

/// SQLite persistence for saved TVs, per-device preferences and app settings.
class DeviceRepository {
  DeviceRepository(this._db);

  final Database _db;

  /// 1: devices, preferences, settings. 2: user themes. 3: macros.
  /// 4: watchlist.
  static const _schemaVersion = 4;

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
          await _createThemes(db);
          await _createMacros(db);
          await _createWatchlist(db);
        },
        onUpgrade: (db, from, to) async {
          if (from < 2) await _createThemes(db);
          if (from < 3) await _createMacros(db);
          if (from < 4) await _createWatchlist(db);
        },
      ),
    );
    return DeviceRepository(db);
  }

  static Future<void> _createThemes(Database db) => db.execute('''
    CREATE TABLE themes (
      id TEXT PRIMARY KEY,
      json TEXT NOT NULL,
      installed_at INTEGER NOT NULL
    )''');

  static Future<void> _createMacros(Database db) => db.execute('''
    CREATE TABLE macros (
      id TEXT PRIMARY KEY,
      json TEXT NOT NULL,
      created_at INTEGER NOT NULL
    )''');

  static Future<void> _createWatchlist(Database db) => db.execute('''
    CREATE TABLE watchlist (
      id TEXT PRIMARY KEY,
      title TEXT NOT NULL,
      url TEXT NOT NULL,
      added_at INTEGER NOT NULL,
      watched INTEGER NOT NULL DEFAULT 0
    )''');

  /// Watchlist rows, newest first.
  Future<List<Map<String, Object?>>> listWatchlist() =>
      _db.query('watchlist', orderBy: 'added_at DESC');

  Future<void> saveWatchItem(Map<String, Object?> row) => _db.insert(
    'watchlist',
    row,
    conflictAlgorithm: ConflictAlgorithm.replace,
  );

  Future<void> deleteWatchItem(String id) =>
      _db.delete('watchlist', where: 'id = ?', whereArgs: [id]);

  /// Saved macros, oldest first, as (id, JSON).
  Future<List<(String, String)>> listMacros() async {
    final rows = await _db.query('macros', orderBy: 'created_at');
    return [for (final r in rows) (r['id']! as String, r['json']! as String)];
  }

  /// Inserts or updates a macro, keeping its original position.
  Future<void> saveMacro(String id, String json) =>
      _db.transaction((txn) async {
        final updated = await txn.update(
          'macros',
          {'json': json},
          where: 'id = ?',
          whereArgs: [id],
        );
        if (updated == 0) {
          await txn.insert('macros', {
            'id': id,
            'json': json,
            'created_at': DateTime.now().microsecondsSinceEpoch,
          });
        }
      });

  Future<void> deleteMacro(String id) =>
      _db.delete('macros', where: 'id = ?', whereArgs: [id]);

  /// Imported theme files, oldest first, as (id, raw JSON).
  Future<List<(String, String)>> listThemes() async {
    final rows = await _db.query('themes', orderBy: 'installed_at');
    return [for (final r in rows) (r['id']! as String, r['json']! as String)];
  }

  /// Installs or replaces a theme with the same id.
  Future<void> saveTheme(String id, String json) => _db.insert('themes', {
    'id': id,
    'json': json,
    'installed_at': DateTime.now().millisecondsSinceEpoch,
  }, conflictAlgorithm: ConflictAlgorithm.replace);

  Future<void> deleteTheme(String id) =>
      _db.delete('themes', where: 'id = ?', whereArgs: [id]);

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
