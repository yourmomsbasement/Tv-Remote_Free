import 'dart:async';

import '../adapter/protocol_driver.dart';
import '../errors.dart';
import '../storage/device_record.dart';
import 'discovered_device.dart';
import 'ssdp.dart';

/// Finds supported TVs via each driver's discovery method, or by IP address.
class DiscoveryService {
  DiscoveryService(this.drivers, {SsdpClient? ssdp})
    : _ssdp = ssdp ?? SsdpClient();

  final List<ProtocolDriver> drivers;
  final SsdpClient _ssdp;

  /// Streams each newly identified device once, then closes after [timeout].
  Stream<DiscoveredDevice> scan({
    Duration timeout = const Duration(seconds: 5),
  }) async* {
    final targets = {for (final d in drivers) ...d.ssdpSearchTargets}.toList();
    final seenResponders = <String>{};
    final seenDevices = <String>{};
    final describing = <Future<DiscoveredDevice?>>[];
    final found = StreamController<DiscoveredDevice>();

    // Drivers with their own discovery (mDNS) run alongside SSDP.
    for (final driver in drivers) {
      describing.add(
        driver
            .discover(timeout: timeout)
            .forEach((device) {
              if (seenDevices.add(device.id)) found.add(device);
            })
            .then((_) => null, onError: (_) => null),
      );
    }

    final responses = targets.isEmpty
        ? const Stream<SsdpResponse>.empty()
        : _ssdp.search(targets, timeout: timeout);
    final sub = responses.listen(
      (response) {
        for (final driver in drivers) {
          if (!driver.matches(response)) continue;
          final key = '${driver.protocol}@${response.address.address}';
          if (!seenResponders.add(key)) continue;
          describing.add(
            driver.describe(response).then((device) {
              if (device != null && seenDevices.add(device.id)) {
                found.add(device);
              }
              return device;
            }, onError: (_) => null),
          );
        }
      },
      onError: found.addError,
      onDone: () async {
        await Future.wait(describing);
        await found.close();
      },
    );
    try {
      yield* found.stream;
    } finally {
      await sub.cancel();
    }
  }

  /// Identifies a TV by IP. With [protocol] null, each driver is tried.
  Future<DiscoveredDevice> probe(String ipAddress, {String? protocol}) async {
    final candidates = protocol == null
        ? drivers.where((d) => d.protocol != Protocols.demo).toList()
        : drivers.where((d) => d.protocol == protocol).toList();
    Object? lastError;
    for (final driver in candidates) {
      try {
        return await driver.probe(ipAddress);
      } on Object catch (e) {
        lastError = e;
      }
    }
    if (lastError is TvRemoteException) throw lastError;
    throw TvRemoteException(
      TvErrorCode.unreachable,
      'No supported TV found at $ipAddress',
      cause: lastError,
    );
  }

  ProtocolDriver driverFor(String protocol) => drivers.firstWhere(
    (d) => d.protocol == protocol,
    orElse: () => throw TvRemoteException(
      TvErrorCode.unsupported,
      'Unknown protocol "$protocol"',
    ),
  );
}
