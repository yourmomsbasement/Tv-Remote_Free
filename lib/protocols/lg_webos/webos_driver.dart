import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import '../../core/adapter/protocol_driver.dart';
import '../../core/adapter/smart_tv_adapter.dart';
import '../../core/discovery/discovered_device.dart';
import '../../core/discovery/ssdp.dart';
import '../../core/errors.dart';
import '../../core/storage/device_record.dart';
import 'webos_adapter.dart';

class WebOsDriver implements ProtocolDriver {
  WebOsDriver({http.Client Function()? clientFactory})
    : _clientFactory = clientFactory ?? http.Client.new;

  final http.Client Function() _clientFactory;

  static const searchTarget = 'urn:lge-com:service:webos-second-screen:1';

  @override
  String get protocol => Protocols.lgWebOs;

  @override
  String get displayName => 'LG webOS';

  @override
  List<String> get ssdpSearchTargets => const [searchTarget];

  @override
  bool matches(SsdpResponse response) =>
      response.st == searchTarget ||
      (response.usn?.contains('webos-second-screen') ?? false);

  @override
  Future<DiscoveredDevice?> describe(SsdpResponse response) async {
    final ip = response.address.address;
    var name = 'LG TV';
    String? model;
    var id = _uuid(response.usn);
    final location = Uri.tryParse(response.location ?? '');
    if (location != null && location.hasScheme) {
      final client = _clientFactory();
      try {
        final body =
            (await client.get(location).timeout(const Duration(seconds: 3)))
                .body;
        final description = parseDescription(body);
        name = description.friendlyName ?? name;
        model = description.modelName;
        id ??= description.udn;
      } on Exception {
        // The SSDP response alone is enough to offer the TV.
      } finally {
        client.close();
      }
    }
    return DiscoveredDevice(
      id: 'lg_webos:${id ?? ip}',
      name: name,
      protocol: protocol,
      ipAddress: ip,
      manufacturer: 'LG Electronics',
      model: model,
    );
  }

  static String? _uuid(String? usn) {
    final match = RegExp(r'uuid:([^:]+)').firstMatch(usn ?? '');
    return match?.group(1);
  }

  static ({String? friendlyName, String? modelName, String? udn})
  parseDescription(String xmlText) {
    final doc = XmlDocument.parse(xmlText);
    String? first(String name) {
      final value = doc.findAllElements(name).firstOrNull?.innerText.trim();
      return value == null || value.isEmpty ? null : value;
    }

    return (
      friendlyName: first('friendlyName'),
      modelName: first('modelName') ?? first('modelNumber'),
      udn: first('UDN')?.replaceFirst('uuid:', ''),
    );
  }

  /// Checks that a webOS API port is open without starting a pairing prompt.
  @override
  Future<DiscoveredDevice> probe(String ipAddress) async {
    for (final port in const [3001, 3000]) {
      try {
        final socket = await Socket.connect(
          ipAddress,
          port,
          timeout: const Duration(seconds: 2),
        );
        socket.destroy();
        return DiscoveredDevice(
          id: 'lg_webos:$ipAddress',
          name: 'LG TV ($ipAddress)',
          protocol: protocol,
          ipAddress: ipAddress,
          manufacturer: 'LG Electronics',
        );
      } on SocketException {
        continue;
      }
    }
    throw TvRemoteException(
      TvErrorCode.unreachable,
      'No LG webOS TV answered at $ipAddress. Check the address and that '
      'the TV is on.',
    );
  }

  @override
  SmartTVAdapter createAdapter(DeviceRecord device) =>
      WebOsAdapter(host: device.ipAddress!);
}
