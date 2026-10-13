import 'dart:async';
import 'dart:io';

import 'package:multicast_dns/multicast_dns.dart';

import 'multicast_lock.dart';

/// One DNS-SD service instance resolved to an address.
class MdnsService {
  const MdnsService({
    required this.instanceName,
    required this.host,
    required this.address,
    required this.port,
  });

  /// Human-readable instance name, e.g. "Living Room TV".
  final String instanceName;
  final String host;
  final InternetAddress address;
  final int port;
}

/// Browses for a DNS-SD service type such as `_androidtvremote2._tcp`.
///
/// iOS: the service type must be listed in NSBonjourServices, and raw
/// multicast also needs the multicast entitlement.
class MdnsBrowser {
  MdnsBrowser({MDnsClient Function()? clientFactory})
    : _clientFactory = clientFactory ?? MDnsClient.new;

  final MDnsClient Function() _clientFactory;

  static String instanceNameOf(String domainName, String serviceType) {
    final suffix = '.$serviceType.local';
    final name = domainName.endsWith(suffix)
        ? domainName.substring(0, domainName.length - suffix.length)
        : domainName;
    // DNS-SD escapes spaces and dots in instance names.
    return name
        .replaceAll(r'\032', ' ')
        .replaceAll(r'\.', '.')
        .replaceAll(r'\', '');
  }

  Stream<MdnsService> browse(
    String serviceType, {
    Duration timeout = const Duration(seconds: 5),
  }) {
    final controller = StreamController<MdnsService>();
    controller.onListen = () {
      MulticastLock.hold(() async {
        final client = _clientFactory();
        try {
          await client.start();
          final seen = <String>{};
          final ptrName = '$serviceType.local';
          await for (final ptr in client.lookup<PtrResourceRecord>(
            ResourceRecordQuery.serverPointer(ptrName),
            timeout: timeout,
          )) {
            if (!seen.add(ptr.domainName)) continue;
            await for (final srv in client.lookup<SrvResourceRecord>(
              ResourceRecordQuery.service(ptr.domainName),
              timeout: const Duration(seconds: 2),
            )) {
              await for (final ip in client.lookup<IPAddressResourceRecord>(
                ResourceRecordQuery.addressIPv4(srv.target),
                timeout: const Duration(seconds: 2),
              )) {
                if (controller.isClosed) return;
                controller.add(
                  MdnsService(
                    instanceName: instanceNameOf(ptr.domainName, serviceType),
                    host: srv.target,
                    address: ip.address,
                    port: srv.port,
                  ),
                );
                break;
              }
              break;
            }
          }
        } on SocketException catch (e) {
          if (!controller.isClosed) controller.addError(e);
        } finally {
          client.stop();
          if (!controller.isClosed) await controller.close();
        }
      });
    };
    return controller.stream;
  }
}
