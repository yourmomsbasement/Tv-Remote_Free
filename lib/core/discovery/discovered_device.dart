import '../storage/device_record.dart';

/// A TV found on the network (or entered manually) but not necessarily saved.
class DiscoveredDevice {
  const DiscoveredDevice({
    required this.id,
    required this.name,
    required this.protocol,
    required this.ipAddress,
    this.manufacturer,
    this.model,
    this.macAddress,
  });

  final String id;
  final String name;
  final String protocol;
  final String ipAddress;
  final String? manufacturer;
  final String? model;
  final String? macAddress;

  DeviceRecord toRecord() => DeviceRecord(
    id: id,
    name: name,
    protocol: protocol,
    manufacturer: manufacturer,
    model: model,
    ipAddress: ipAddress,
    macAddress: macAddress,
  );
}
