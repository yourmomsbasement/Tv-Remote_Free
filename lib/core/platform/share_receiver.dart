import 'package:flutter/services.dart';

/// Receives text shared into the app from other apps (Android share sheet;
/// see MainActivity.kt). A no-op where the native side is absent.
abstract final class ShareReceiver {
  static const _channel = MethodChannel('tv_remote_free/share');

  /// Calls [onShared] for the share that launched the app, if any, and for
  /// every later share while it runs.
  static Future<void> listen(void Function(String text) onShared) async {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'shared' && call.arguments is String) {
        onShared(call.arguments as String);
      }
    });
    try {
      final pending = await _channel.invokeMethod<String>('takePending');
      if (pending != null && pending.isNotEmpty) onShared(pending);
    } on MissingPluginException {
      // iOS and tests: sharing into the app is not wired up there.
    } on PlatformException {
      // Ignore; sharing is a convenience.
    }
  }
}
