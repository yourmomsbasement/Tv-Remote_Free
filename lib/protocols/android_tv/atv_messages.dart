import 'protobuf.dart';

/// Pairing ("polo") protocol on port 6467. Field numbers follow polo.proto.
abstract final class Polo {
  static const statusOk = 200;
  static const encodingHexadecimal = 3;
  static const roleInput = 1;
  static const pinLength = 6;

  // OuterMessage fields.
  static const protocolVersion = 1;
  static const status = 2;
  static const pairingRequest = 10;
  static const pairingRequestAck = 11;
  static const options = 20;
  static const configuration = 30;
  static const configurationAck = 31;
  static const secret = 40;
  static const secretAck = 41;

  static ProtoWriter _outer() => ProtoWriter()
    ..varint(protocolVersion, 2)
    ..varint(status, statusOk);

  static ProtoWriter _encoding() => ProtoWriter()
    ..varint(1, encodingHexadecimal)
    ..varint(2, pinLength);

  static ProtoWriter pairingRequestMessage(String clientName) => _outer()
    ..message(
      pairingRequest,
      ProtoWriter()
        ..string(1, 'atvremote')
        ..string(2, clientName),
    );

  static ProtoWriter optionsMessage() => _outer()
    ..message(
      options,
      ProtoWriter()
        ..message(1, _encoding())
        ..varint(3, roleInput),
    );

  static ProtoWriter configurationMessage() => _outer()
    ..message(
      configuration,
      ProtoWriter()
        ..message(1, _encoding())
        ..varint(2, roleInput),
    );

  static ProtoWriter secretMessage(List<int> secretBytes) =>
      _outer()..message(secret, ProtoWriter()..bytes(1, secretBytes));
}

/// Remote protocol on port 6466. Field numbers follow remotemessage.proto.
abstract final class RemoteMsg {
  // RemoteMessage fields.
  static const configure = 1;
  static const setActive = 2;
  static const error = 3;
  static const pingRequest = 8;
  static const pingResponse = 9;
  static const keyInject = 10;
  static const imeKeyInject = 20;
  static const imeBatchEdit = 21;
  static const imeShowRequest = 22;
  static const start = 40;
  static const setVolumeLevel = 50;
  static const appLinkLaunch = 90;

  static const directionShort = 3;

  static ProtoWriter configureReply(int features) => ProtoWriter()
    ..message(
      configure,
      ProtoWriter()
        ..varint(1, features)
        ..message(
          2,
          ProtoWriter()
            ..varint(3, 1)
            ..string(4, '1')
            ..string(5, 'atvremote')
            ..string(6, '1.0.0'),
        ),
    );

  static ProtoWriter setActiveReply(int features) =>
      ProtoWriter()..message(setActive, ProtoWriter()..varint(1, features));

  static ProtoWriter pingReply(int value) =>
      ProtoWriter()..message(pingResponse, ProtoWriter()..varint(1, value));

  static ProtoWriter key(int keyCode) => ProtoWriter()
    ..message(
      keyInject,
      ProtoWriter()
        ..varint(1, keyCode)
        ..varint(2, directionShort),
    );

  static ProtoWriter appLink(String link) =>
      ProtoWriter()..message(appLinkLaunch, ProtoWriter()..string(1, link));

  /// Sets the focused field's content to [value], cursor at the end.
  static ProtoWriter imeText({
    required int imeCounter,
    required int fieldCounter,
    required String value,
  }) {
    final cursor = value.runes.length - 1;
    return ProtoWriter()..message(
      imeBatchEdit,
      ProtoWriter()
        ..varint(1, imeCounter)
        ..varint(2, fieldCounter)
        ..message(
          3,
          ProtoWriter()
            ..varint(1, 1)
            ..message(
              2,
              ProtoWriter()
                ..varint(1, cursor)
                ..varint(2, cursor)
                ..string(3, value),
            ),
        ),
    );
  }
}

/// Feature bits negotiated in RemoteConfigure / RemoteSetActive.
abstract final class AtvFeature {
  static const ping = 1 << 0;
  static const key = 1 << 1;
  static const ime = 1 << 2;
  static const power = 1 << 5;
  static const volume = 1 << 6;
  static const appLink = 1 << 9;

  static const requested = ping | key | ime | power | volume | appLink;
}
