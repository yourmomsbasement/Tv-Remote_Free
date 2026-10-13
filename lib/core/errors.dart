/// Structured errors raised by adapters and the unified controller.
///
/// Adapters must throw [TvRemoteException] instead of failing silently so the
/// UI can explain exactly why an action did not reach the TV.
enum TvErrorCode {
  /// The connected device does not support this operation.
  unsupported,

  /// No active connection to the device.
  notConnected,

  /// The device could not be reached on the local network.
  unreachable,

  /// The TV rejected or cancelled the pairing request.
  pairingRejected,

  /// The stored credential is no longer accepted; the user must pair again.
  pairingRequired,

  /// The device refused the command (e.g. Roku "Control by mobile apps" off).
  forbidden,

  /// The device answered with something the adapter did not understand.
  protocol,

  /// The operation did not complete in time.
  timeout,
}

class TvRemoteException implements Exception {
  const TvRemoteException(this.code, this.message, {this.cause});

  const TvRemoteException.unsupported(String operation)
    : this(TvErrorCode.unsupported, '$operation is not supported by this TV');

  const TvRemoteException.notConnected()
    : this(TvErrorCode.notConnected, 'Not connected to a TV');

  final TvErrorCode code;
  final String message;
  final Object? cause;

  @override
  String toString() => 'TvRemoteException(${code.name}): $message';
}
