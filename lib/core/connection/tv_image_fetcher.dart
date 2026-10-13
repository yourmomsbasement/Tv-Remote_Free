import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

/// Downloads small images (app icons) served by a TV.
///
/// TVs serve these over plain HTTP or over HTTPS with a self-signed
/// certificate. The certificate is accepted only for the TV's own address,
/// never for any other host.
class TvImageFetcher {
  TvImageFetcher(
    this.host, {
    this.timeout = const Duration(seconds: 4),
    this.maxBytes = 2 * 1024 * 1024,
  });

  final String host;
  final Duration timeout;
  final int maxBytes;

  late final HttpClient _client = HttpClient()
    ..connectionTimeout = timeout
    ..badCertificateCallback = (cert, certHost, port) => certHost == host;

  /// Returns the first candidate that downloads as an image, or null.
  Future<Uint8List?> fetchFirst(Iterable<Uri> candidates) async {
    for (final uri in candidates) {
      // Only ever talk to the TV itself.
      if (uri.host != host) continue;
      final bytes = await _fetch(uri);
      if (bytes != null) return bytes;
    }
    return null;
  }

  Future<Uint8List?> _fetch(Uri uri) async {
    try {
      final request = await _client.getUrl(uri).timeout(timeout);
      final response = await request.close().timeout(timeout);
      final type = response.headers.contentType;
      if (response.statusCode != 200 ||
          (type != null && type.primaryType != 'image')) {
        await response.drain<void>();
        return null;
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(timeout)) {
        builder.add(chunk);
        if (builder.length > maxBytes) return null;
      }
      final bytes = builder.takeBytes();
      return bytes.isEmpty ? null : bytes;
    } on Object {
      return null;
    }
  }

  void close() => _client.close(force: true);
}
