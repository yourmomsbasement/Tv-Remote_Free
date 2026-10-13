import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_remote_free/core/connection/tv_image_fetcher.dart';
import 'package:tv_remote_free/protocols/android_tv/atv_crypto.dart';
import 'package:tv_remote_free/protocols/lg_webos/webos_adapter.dart';

final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 1, 2, 3]);

void serve(HttpServer server) => server.listen((req) async {
  if (req.uri.path == '/icon.png') {
    req.response.headers.contentType = ContentType('image', 'png');
    req.response.add(png);
  } else if (req.uri.path == '/page') {
    req.response.headers.contentType = ContentType.html;
    req.response.write('<html>');
  } else {
    req.response.statusCode = 404;
  }
  await req.response.close();
});

void main() {
  test('downloads an icon over plain HTTP', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    serve(server);
    final fetcher = TvImageFetcher('127.0.0.1');
    final bytes = await fetcher.fetchFirst([
      Uri.parse('http://127.0.0.1:${server.port}/missing.png'),
      Uri.parse('http://127.0.0.1:${server.port}/page'), // not an image
      Uri.parse('http://127.0.0.1:${server.port}/icon.png'),
    ]);
    expect(bytes, png);
    fetcher.close();
    await server.close(force: true);
  });

  test("accepts the TV's self-signed certificate, only for the TV", () async {
    final identity = await AtvCrypto.generateIdentity(keySize: 1024);
    final context = SecurityContext()
      ..useCertificateChainBytes(identity.certificatePem.codeUnits)
      ..usePrivateKeyBytes(identity.privateKeyPem.codeUnits);
    final server = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      context,
    );
    serve(server);
    final url = Uri.parse('https://127.0.0.1:${server.port}/icon.png');

    final tvFetcher = TvImageFetcher('127.0.0.1');
    expect(await tvFetcher.fetchFirst([url]), png);
    tvFetcher.close();

    // A fetcher for a different TV never contacts this host.
    final other = TvImageFetcher('192.0.2.1');
    expect(await other.fetchFirst([url]), isNull);
    other.close();
    await server.close(force: true);
  });

  test(
    'webOS icon URLs: relative paths, both ports, foreign hosts dropped',
    () {
      final candidates = WebOsAdapter.iconCandidates('10.0.0.5', [
        'http://10.0.0.5:3000/resources/abc/large.png',
        '/resources/abc/icon.png',
        'resources/abc/rel.png',
        'https://evil.example/x.png',
        'http://10.0.0.5:3000/resources/abc/large.png', // duplicate
      ]).map((u) => u.toString());
      expect(candidates, [
        'http://10.0.0.5:3000/resources/abc/large.png',
        'https://10.0.0.5:3001/resources/abc/large.png',
        'https://10.0.0.5:3001/resources/abc/icon.png',
        'http://10.0.0.5:3000/resources/abc/icon.png',
        'https://10.0.0.5:3001/resources/abc/rel.png',
        'http://10.0.0.5:3000/resources/abc/rel.png',
      ]);
    },
  );
}
