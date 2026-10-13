import 'dart:convert';

import '../errors.dart';

/// What a custom command does, per TV system.
enum CustomCommandKind {
  /// Roku: an ECP key name (e.g. "InputHDMI2", "FindRemote").
  rokuKey('roku', 'ECP key'),

  /// Roku: launch a channel by id, optionally with deep-link parameters.
  rokuLaunch('roku', 'Launch channel'),

  /// LG webOS: an SSAP request (ssap:// URI plus JSON payload).
  webOsRequest('lg_webos', 'SSAP request'),

  /// LG webOS: a pointer-socket button name (e.g. "RED", "3D_MODE").
  webOsButton('lg_webos', 'Remote button'),

  /// Android TV: an Android key code (e.g. 183 for KEYCODE_PROG_RED).
  androidKeyCode('android_tv', 'Key code'),

  /// Android TV: an app link (https:// or a registered app scheme).
  androidLink('android_tv', 'App link'),

  /// Samsung Tizen: a key name (e.g. "KEY_HDMI2", "KEY_RED").
  samsungKey('samsung', 'Key name');

  const CustomCommandKind(this.protocol, this.label);

  final String protocol;
  final String label;

  static List<CustomCommandKind> forProtocol(String protocol) =>
      values.where((k) => k.protocol == protocol).toList();
}

/// A user-defined command bound to a custom button.
///
/// Only a fixed set of command kinds exists and every value is validated
/// before saving, importing and sending: no arbitrary URLs, hosts or HTTP
/// methods, and operations that change or remove things on the TV
/// (installing, deleting, resetting, re-pairing) are refused.
class CustomCommand {
  const CustomCommand({
    required this.id,
    required this.name,
    required this.kind,
    required this.value,
    this.params = const {},
  });

  final String id;
  final String name;
  final CustomCommandKind kind;

  /// Key name, channel id, SSAP URI, button name, key code or link.
  final String value;

  /// Roku launch parameters, or the SSAP JSON payload (as string values).
  final Map<String, Object?> params;

  String get protocol => kind.protocol;

  static const maxPayloadBytes = 4096;

  static final _rokuKey = RegExp(
    r'^(Lit_[^\s]{1,12}|[A-Za-z][A-Za-z0-9_]{0,40})$',
  );
  static final _rokuChannel = RegExp(r'^[A-Za-z0-9._-]{1,64}$');
  static final _paramName = RegExp(r'^[A-Za-z][A-Za-z0-9_]{0,40}$');
  static final _ssapUri = RegExp(
    r'^ssap://[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)+$',
  );
  static final _button = RegExp(r'^[A-Z0-9_]{1,32}$');
  static final _samsungKey = RegExp(r'^KEY_[A-Z0-9_]{1,40}$');
  static final _scheme = RegExp(r'^[a-z][a-z0-9+.-]{1,30}$');

  /// SSAP services that install, remove, reset or re-pair; never sent.
  static const _blockedSsap = [
    'install',
    'remove',
    'delete',
    'reset',
    'factory',
    'update',
    'register',
    'pairing',
    'developer',
    'devmode',
  ];

  /// Link schemes that would act on the TV itself rather than open an app.
  static const _blockedSchemes = {
    'file',
    'content',
    'javascript',
    'data',
    'intent',
    'market',
    'adb',
  };

  /// Why this command is not allowed, or null if it is valid.
  String? validate() {
    if (name.trim().isEmpty || name.length > 40) {
      return 'Give the command a name (up to 40 characters).';
    }
    switch (kind) {
      case CustomCommandKind.rokuKey:
        if (!_rokuKey.hasMatch(value)) {
          return 'Use an ECP key name such as InputHDMI2.';
        }
      case CustomCommandKind.rokuLaunch:
        if (!_rokuChannel.hasMatch(value)) {
          return 'Enter a channel id such as 12.';
        }
        for (final MapEntry(:key, value: v) in params.entries) {
          if (!_paramName.hasMatch(key)) {
            return 'Invalid parameter name "$key".';
          }
          if (v is! String || v.length > 200) {
            return 'Parameter "$key" must be text up to 200 characters.';
          }
        }
      case CustomCommandKind.webOsRequest:
        if (!_ssapUri.hasMatch(value)) {
          return 'Use an ssap:// URI such as ssap://tv/channelUp.';
        }
        final lower = value.toLowerCase();
        for (final word in _blockedSsap) {
          if (lower.contains(word)) {
            return 'Commands that change or remove things on the TV '
                '("$word") are not allowed.';
          }
        }
        if (utf8.encode(jsonEncode(params)).length > maxPayloadBytes) {
          return 'The payload is too large (max 4 KB).';
        }
      case CustomCommandKind.webOsButton:
        if (!_button.hasMatch(value)) {
          return 'Use an upper-case button name such as RED.';
        }
      case CustomCommandKind.samsungKey:
        if (!_samsungKey.hasMatch(value)) {
          return 'Use a Samsung key name such as KEY_HDMI2.';
        }
      case CustomCommandKind.androidKeyCode:
        final code = int.tryParse(value);
        if (code == null || code < 1 || code > 300) {
          return 'Use an Android key code between 1 and 300.';
        }
      case CustomCommandKind.androidLink:
        final uri = Uri.tryParse(value);
        if (uri == null || !uri.hasScheme || value.length > 500) {
          return 'Enter a link such as https://www.youtube.com.';
        }
        final scheme = uri.scheme.toLowerCase();
        if (!_scheme.hasMatch(scheme) || _blockedSchemes.contains(scheme)) {
          return '"$scheme:" links are not allowed.';
        }
        if ((scheme == 'http' || scheme == 'https') && uri.host.isEmpty) {
          return 'The link needs a host.';
        }
    }
    return null;
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'kind': kind.name,
    'value': value,
    if (params.isNotEmpty) 'params': params,
  };

  /// Parses and validates; throws [FormatException] with the reason.
  static CustomCommand fromJson(Map<String, Object?> json) {
    final kind = CustomCommandKind.values
        .where((k) => k.name == json['kind'])
        .firstOrNull;
    if (kind == null) throw const FormatException('Unknown command kind.');
    final params = json['params'];
    final command = CustomCommand(
      id: '${json['id'] ?? ''}',
      name: '${json['name'] ?? ''}'.trim(),
      kind: kind,
      value: '${json['value'] ?? ''}'.trim(),
      params: params is Map ? params.cast<String, Object?>() : const {},
    );
    final problem = command.validate();
    if (problem != null) throw FormatException(problem);
    return command;
  }
}

/// Throws unless [command] is valid and meant for [protocol].
void checkCustomCommand(CustomCommand command, String protocol) {
  if (command.protocol != protocol) {
    throw TvRemoteException.unsupported(
      '"${command.name}" is for another kind of TV and',
    );
  }
  final problem = command.validate();
  if (problem != null) {
    throw TvRemoteException(TvErrorCode.unsupported, problem);
  }
}
