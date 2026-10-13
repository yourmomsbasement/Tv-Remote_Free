/// Protocol identifiers persisted in `devices.protocol`.
abstract final class Protocols {
  static const roku = 'roku';
  static const lgWebOs = 'lg_webos';

  static const all = [roku, lgWebOs];

  static String label(String protocol) => switch (protocol) {
    roku => 'Roku',
    lgWebOs => 'LG webOS',
    _ => protocol,
  };
}

/// Nonsensitive metadata about a saved TV. Secrets live in [CredentialStore].
class DeviceRecord {
  const DeviceRecord({
    required this.id,
    required this.name,
    required this.protocol,
    this.manufacturer,
    this.model,
    this.ipAddress,
    this.macAddress,
    this.room,
    this.lastConnected,
    this.isFavorite = false,
  });

  final String id;
  final String name;
  final String protocol;
  final String? manufacturer;
  final String? model;
  final String? ipAddress;
  final String? macAddress;
  final String? room;
  final DateTime? lastConnected;
  final bool isFavorite;

  DeviceRecord copyWith({
    String? name,
    String? model,
    String? ipAddress,
    String? macAddress,
    String? room,
    DateTime? lastConnected,
    bool? isFavorite,
  }) => DeviceRecord(
    id: id,
    name: name ?? this.name,
    protocol: protocol,
    manufacturer: manufacturer,
    model: model ?? this.model,
    ipAddress: ipAddress ?? this.ipAddress,
    macAddress: macAddress ?? this.macAddress,
    room: room ?? this.room,
    lastConnected: lastConnected ?? this.lastConnected,
    isFavorite: isFavorite ?? this.isFavorite,
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'name': name,
    'manufacturer': manufacturer,
    'model': model,
    'protocol': protocol,
    'ip_address': ipAddress,
    'mac_address': macAddress,
    'room': room,
    'last_connected': lastConnected?.millisecondsSinceEpoch,
    'is_favorite': isFavorite ? 1 : 0,
  };

  factory DeviceRecord.fromMap(Map<String, Object?> map) {
    final last = map['last_connected'] as int?;
    return DeviceRecord(
      id: map['id']! as String,
      name: map['name']! as String,
      protocol: map['protocol']! as String,
      manufacturer: map['manufacturer'] as String?,
      model: map['model'] as String?,
      ipAddress: map['ip_address'] as String?,
      macAddress: map['mac_address'] as String?,
      room: map['room'] as String?,
      lastConnected: last == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(last),
      isFavorite: (map['is_favorite'] as int? ?? 0) == 1,
    );
  }
}

class RemotePreferences {
  const RemotePreferences({
    required this.deviceId,
    this.layout = 'standard',
    this.hapticsEnabled = true,
    this.keyboardAutoOpen = true,
  });

  final String deviceId;
  final String layout;
  final bool hapticsEnabled;
  final bool keyboardAutoOpen;

  RemotePreferences copyWith({
    String? layout,
    bool? hapticsEnabled,
    bool? keyboardAutoOpen,
  }) => RemotePreferences(
    deviceId: deviceId,
    layout: layout ?? this.layout,
    hapticsEnabled: hapticsEnabled ?? this.hapticsEnabled,
    keyboardAutoOpen: keyboardAutoOpen ?? this.keyboardAutoOpen,
  );

  Map<String, Object?> toMap() => {
    'device_id': deviceId,
    'layout': layout,
    'haptics_enabled': hapticsEnabled ? 1 : 0,
    'keyboard_auto_open': keyboardAutoOpen ? 1 : 0,
  };

  factory RemotePreferences.fromMap(Map<String, Object?> map) =>
      RemotePreferences(
        deviceId: map['device_id']! as String,
        layout: map['layout'] as String? ?? 'standard',
        hapticsEnabled: (map['haptics_enabled'] as int? ?? 1) == 1,
        keyboardAutoOpen: (map['keyboard_auto_open'] as int? ?? 1) == 1,
      );
}
