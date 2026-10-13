import 'package:flutter_test/flutter_test.dart';
import 'package:tv_remote_free/core/adapter/custom_command.dart';
import 'package:tv_remote_free/core/errors.dart';

CustomCommand cmd(
  CustomCommandKind kind,
  String value, [
  Map<String, Object?> params = const {},
]) => CustomCommand(
  id: 'c',
  name: 'Test',
  kind: kind,
  value: value,
  params: params,
);

void main() {
  test('accepts well-formed commands of every kind', () {
    for (final c in [
      cmd(CustomCommandKind.rokuKey, 'InputHDMI2'),
      cmd(CustomCommandKind.rokuKey, 'Lit_a'),
      cmd(CustomCommandKind.rokuLaunch, '12', {
        'contentId': '8001',
        'mediaType': 'movie',
      }),
      cmd(CustomCommandKind.webOsRequest, 'ssap://tv/channelUp'),
      cmd(CustomCommandKind.webOsRequest, 'ssap://audio/setVolume', {
        'volume': 10,
      }),
      cmd(CustomCommandKind.webOsButton, 'RED'),
      cmd(CustomCommandKind.androidKeyCode, '183'),
      cmd(CustomCommandKind.androidLink, 'https://www.youtube.com'),
      cmd(CustomCommandKind.androidLink, 'spotify://'),
    ]) {
      expect(c.validate(), isNull, reason: '${c.kind} ${c.value}');
    }
  });

  test('refuses malformed values', () {
    expect(
      cmd(CustomCommandKind.rokuKey, '../query/apps').validate(),
      isNotNull,
    );
    expect(cmd(CustomCommandKind.rokuKey, 'Home?x=1').validate(), isNotNull);
    expect(cmd(CustomCommandKind.rokuLaunch, '12/../x').validate(), isNotNull);
    expect(
      cmd(CustomCommandKind.rokuLaunch, '12', {'bad name': 'x'}).validate(),
      isNotNull,
    );
    expect(
      cmd(CustomCommandKind.webOsRequest, 'http://tv/x').validate(),
      isNotNull,
    );
    expect(cmd(CustomCommandKind.webOsButton, 'red;rm').validate(), isNotNull);
    expect(cmd(CustomCommandKind.androidKeyCode, '0').validate(), isNotNull);
    expect(cmd(CustomCommandKind.androidKeyCode, '9999').validate(), isNotNull);
    expect(
      const CustomCommand(
        id: 'c',
        name: ' ',
        kind: CustomCommandKind.rokuKey,
        value: 'Home',
      ).validate(),
      isNotNull,
    );
  });

  test('blocks commands that change or remove things on the TV', () {
    for (final uri in [
      'ssap://com.webos.appInstallService/remove',
      'ssap://com.webos.service.update/getCurrentSWInformation',
      'ssap://com.webos.service.secondscreen.gateway/register',
      'ssap://system/factoryReset',
      'ssap://com.webos.applicationManager/deleteApp',
    ]) {
      expect(
        cmd(CustomCommandKind.webOsRequest, uri).validate(),
        contains('not allowed'),
        reason: uri,
      );
    }
    for (final link in [
      'file:///sdcard/x',
      'intent://x#Intent;end',
      'javascript:alert(1)',
      'content://media/x',
      'market://details?id=x',
    ]) {
      expect(
        cmd(CustomCommandKind.androidLink, link).validate(),
        isNotNull,
        reason: link,
      );
    }
    expect(
      cmd(CustomCommandKind.webOsRequest, 'ssap://tv/x', {
        'big': 'x' * 5000,
      }).validate(),
      contains('too large'),
    );
  });

  test('round-trips through JSON and re-validates on import', () {
    final c = cmd(CustomCommandKind.rokuLaunch, '12', {'contentId': '1'});
    expect(CustomCommand.fromJson(c.toJson()).toJson(), c.toJson());
    expect(
      () => CustomCommand.fromJson({
        'kind': 'webOsRequest',
        'name': 'x',
        'value': 'ssap://appInstallService/remove',
      }),
      throwsFormatException,
    );
    expect(
      () => CustomCommand.fromJson({'kind': 'shell', 'name': 'x'}),
      throwsFormatException,
    );
  });

  test('a TV only runs commands for its own system', () {
    final roku = cmd(CustomCommandKind.rokuKey, 'Home');
    expect(
      () => checkCustomCommand(roku, 'lg_webos'),
      throwsA(isA<TvRemoteException>()),
    );
    checkCustomCommand(roku, 'roku');
  });
}
