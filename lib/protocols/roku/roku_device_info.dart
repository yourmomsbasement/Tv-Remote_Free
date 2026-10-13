import 'package:xml/xml.dart';

/// Fields of interest from `GET /query/device-info`.
class RokuDeviceInfo {
  const RokuDeviceInfo({
    required this.serialNumber,
    this.friendlyName,
    this.modelName,
    this.vendorName,
    this.isTv = false,
    this.supportsSuspend = false,
    this.supportsWakeOnWlan = false,
    this.wifiMac,
    this.ethernetMac,
    this.ecpSettingMode,
  });

  final String serialNumber;
  final String? friendlyName;
  final String? modelName;
  final String? vendorName;
  final bool isTv;
  final bool supportsSuspend;
  final bool supportsWakeOnWlan;
  final String? wifiMac;
  final String? ethernetMac;

  /// "default", "permissive", "limited" or "disabled" when reported.
  final String? ecpSettingMode;

  bool get isLimited =>
      ecpSettingMode == 'limited' || ecpSettingMode == 'disabled';

  static RokuDeviceInfo parse(String xmlText) {
    final root = XmlDocument.parse(xmlText).rootElement;
    String? text(String name) {
      final value = root.getElement(name)?.innerText.trim();
      return value == null || value.isEmpty ? null : value;
    }

    bool flag(String name) => text(name) == 'true';

    final serial = text('serial-number') ?? text('device-id');
    if (serial == null) {
      throw const FormatException('device-info has no serial-number');
    }
    return RokuDeviceInfo(
      serialNumber: serial,
      friendlyName:
          text('user-device-name') ??
          text('friendly-device-name') ??
          text('default-device-name'),
      modelName: text('friendly-model-name') ?? text('model-name'),
      vendorName: text('vendor-name'),
      isTv: flag('is-tv'),
      supportsSuspend: flag('supports-suspend'),
      supportsWakeOnWlan: flag('supports-wake-on-wlan'),
      wifiMac: text('wifi-mac'),
      ethernetMac: text('ethernet-mac'),
      ecpSettingMode: text('ecp-setting-mode'),
    );
  }
}
