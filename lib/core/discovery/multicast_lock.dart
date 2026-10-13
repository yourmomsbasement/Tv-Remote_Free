import 'dart:io';

import 'package:flutter/services.dart';

/// Android drops incoming multicast packets (mDNS answers) unless the app
/// holds a Wi-Fi MulticastLock. Implemented in MainActivity.kt; a no-op on
/// other platforms and in tests.
abstract final class MulticastLock {
  static const _channel = MethodChannel('tv_remote_free/multicast');

  static Future<T> hold<T>(Future<T> Function() body) async {
    final android = Platform.isAndroid;
    if (android) await _invoke('acquire');
    try {
      return await body();
    } finally {
      if (android) await _invoke('release');
    }
  }

  static Future<void> _invoke(String method) async {
    try {
      await _channel.invokeMethod<void>(method);
    } on MissingPluginException {
      // Running without the native side (tests); discovery still works on
      // networks that deliver multicast anyway.
    } on PlatformException {
      // Lock unavailable; continue best-effort.
    }
  }
}
