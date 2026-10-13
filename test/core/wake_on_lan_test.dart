import 'package:flutter_test/flutter_test.dart';
import 'package:tv_remote_free/core/connection/backoff.dart';
import 'package:tv_remote_free/core/connection/wake_on_lan.dart';

void main() {
  test('magic packet is 6x FF followed by the MAC 16 times', () {
    final packet = WakeOnLan.magicPacket('78:5D:C8:00:11:22');
    expect(packet.length, 102);
    expect(packet.sublist(0, 6), List.filled(6, 0xFF));
    for (var i = 0; i < 16; i++) {
      expect(packet.sublist(6 + i * 6, 12 + i * 6), [
        0x78,
        0x5D,
        0xC8,
        0x00,
        0x11,
        0x22,
      ]);
    }
  });

  test('accepts common MAC formats and rejects junk', () {
    expect(WakeOnLan.isValidMac('78:5d:c8:00:11:22'), isTrue);
    expect(WakeOnLan.isValidMac('78-5d-c8-00-11-22'), isTrue);
    expect(WakeOnLan.isValidMac('785dc8001122'), isTrue);
    expect(WakeOnLan.isValidMac('78:5d:c8:00:11'), isFalse);
    expect(WakeOnLan.isValidMac('zz:5d:c8:00:11:22'), isFalse);
    expect(() => WakeOnLan.magicPacket('nope'), throwsArgumentError);
  });

  test('backoff grows exponentially up to the cap', () {
    final backoff = Backoff(
      initial: const Duration(seconds: 1),
      max: const Duration(seconds: 8),
    );
    final delays = [for (var i = 0; i < 6; i++) backoff.next().inMilliseconds];
    final expected = [1000, 2000, 4000, 8000, 8000, 8000];
    for (var i = 0; i < delays.length; i++) {
      expect(delays[i], inInclusiveRange(expected[i] * 0.8, expected[i] * 1.2));
    }
    backoff.reset();
    expect(backoff.next().inMilliseconds, inInclusiveRange(800, 1200));
  });
}
