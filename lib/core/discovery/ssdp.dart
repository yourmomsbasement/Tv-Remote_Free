import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// A parsed SSDP M-SEARCH response.
class SsdpResponse {
  const SsdpResponse({required this.address, required this.headers});

  final InternetAddress address;

  /// Header names are lower-cased.
  final Map<String, String> headers;

  String? get st => headers['st'];
  String? get usn => headers['usn'];
  String? get location => headers['location'];
  String? get server => headers['server'];

  /// Parses a raw datagram. Returns null for anything that is not a
  /// successful HTTP-over-UDP response.
  static SsdpResponse? parse(String raw, InternetAddress address) {
    final lines = const LineSplitter().convert(raw);
    if (lines.isEmpty ||
        !lines.first.toUpperCase().startsWith('HTTP/1.1 200')) {
      return null;
    }
    final headers = <String, String>{};
    for (final line in lines.skip(1)) {
      final colon = line.indexOf(':');
      if (colon <= 0) continue;
      headers[line.substring(0, colon).trim().toLowerCase()] = line
          .substring(colon + 1)
          .trim();
    }
    return SsdpResponse(address: address, headers: headers);
  }
}

/// Minimal SSDP client: multicasts M-SEARCH requests and streams unicast
/// responses until [timeout] elapses.
///
/// iOS: sending multicast requires the com.apple.developer.networking.multicast
/// entitlement plus NSLocalNetworkUsageDescription.
class SsdpClient {
  static final multicastAddress = InternetAddress('239.255.255.250');
  static const multicastPort = 1900;

  static String searchMessage(String searchTarget, {int mx = 2}) => [
    'M-SEARCH * HTTP/1.1',
    'HOST: 239.255.255.250:1900',
    'MAN: "ssdp:discover"',
    'MX: $mx',
    'ST: $searchTarget',
    '',
    '',
  ].join('\r\n');

  Stream<SsdpResponse> search(
    List<String> searchTargets, {
    Duration timeout = const Duration(seconds: 4),
  }) {
    late StreamController<SsdpResponse> controller;
    RawDatagramSocket? socket;
    Timer? stopTimer;
    final resendTimers = <Timer>[];

    Future<void> stop() async {
      stopTimer?.cancel();
      for (final t in resendTimers) {
        t.cancel();
      }
      socket?.close();
      socket = null;
      if (!controller.isClosed) await controller.close();
    }

    void sendAll() {
      for (final st in searchTargets) {
        socket?.send(
          utf8.encode(searchMessage(st)),
          multicastAddress,
          multicastPort,
        );
      }
    }

    controller = StreamController<SsdpResponse>(
      onListen: () async {
        try {
          socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
        } on SocketException catch (e) {
          controller.addError(e);
          await stop();
          return;
        }
        socket!
          ..multicastHops = 4
          ..listen((event) {
            if (event != RawSocketEvent.read) return;
            final datagram = socket?.receive();
            if (datagram == null) return;
            final response = SsdpResponse.parse(
              utf8.decode(datagram.data, allowMalformed: true),
              datagram.address,
            );
            if (response != null && !controller.isClosed) {
              controller.add(response);
            }
          });
        // UDP is lossy; repeat the search a couple of times.
        sendAll();
        resendTimers
          ..add(Timer(const Duration(milliseconds: 600), sendAll))
          ..add(Timer(const Duration(milliseconds: 1500), sendAll));
        stopTimer = Timer(timeout, stop);
      },
      onCancel: stop,
    );
    return controller.stream;
  }
}
