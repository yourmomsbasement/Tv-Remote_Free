import 'dart:io';
import 'dart:typed_data';

/// Builds and sends Wake-on-LAN magic packets.
class WakeOnLan {
  static final _macPattern = RegExp(
    r'^([0-9A-Fa-f]{2})([:-]?[0-9A-Fa-f]{2}){5}$',
  );

  static bool isValidMac(String mac) => _macPattern.hasMatch(mac.trim());

  /// 6 bytes of 0xFF followed by the MAC address repeated 16 times.
  static Uint8List magicPacket(String mac) {
    if (!isValidMac(mac)) {
      throw ArgumentError.value(mac, 'mac', 'Invalid MAC address');
    }
    final hex = mac.replaceAll(RegExp(r'[:-]'), '');
    final macBytes = [
      for (var i = 0; i < 12; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16),
    ];
    return Uint8List.fromList([
      ...List.filled(6, 0xFF),
      for (var i = 0; i < 16; i++) ...macBytes,
    ]);
  }

  /// Broadcasts the magic packet on the local network (ports 9 and 7).
  static Future<void> send(String mac, {InternetAddress? broadcast}) async {
    final packet = magicPacket(mac);
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    try {
      socket.broadcastEnabled = true;
      final target = broadcast ?? InternetAddress('255.255.255.255');
      for (var i = 0; i < 3; i++) {
        socket.send(packet, target, 9);
        socket.send(packet, target, 7);
      }
    } finally {
      socket.close();
    }
  }
}
