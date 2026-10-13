import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/adapter/custom_command.dart';
import '../../core/capabilities/remote_key.dart';
import '../macros/macro.dart' show keyLabel;

/// Icons a custom button can use. A fixed set keeps shared layouts from
/// referring to icons the app does not ship.
const layoutIcons = <String, IconData>{
  'power': Icons.power_settings_new,
  'home': Icons.home_outlined,
  'back': Icons.arrow_back,
  'menu': Icons.menu,
  'info': Icons.info_outline,
  'input': Icons.input,
  'search': Icons.search,
  'up': Icons.keyboard_arrow_up,
  'down': Icons.keyboard_arrow_down,
  'left': Icons.keyboard_arrow_left,
  'right': Icons.keyboard_arrow_right,
  'ok': Icons.radio_button_checked,
  'play': Icons.play_arrow,
  'pause': Icons.pause,
  'play_pause': Icons.play_circle_outline,
  'stop': Icons.stop,
  'rewind': Icons.fast_rewind,
  'fast_forward': Icons.fast_forward,
  'replay': Icons.replay_10,
  'next': Icons.skip_next,
  'previous': Icons.skip_previous,
  'volume_up': Icons.volume_up,
  'volume_down': Icons.volume_down,
  'mute': Icons.volume_off,
  'channel_up': Icons.keyboard_double_arrow_up,
  'channel_down': Icons.keyboard_double_arrow_down,
  'apps': Icons.apps,
  'tv': Icons.tv,
  'movie': Icons.movie_outlined,
  'music': Icons.music_note,
  'game': Icons.sports_esports,
  'star': Icons.star_outline,
  'heart': Icons.favorite_outline,
  'bolt': Icons.bolt,
  'settings': Icons.settings_outlined,
  'keyboard': Icons.keyboard,
  'red': Icons.circle,
  'macro': Icons.auto_awesome_outlined,
  'command': Icons.terminal,
};

String defaultIconFor(RemoteKey key) => switch (key) {
  RemoteKey.power || RemoteKey.powerOff || RemoteKey.powerOn => 'power',
  RemoteKey.home => 'home',
  RemoteKey.back => 'back',
  RemoteKey.menu => 'menu',
  RemoteKey.info => 'info',
  RemoteKey.input => 'input',
  RemoteKey.search => 'search',
  RemoteKey.up => 'up',
  RemoteKey.down => 'down',
  RemoteKey.left => 'left',
  RemoteKey.right => 'right',
  RemoteKey.select || RemoteKey.enter => 'ok',
  RemoteKey.play => 'play',
  RemoteKey.pause => 'pause',
  RemoteKey.playPause => 'play_pause',
  RemoteKey.stop => 'stop',
  RemoteKey.rewind => 'rewind',
  RemoteKey.fastForward => 'fast_forward',
  RemoteKey.replay => 'replay',
  RemoteKey.nextTrack => 'next',
  RemoteKey.previousTrack => 'previous',
  RemoteKey.volumeUp => 'volume_up',
  RemoteKey.volumeDown => 'volume_down',
  RemoteKey.mute => 'mute',
  RemoteKey.channelUp => 'channel_up',
  RemoteKey.channelDown => 'channel_down',
  RemoteKey.backspace => 'back',
};

/// What a button does.
sealed class ButtonAction {
  const ButtonAction();

  String get type;
  String get defaultLabel;
  String get defaultIcon;
  Map<String, Object?> toJson();

  /// Smallest size, in grid cells (width, height).
  (int, int) get minSize => (1, 1);

  static ButtonAction fromJson(Map<String, Object?> json) =>
      switch (json['type']) {
        'key' => KeyAction(RemoteKey.values.byName('${json['key']}')),
        'app' => AppAction('${json['app']}', '${json['name'] ?? json['app']}'),
        'macro' => MacroAction('${json['name']}'),
        'command' => CommandAction(
          CustomCommand.fromJson(
            (json['command']! as Map).cast<String, Object?>(),
          ),
        ),
        'power_on' => const PowerOnAction(),
        'dpad' => const DpadAction(),
        'now_playing' => const NowPlayingAction(),
        final t => throw FormatException('Unknown button type "$t".'),
      };
}

class KeyAction extends ButtonAction {
  const KeyAction(this.key);
  final RemoteKey key;
  @override
  String get type => 'key';
  @override
  String get defaultLabel => keyLabel(key);
  @override
  String get defaultIcon => defaultIconFor(key);
  @override
  Map<String, Object?> toJson() => {'type': type, 'key': key.name};
}

class AppAction extends ButtonAction {
  const AppAction(this.appId, this.appName);
  final String appId;
  final String appName;
  @override
  String get type => 'app';
  @override
  String get defaultLabel => appName;
  @override
  String get defaultIcon => 'apps';
  @override
  Map<String, Object?> toJson() => {
    'type': type,
    'app': appId,
    'name': appName,
  };
}

/// Runs a saved macro, referred to by name so shared layouts can find the
/// recipient's macro of the same name.
class MacroAction extends ButtonAction {
  const MacroAction(this.macroName);
  final String macroName;
  @override
  String get type => 'macro';
  @override
  String get defaultLabel => macroName;
  @override
  String get defaultIcon => 'macro';
  @override
  Map<String, Object?> toJson() => {'type': type, 'name': macroName};
}

class CommandAction extends ButtonAction {
  const CommandAction(this.command);
  final CustomCommand command;
  @override
  String get type => 'command';
  @override
  String get defaultLabel => command.name;
  @override
  String get defaultIcon => 'command';
  @override
  Map<String, Object?> toJson() => {'type': type, 'command': command.toJson()};
}

class PowerOnAction extends ButtonAction {
  const PowerOnAction();
  @override
  String get type => 'power_on';
  @override
  String get defaultLabel => 'Turn on';
  @override
  String get defaultIcon => 'power';
  @override
  Map<String, Object?> toJson() => {'type': type};
}

/// The full directional pad with OK.
class DpadAction extends ButtonAction {
  const DpadAction();
  @override
  String get type => 'dpad';
  @override
  String get defaultLabel => 'D-pad';
  @override
  String get defaultIcon => 'ok';
  @override
  (int, int) get minSize => (3, 3);
  @override
  Map<String, Object?> toJson() => {'type': type};
}

/// What is playing (app and state, progress where the TV reports it).
class NowPlayingAction extends ButtonAction {
  const NowPlayingAction();
  @override
  String get type => 'now_playing';
  @override
  String get defaultLabel => 'Now playing';
  @override
  String get defaultIcon => 'music';
  @override
  (int, int) get minSize => (4, 1);
  @override
  Map<String, Object?> toJson() => {'type': type};
}

/// One button on a custom remote.
class LayoutItem {
  const LayoutItem({
    required this.id,
    required this.action,
    this.width = 1,
    this.height = 1,
    this.label,
    this.icon,
  });

  final String id;
  final ButtonAction action;

  /// Size in grid cells: 1–4 wide, 1–3 tall.
  final int width;
  final int height;
  final String? label;
  final String? icon;

  String get displayLabel => label ?? action.defaultLabel;
  IconData get iconData =>
      layoutIcons[icon] ?? layoutIcons[action.defaultIcon] ?? Icons.circle;

  LayoutItem copyWith({
    ButtonAction? action,
    int? width,
    int? height,
    String? Function()? label,
    String? Function()? icon,
  }) {
    final next = action ?? this.action;
    final (minW, minH) = next.minSize;
    return LayoutItem(
      id: id,
      action: next,
      width: (width ?? this.width).clamp(minW, RemoteLayout.columns),
      height: (height ?? this.height).clamp(minH, 3),
      label: label == null ? this.label : label(),
      icon: icon == null ? this.icon : icon(),
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'action': action.toJson(),
    'w': width,
    'h': height,
    'label': ?label,
    'icon': ?icon,
  };

  static LayoutItem fromJson(Map<String, Object?> json) {
    final action = ButtonAction.fromJson(
      (json['action']! as Map).cast<String, Object?>(),
    );
    final (minW, minH) = action.minSize;
    final label = json['label'];
    final icon = json['icon'];
    return LayoutItem(
      id: '${json['id']}',
      action: action,
      width: ((json['w'] as num?)?.round() ?? 1).clamp(
        minW,
        RemoteLayout.columns,
      ),
      height: ((json['h'] as num?)?.round() ?? 1).clamp(minH, 3),
      label: label is String && label.trim().isNotEmpty
          ? (label.trim().length > 24
                ? label.trim().substring(0, 24)
                : label.trim())
          : null,
      icon: icon is String && layoutIcons.containsKey(icon) ? icon : null,
    );
  }
}

const layoutFormatId = 'tv-remote-free-layout';

/// A user-built remote: buttons packed into a 4-column grid in order.
class RemoteLayout {
  const RemoteLayout({
    required this.id,
    required this.name,
    required this.items,
    this.builtIn = false,
  });

  static const columns = 4;
  static const maxItems = 60;

  /// The app's standard remote (not a grid layout).
  static const standardId = 'builtin.standard';

  final String id;
  final String name;
  final List<LayoutItem> items;
  final bool builtIn;

  RemoteLayout copyWith({String? name, List<LayoutItem>? items}) =>
      RemoteLayout(id: id, name: name ?? this.name, items: items ?? this.items);

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'items': [for (final i in items) i.toJson()],
  };

  /// Validates every button; throws [FormatException] with the reason.
  static RemoteLayout fromJson(
    Map<String, Object?> json, {
    bool builtIn = false,
  }) {
    final name = '${json['name'] ?? ''}'.trim();
    final items = json['items'];
    if (name.isEmpty || items is! List) {
      throw const FormatException('This is not a remote layout.');
    }
    if (items.length > maxItems) {
      throw const FormatException('Too many buttons (max 60).');
    }
    return RemoteLayout(
      id: '${json['id'] ?? ''}',
      name: name.length > 40 ? name.substring(0, 40) : name,
      items: [
        for (final i in items)
          LayoutItem.fromJson((i as Map).cast<String, Object?>()),
      ],
      builtIn: builtIn,
    );
  }

  /// A shareable file.
  String export() => const JsonEncoder.withIndent('  ')
      .convert({'format': layoutFormatId, 'version': 1, 'layout': toJson()});

  /// Parses a shared file; throws [FormatException] with the reason.
  static RemoteLayout import(String text, {required String newId}) {
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      throw const FormatException('This is not a remote layout file.');
    }
    if (decoded is! Map || decoded['format'] != layoutFormatId) {
      throw const FormatException('This is not a remote layout file.');
    }
    if ((decoded['version'] as num? ?? 0) > 1) {
      throw const FormatException('This layout needs a newer app version.');
    }
    final layout = decoded['layout'];
    if (layout is! Map) throw const FormatException('The file has no layout.');
    final parsed = fromJson(layout.cast<String, Object?>());
    return RemoteLayout(id: newId, name: parsed.name, items: parsed.items);
  }
}

/// Where an item sits in the grid.
class PlacedItem {
  const PlacedItem(this.item, this.column, this.row);
  final LayoutItem item;
  final int column;
  final int row;
}

/// Packs items into the grid in order: each goes in the first free spot,
/// scanning rows top to bottom, so small buttons fill gaps.
(List<PlacedItem>, int rows) packLayout(List<LayoutItem> items) {
  final taken = <List<bool>>[];
  bool free(int c, int r, int w, int h) {
    for (var y = r; y < r + h; y++) {
      while (taken.length <= y) {
        taken.add(List.filled(RemoteLayout.columns, false));
      }
      for (var x = c; x < c + w; x++) {
        if (taken[y][x]) return false;
      }
    }
    return true;
  }

  final placed = <PlacedItem>[];
  for (final item in items) {
    final w = item.width.clamp(1, RemoteLayout.columns);
    var row = 0;
    placement:
    while (true) {
      for (var col = 0; col + w <= RemoteLayout.columns; col++) {
        if (free(col, row, w, item.height)) {
          for (var y = row; y < row + item.height; y++) {
            for (var x = col; x < col + w; x++) {
              taken[y][x] = true;
            }
          }
          placed.add(PlacedItem(item, col, row));
          break placement;
        }
      }
      row++;
    }
  }
  final rows = placed.fold<int>(
    0,
    (m, p) => (p.row + p.item.height) > m ? p.row + p.item.height : m,
  );
  return (placed, rows);
}
