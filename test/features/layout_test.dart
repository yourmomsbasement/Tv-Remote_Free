import 'package:flutter_test/flutter_test.dart';
import 'package:tv_remote_free/core/adapter/custom_command.dart';
import 'package:tv_remote_free/core/capabilities/remote_key.dart';
import 'package:tv_remote_free/features/layouts/layout_library.dart';
import 'package:tv_remote_free/features/layouts/remote_layout.dart';

LayoutItem item(String id, {int w = 1, int h = 1, ButtonAction? action}) =>
    LayoutItem(
      id: id,
      action: action ?? const KeyAction(RemoteKey.home),
      width: w,
      height: h,
    );

void main() {
  test('packs buttons row by row, filling gaps', () {
    final (placed, rows) = packLayout([
      item('a', w: 2),
      item('b', w: 3), // doesn't fit beside a: next row
      item('c'), // fills the gap beside a
      item('d', h: 2),
    ]);
    final at = {for (final p in placed) p.item.id: (p.column, p.row)};
    expect(at['a'], (0, 0));
    expect(at['b'], (0, 1));
    expect(at['c'], (2, 0));
    expect(at['d'], (3, 0));
    expect(rows, 2);
  });

  test('sizes are clamped to each button type', () {
    final dpad = item('d', action: const DpadAction()).copyWith(width: 1);
    expect((dpad.width, dpad.height), (3, 3));
    expect(item('x').copyWith(width: 9, height: 9).width, 4);
    expect(item('x').copyWith(height: 9).height, 3);
  });

  test('export and import round-trip, with embedded commands', () {
    final layout = RemoteLayout(
      id: 'l1',
      name: 'Mine',
      items: [
        item('a', w: 2).copyWith(label: () => 'Go home', icon: () => 'star'),
        const LayoutItem(id: 'b', action: DpadAction(), width: 4, height: 3),
        const LayoutItem(
          id: 'c',
          action: CommandAction(
            CustomCommand(
              id: 'k',
              name: 'HDMI 2',
              kind: CustomCommandKind.rokuKey,
              value: 'InputHDMI2',
            ),
          ),
        ),
        const LayoutItem(id: 'd', action: AppAction('12', 'Netflix')),
        const LayoutItem(id: 'e', action: MacroAction('Movie night')),
        const LayoutItem(id: 'f', action: NowPlayingAction(), width: 4),
      ],
    );
    final back = RemoteLayout.import(layout.export(), newId: 'new');
    expect(back.id, 'new');
    expect(back.toJson()['items'], layout.toJson()['items']);
    expect(back.items.first.displayLabel, 'Go home');
  });

  test('imports refuse invalid files and unsafe commands', () {
    expect(
      () => RemoteLayout.import('nope', newId: 'x'),
      throwsFormatException,
    );
    expect(
      () => RemoteLayout.import('{"format":"other"}', newId: 'x'),
      throwsFormatException,
    );
    const unsafe =
        '{"format":"tv-remote-free-layout","version":1,"layout":'
        '{"name":"Bad","items":[{"id":"a","action":{"type":"command",'
        '"command":{"id":"c","name":"x","kind":"webOsRequest",'
        '"value":"ssap://com.webos.appInstallService/remove"}}}]}}';
    expect(
      () => RemoteLayout.import(unsafe, newId: 'x'),
      throwsFormatException,
    );
    const unknownIcon =
        '{"format":"tv-remote-free-layout","version":1,"layout":'
        '{"name":"Ok","items":[{"id":"a","action":{"type":"key","key":"home"},'
        '"icon":"not-an-icon","w":2}]}}';
    final ok = RemoteLayout.import(unknownIcon, newId: 'x');
    expect(ok.items.single.icon, isNull);
    expect(ok.items.single.width, 2);
  });

  test('built-in templates are valid and include the music controls', () {
    for (final l in [musicLayout, minimalLayout]) {
      final back = RemoteLayout.fromJson(l.toJson());
      expect(back.items.length, l.items.length);
    }
    final keys = [
      for (final i in musicLayout.items)
        if (i.action case KeyAction(:final key)) key,
    ];
    expect(
      keys,
      containsAll([
        RemoteKey.previousTrack,
        RemoteKey.playPause,
        RemoteKey.nextTrack,
      ]),
    );
  });
}
