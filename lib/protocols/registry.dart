import '../core/adapter/protocol_driver.dart';
import 'lg_webos/webos_driver.dart';
import 'roku/roku_driver.dart';

/// Protocols supported by this build, in discovery priority order.
List<ProtocolDriver> defaultDrivers() => [RokuDriver(), WebOsDriver()];
