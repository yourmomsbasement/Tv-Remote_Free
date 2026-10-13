import 'package:flutter_test/flutter_test.dart';
import 'package:tv_remote_free/protocols/android_tv/atv_messages.dart';
import 'package:tv_remote_free/protocols/android_tv/protobuf.dart';

void main() {
  test('round-trips varints, strings and nested messages', () {
    final bytes =
        (ProtoWriter()
              ..varint(1, 300)
              ..string(2, 'héllo')
              ..message(3, ProtoWriter()..varint(1, 7))
              ..message(3, ProtoWriter()..varint(1, 8)))
            .toBytes();
    final m = ProtoMessage.decode(bytes);
    expect(m.integer(1), 300);
    expect(m.string(2), 'héllo');
    expect(m.messages(3).map((e) => e.integer(1)), [7, 8]);
    expect(m.has(4), isFalse);
  });

  test('encodes like protoc for a key press', () {
    // remote_key_inject { key_code: KEYCODE_DPAD_UP direction: SHORT }
    expect(RemoteMsg.key(19).toBytes(), [0x52, 0x04, 0x08, 0x13, 0x10, 0x03]);
  });

  test('encodes like protoc for the pairing request', () {
    final bytes = Polo.pairingRequestMessage('X').toBytes();
    // protocol_version 2, status 200, pairing_request{service "atvremote", client "X"}
    expect(bytes, [
      0x08, 0x02, 0x10, 0xC8, 0x01, //
      0x52, 0x0E, 0x0A, 0x09, ...'atvremote'.codeUnits, 0x12, 0x01, 0x58,
    ]);
  });

  test('frame decoder handles chunks split anywhere', () {
    final a = (ProtoWriter()..string(1, 'a' * 200)).toFrame();
    final b = (ProtoWriter()..varint(1, 1)).toFrame();
    final stream = [...a, ...b];
    final decoder = ProtoFrameDecoder();
    final frames = [
      for (var i = 0; i < stream.length; i++) ...decoder.add([stream[i]]),
    ];
    expect(frames, hasLength(2));
    expect(ProtoMessage.decode(frames[0]).string(1), 'a' * 200);
    expect(ProtoMessage.decode(frames[1]).integer(1), 1);
  });

  test('IME edit puts the cursor at the end of the value', () {
    final m = ProtoMessage.decode(
      RemoteMsg.imeText(
        imeCounter: 3,
        fieldCounter: 4,
        value: 'ab😀',
      ).toBytes(),
    );
    final edit = m.message(RemoteMsg.imeBatchEdit)!;
    expect(edit.integer(1), 3);
    expect(edit.integer(2), 4);
    final object = edit.messages(3).single.message(2)!;
    expect(object.integer(1), 2);
    expect(object.integer(2), 2);
    expect(object.string(3), 'ab😀');
  });

  test('rejects truncated input', () {
    expect(
      () => ProtoMessage.decode([0x0A, 0x05, 0x01]),
      throwsFormatException,
    );
  });
}
