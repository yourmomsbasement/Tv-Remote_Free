import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:pointycastle/asn1.dart';

/// The client identity the TV remembers after pairing.
class AtvCredential {
  const AtvCredential({
    required this.certificatePem,
    required this.privateKeyPem,
    required this.serverCertificateSha256,
  });

  final String certificatePem;
  final String privateKeyPem;

  /// Fingerprint of the TV's certificate, captured during PIN-authenticated
  /// pairing and pinned for every later connection.
  final String serverCertificateSha256;

  String encode() => jsonEncode({
    'v': 1,
    'cert': certificatePem,
    'key': privateKeyPem,
    'server_sha256': serverCertificateSha256,
  });

  static AtvCredential? tryDecode(String? value) {
    if (value == null) return null;
    try {
      final map = jsonDecode(value) as Map<String, dynamic>;
      return AtvCredential(
        certificatePem: map['cert'] as String,
        privateKeyPem: map['key'] as String,
        serverCertificateSha256: map['server_sha256'] as String,
      );
    } on Object {
      return null;
    }
  }
}

class ClientIdentity {
  const ClientIdentity(this.certificatePem, this.privateKeyPem);
  final String certificatePem;
  final String privateKeyPem;
}

abstract final class AtvCrypto {
  /// Generates an RSA key and self-signed certificate off the UI thread.
  /// 2048-bit keygen in pure Dart can take a few seconds on a phone.
  static Future<ClientIdentity> generateIdentity({int keySize = 2048}) =>
      Isolate.run(() => _generate(keySize));

  static ClientIdentity _generate(int keySize) {
    final pair = CryptoUtils.generateRSAKeyPair(keySize: keySize);
    final privateKey = pair.privateKey as RSAPrivateKey;
    final publicKey = pair.publicKey as RSAPublicKey;
    final csr = X509Utils.generateRsaCsrPem(
      {'CN': 'atvremote'},
      privateKey,
      publicKey,
    );
    final cert = X509Utils.generateSelfSignedCertificate(
      privateKey,
      csr,
      3650,
      serialNumber: '${DateTime.now().millisecondsSinceEpoch}',
    );
    return ClientIdentity(
      cert,
      CryptoUtils.encodeRSAPrivateKeyToPemPkcs1(privateKey),
    );
  }

  static String sha256Hex(List<int> bytes) =>
      crypto.sha256.convert(bytes).toString();

  /// RSA public key from a DER-encoded X.509 certificate.
  static RSAPublicKey publicKeyFromCertificateDer(Uint8List der) {
    final certificate = ASN1Parser(der).nextObject() as ASN1Sequence;
    final tbs = certificate.elements![0] as ASN1Sequence;
    // tbsCertificate: [0] version (optional), serial, signature, issuer,
    // validity, subject, subjectPublicKeyInfo, ...
    final hasVersion = tbs.elements![0].tag == 0xA0;
    final spki = tbs.elements![hasVersion ? 6 : 5] as ASN1Sequence;
    return CryptoUtils.rsaPublicKeyFromDERBytes(spki.encodedBytes!);
  }

  static RSAPublicKey publicKeyFromCertificatePem(String pem) =>
      publicKeyFromCertificateDer(CryptoUtils.getBytesFromPEMString(pem));

  /// Minimal big-endian bytes of [value] (as Python's bytes.fromhex(f"{n:X}")).
  static Uint8List _unsigned(BigInt value) {
    var hex = value.toRadixString(16);
    if (hex.length.isOdd) hex = '0$hex';
    return Uint8List.fromList([
      for (var i = 0; i < hex.length; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16),
    ]);
  }

  static bool isValidPin(String pin) =>
      RegExp(r'^[0-9A-Fa-f]{6}$').hasMatch(pin);

  /// The pairing secret: SHA-256 over both public keys and the last four hex
  /// digits of the PIN. The PIN's first byte must equal the hash's first
  /// byte, which lets us reject a mistyped PIN before sending anything.
  ///
  /// Returns null if [pin] does not match these keys.
  static Uint8List? pairingSecret({
    required RSAPublicKey client,
    required RSAPublicKey server,
    required String pin,
  }) {
    if (!isValidPin(pin)) return null;
    final digest = crypto.sha256.convert([
      ..._unsigned(client.modulus!),
      ..._unsigned(client.exponent!),
      ..._unsigned(server.modulus!),
      ..._unsigned(server.exponent!),
      int.parse(pin.substring(2, 4), radix: 16),
      int.parse(pin.substring(4, 6), radix: 16),
    ]).bytes;
    if (digest[0] != int.parse(pin.substring(0, 2), radix: 16)) return null;
    return Uint8List.fromList(digest);
  }

  /// The PIN a TV would display for these keys and nonce (for tests and the
  /// mock TV): first byte of the hash followed by the 2-byte nonce.
  static String pinFor({
    required RSAPublicKey client,
    required RSAPublicKey server,
    required int nonce,
  }) {
    final nonceHex = nonce.toRadixString(16).padLeft(4, '0');
    final digest = crypto.sha256.convert([
      ..._unsigned(client.modulus!),
      ..._unsigned(client.exponent!),
      ..._unsigned(server.modulus!),
      ..._unsigned(server.exponent!),
      int.parse(nonceHex.substring(0, 2), radix: 16),
      int.parse(nonceHex.substring(2), radix: 16),
    ]).bytes;
    return (digest[0].toRadixString(16).padLeft(2, '0') + nonceHex)
        .toUpperCase();
  }
}
