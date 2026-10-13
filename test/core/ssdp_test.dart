import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_remote_free/core/discovery/ssdp.dart';

void main() {
  final address = InternetAddress('192.168.1.40');

  test('parses headers case-insensitively', () {
    final response = SsdpResponse.parse(
      'HTTP/1.1 200 OK\r\n'
      'Cache-Control: max-age=3600\r\n'
      'ST: roku:ecp\r\n'
      'Location: http://192.168.1.40:8060/\r\n'
      'USN: uuid:roku:ecp:X0123\r\n\r\n',
      address,
    )!;
    expect(response.st, 'roku:ecp');
    expect(response.location, 'http://192.168.1.40:8060/');
    expect(response.usn, 'uuid:roku:ecp:X0123');
    expect(response.address, address);
  });

  test('ignores other SSDP traffic such as NOTIFY and M-SEARCH', () {
    expect(
      SsdpResponse.parse('NOTIFY * HTTP/1.1\r\nNT: x\r\n\r\n', address),
      isNull,
    );
    expect(
      SsdpResponse.parse(SsdpClient.searchMessage('roku:ecp'), address),
      isNull,
    );
  });

  test('builds a valid M-SEARCH request', () {
    final message = SsdpClient.searchMessage('roku:ecp', mx: 3);
    expect(message, startsWith('M-SEARCH * HTTP/1.1\r\n'));
    expect(message, contains('MAN: "ssdp:discover"\r\n'));
    expect(message, contains('ST: roku:ecp\r\n'));
    expect(message, contains('MX: 3\r\n'));
    expect(message, endsWith('\r\n\r\n'));
  });
}
