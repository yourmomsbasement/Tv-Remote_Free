import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stores pairing secrets (tokens, client keys, certificates).
///
/// Secrets never go into SQLite; the production implementation uses the
/// Android Keystore / iOS Keychain through flutter_secure_storage.
abstract class CredentialStore {
  Future<String?> read(String deviceId);
  Future<void> write(String deviceId, String credential);
  Future<void> delete(String deviceId);
}

class SecureCredentialStore implements CredentialStore {
  SecureCredentialStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static String _key(String deviceId) => 'pairing.$deviceId';

  @override
  Future<String?> read(String deviceId) => _storage.read(key: _key(deviceId));

  @override
  Future<void> write(String deviceId, String credential) =>
      _storage.write(key: _key(deviceId), value: credential);

  @override
  Future<void> delete(String deviceId) => _storage.delete(key: _key(deviceId));
}

class InMemoryCredentialStore implements CredentialStore {
  final _values = <String, String>{};

  @override
  Future<String?> read(String deviceId) async => _values[deviceId];

  @override
  Future<void> write(String deviceId, String credential) async =>
      _values[deviceId] = credential;

  @override
  Future<void> delete(String deviceId) async => _values.remove(deviceId);
}
