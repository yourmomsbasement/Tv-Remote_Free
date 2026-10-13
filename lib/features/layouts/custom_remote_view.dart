import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/adapter/smart_tv_adapter.dart';
import '../../core/capabilities/remote_key.dart';
import '../../core/platform/haptics.dart';
import '../../ui/components/dpad.dart';
import '../../ui/themes/remote_style.dart';
import '../themes/theme_definition.dart' show ButtonShape;
import '../macros/macro_library.dart';
import '../macros/macros_screen.dart';
import '../remote/now_playing_card.dart';
import '../remote/remote_session.dart';
import '../settings/app_settings.dart';
import 'remote_layout.dart';

/// Renders a [RemoteLayout]. In [editing] mode buttons don't act: tapping
/// one calls [onEdit], and long-press-dragging one onto another moves it
/// there ([onMove]).
class CustomRemoteView extends ConsumerWidget {
  const CustomRemoteView({
    super.key,
    required this.layout,
    this.editing = false,
    this.onEdit,
    this.onMove,
  });

  final RemoteLayout layout;
  final bool editing;
  final void Function(LayoutItem item)? onEdit;
  final void Function(String movedId, String beforeId)? onMove;

  @override
  Widget build(BuildContext context, WidgetRef ref) => LayoutBuilder(
    builder: (context, constraints) {
      const gap = 8.0;
      final cell =
          (constraints.maxWidth - gap * (RemoteLayout.columns + 1)) /
          RemoteLayout.columns;
      final (placed, rows) = packLayout(layout.items);
      return SingleChildScrollView(
        child: SizedBox(
          height: rows * (cell + gap) + gap,
          child: Stack(
            children: [
              for (final p in placed)
                Positioned(
                  left: gap + p.column * (cell + gap),
                  top: gap + p.row * (cell + gap),
                  width: p.item.width * cell + (p.item.width - 1) * gap,
                  height: p.item.height * cell + (p.item.height - 1) * gap,
                  child: editing
                      ? _EditableItem(
                          item: p.item,
                          onEdit: onEdit,
                          onMove: onMove,
                        )
                      : _LiveItem(item: p.item),
                ),
            ],
          ),
        ),
      );
    },
  );
}

/// A button that does its action.
class _LiveItem extends ConsumerWidget {
  const _LiveItem({required this.item});

  final LayoutItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(remoteSessionProvider);
    final haptics = ref.watch(settingsProvider.select((s) => s.hapticStrength));
    final remote = ref.read(remoteSessionProvider.notifier);
    final caps = session.capabilities;
    final connected = session.isConnected;

    switch (item.action) {
      case DpadAction():
        return LayoutBuilder(
          builder: (context, c) => Center(
            child: DPad(
              size: math.min(c.maxWidth, c.maxHeight),
              enabled: connected && caps.navigation,
              haptics: haptics,
              onKey: remote.sendKey,
            ),
          ),
        );
      case NowPlayingAction():
        final activity = session.activity;
        return activity != null && activity.hasMedia
            ? _CompactNowPlaying(activity: activity)
            : Card(
                margin: EdgeInsets.zero,
                child: Center(
                  child: Text(
                    activity?.appName == null
                        ? 'Nothing playing'
                        : 'In ${activity!.appName}',
                  ),
                ),
              );
      case final action:
        final macros = ref.watch(macroLibraryProvider).value ?? const [];
        final (enabled, reason) = switch (action) {
          KeyAction(:final key) => (
            connected && caps.supportsKey(key),
            'Not available on this TV',
          ),
          AppAction() => (connected && caps.appLaunch, 'Cannot open apps'),
          CommandAction(:final command) => (
            connected &&
                caps.customCommands &&
                command.protocol == session.device?.protocol,
            'This command is for another kind of TV',
          ),
          MacroAction(:final macroName) => (
            macros.any((m) => m.name == macroName),
            'No macro named "$macroName"',
          ),
          PowerOnAction() => (session.canPowerOn, 'Cannot turn this TV on'),
          _ => (false, ''),
        };
        Future<void> run() async {
          switch (action) {
            case KeyAction(:final key):
              await remote.sendKey(key);
            case AppAction(:final appId):
              await remote.launchApp(appId);
            case CommandAction(:final command):
              await remote.sendCustom(command);
            case MacroAction(:final macroName):
              final macro = macros.firstWhere((m) => m.name == macroName);
              if (context.mounted) await MacrosScreen.run(context, ref, macro);
            case PowerOnAction():
              await remote.powerOn();
            default:
          }
        }

        return _GridButton(
          icon: item.iconData,
          label: item.displayLabel,
          tooltip: enabled
              ? item.displayLabel
              : '${item.displayLabel}: $reason',
          haptics: haptics,
          accent:
              action is KeyAction &&
              (action.key == RemoteKey.power ||
                  action.key == RemoteKey.playPause),
          repeat: action is KeyAction && repeatableKeys.contains(action.key),
          onPressed: enabled ? run : null,
        );
    }
  }
}

/// A button that fills its grid cells, with haptics and hold-to-repeat.
class _GridButton extends StatefulWidget {
  const _GridButton({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.haptics,
    required this.onPressed,
    this.repeat = false,
    this.accent = false,
  });

  final IconData icon;
  final String label;
  final String tooltip;
  final HapticStrength haptics;
  final VoidCallback? onPressed;
  final bool repeat;
  final bool accent;

  @override
  State<_GridButton> createState() => _GridButtonState();
}

class _GridButtonState extends State<_GridButton> {
  Timer? _delay;
  Timer? _repeat;
  bool _held = false;

  void _stop() {
    _delay?.cancel();
    _repeat?.cancel();
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = RemoteStyle.of(context);
    final enabled = widget.onPressed != null;
    final bg = widget.accent ? style.accentButton : style.button;
    final fg = widget.accent ? style.accentButtonIcon : style.buttonIcon;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      excludeSemantics: true,
      child: Tooltip(
        message: widget.tooltip,
        triggerMode: widget.repeat
            ? TooltipTriggerMode.manual
            : TooltipTriggerMode.longPress,
        enableFeedback: false,
        child: Listener(
          onPointerDown: enabled && widget.repeat
              ? (_) {
                  _held = false;
                  _delay = Timer(const Duration(milliseconds: 350), () {
                    _held = true;
                    Haptics.play(HapticEvent.hold, widget.haptics);
                    widget.onPressed?.call();
                    var n = 0;
                    _repeat = Timer.periodic(
                      const Duration(milliseconds: 150),
                      (t) {
                        if (++n > 60) return _stop();
                        Haptics.play(HapticEvent.repeat, widget.haptics);
                        widget.onPressed?.call();
                      },
                    );
                  });
                }
              : null,
          onPointerUp: (_) => _stop(),
          onPointerCancel: (_) => _stop(),
          child: Material(
            color: enabled ? bg : bg.withValues(alpha: 0.4),
            shape: style.buttonShape == ButtonShape.circle
                ? RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  )
                : style.buttonBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: enabled
                  ? () {
                      if (_held) {
                        _held = false;
                        return;
                      }
                      Haptics.play(HapticEvent.press, widget.haptics);
                      widget.onPressed?.call();
                    }
                  : null,
              child: LayoutBuilder(
                builder: (context, c) {
                  final iconSize = math.min(c.maxWidth, c.maxHeight) * 0.42;
                  final showLabel = c.maxWidth > 100 || c.maxHeight > 100;
                  final color = enabled ? fg : fg.withValues(alpha: 0.4);
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          widget.icon,
                          size: showLabel ? iconSize * 0.8 : iconSize,
                          color: color,
                        ),
                        if (showLabel)
                          Text(
                            widget.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: color),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CompactNowPlaying extends StatelessWidget {
  const _CompactNowPlaying({required this.activity});

  final MediaActivity activity;

  @override
  Widget build(BuildContext context) {
    final position = activity.positionAt(DateTime.now());
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  activity.state == PlaybackState.playing
                      ? Icons.play_arrow
                      : Icons.pause,
                  size: 18,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    activity.appName ?? 'Now playing',
                    style: theme.textTheme.titleSmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (activity.hasTimeline && position != null)
                  Text(
                    '${formatDuration(position)} / '
                    '${formatDuration(activity.duration!)}',
                    style: theme.textTheme.bodySmall,
                  ),
              ],
            ),
            if (activity.hasTimeline && position != null) ...[
              const SizedBox(height: 6),
              LinearProgressIndicator(
                value:
                    position.inMilliseconds / activity.duration!.inMilliseconds,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A button in edit mode: tap to edit, long-press and drag to move.
class _EditableItem extends StatelessWidget {
  const _EditableItem({required this.item, this.onEdit, this.onMove});

  final LayoutItem item;
  final void Function(LayoutItem item)? onEdit;
  final void Function(String movedId, String beforeId)? onMove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget face({bool highlighted = false}) => Material(
      color: highlighted
          ? scheme.primaryContainer
          : scheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outline),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => onEdit?.call(item),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(item.iconData),
              Text(
                item.displayLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ),
        ),
      ),
    );

    return DragTarget<String>(
      onWillAcceptWithDetails: (d) => d.data != item.id,
      onAcceptWithDetails: (d) => onMove?.call(d.data, item.id),
      builder: (context, candidates, _) => LongPressDraggable<String>(
        data: item.id,
        feedback: Opacity(
          opacity: 0.8,
          child: SizedBox(
            width: 72,
            height: 72,
            child: Material(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
              child: Icon(item.iconData),
            ),
          ),
        ),
        childWhenDragging: Opacity(opacity: 0.3, child: face()),
        child: face(highlighted: candidates.isNotEmpty),
      ),
    );
  }
}
