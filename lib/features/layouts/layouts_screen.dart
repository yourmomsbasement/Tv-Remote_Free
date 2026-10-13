import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/device_record.dart';

import '../../core/adapter/custom_command.dart';
import '../../core/adapter/smart_tv_adapter.dart';
import '../../core/capabilities/remote_key.dart';
import '../applications/app_links.dart';
import '../macros/macro.dart' show keyLabel;
import '../macros/macro_library.dart';
import '../remote/remote_session.dart';
import 'custom_remote_view.dart';
import 'layout_library.dart';
import 'remote_layout.dart';

void _snack(BuildContext context, String message) =>
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));

/// Picks the remote layout and manages custom ones.
class LayoutsScreen extends ConsumerWidget {
  const LayoutsScreen({super.key});

  Future<void> _edit(BuildContext context, RemoteLayout layout) => Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => LayoutEditor(initial: layout)));

  RemoteLayout _copy(RemoteLayout l) => RemoteLayout(
    id: LayoutLibrary.newId(),
    name: l.builtIn ? 'My ${l.name.toLowerCase()} remote' : '${l.name} copy',
    items: l.items,
  );

  Future<void> _import(
    BuildContext context,
    WidgetRef ref,
    String source,
  ) async {
    String? text;
    try {
      if (source == 'file') {
        final file = await FilePicker.pickFile(
          type: FileType.custom,
          allowedExtensions: const ['json'],
        );
        if (file == null) return;
        text = utf8.decode(await file.readAsBytes(), allowMalformed: true);
      } else {
        text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
      }
      if (text == null || text.isEmpty) return;
      final layout = RemoteLayout.import(text, newId: LayoutLibrary.newId());
      await ref.read(layoutLibraryProvider.notifier).save(layout);
      if (context.mounted) _snack(context, 'Added "${layout.name}"');
    } on FormatException catch (e) {
      if (context.mounted) _snack(context, e.message);
    } on Object {
      if (context.mounted) _snack(context, 'Could not read the layout.');
    }
  }

  Future<void> _action(
    BuildContext context,
    WidgetRef ref,
    RemoteLayout l,
    String action,
  ) async {
    final library = ref.read(layoutLibraryProvider.notifier);
    switch (action) {
      case 'edit':
        await _edit(context, l.builtIn ? _copy(l) : l);
      case 'duplicate':
        await library.save(_copy(l));
      case 'export':
        try {
          await FilePicker.saveFile(
            dialogTitle: 'Save layout',
            fileName:
                '${l.name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-')}.tvlayout.json',
            bytes: utf8.encode(l.export()),
            mimeType: 'application/json',
          );
        } on Object {
          if (context.mounted) _snack(context, 'Could not save the file.');
        }
      case 'copy':
        await Clipboard.setData(ClipboardData(text: l.export()));
        if (context.mounted) _snack(context, 'Layout copied as text');
      case 'delete':
        await library.remove(l);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layouts = ref.watch(layoutLibraryProvider).value ?? const [];
    final activeId =
        ref.watch(activeLayoutIdProvider).value ?? RemoteLayout.standardId;
    final library = ref.read(layoutLibraryProvider.notifier);

    Widget tile({
      required String id,
      required String title,
      required String subtitle,
      RemoteLayout? layout,
    }) => ListTile(
      leading: Icon(
        id == activeId
            ? Icons.radio_button_checked
            : Icons.radio_button_unchecked,
      ),
      title: Text(title),
      subtitle: Text(subtitle),
      onTap: () => library.setActive(id),
      trailing: layout == null
          ? null
          : PopupMenuButton<String>(
              tooltip: 'More',
              onSelected: (a) => _action(context, ref, layout, a),
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'edit',
                  child: Text(layout.builtIn ? 'Customize a copy' : 'Edit'),
                ),
                const PopupMenuItem(
                  value: 'duplicate',
                  child: Text('Duplicate'),
                ),
                const PopupMenuItem(
                  value: 'export',
                  child: Text('Save as file'),
                ),
                const PopupMenuItem(value: 'copy', child: Text('Copy as text')),
                if (!layout.builtIn)
                  const PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Remote layouts'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Import layout',
            icon: const Icon(Icons.file_download_outlined),
            onSelected: (s) => _import(context, ref, s),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'file', child: Text('Import from file')),
              PopupMenuItem(
                value: 'clipboard',
                child: Text('Paste from clipboard'),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(
          context,
          RemoteLayout(
            id: LayoutLibrary.newId(),
            name: 'My remote',
            items: const [],
          ),
        ),
        icon: const Icon(Icons.dashboard_customize_outlined),
        label: const Text('New layout'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          tile(
            id: RemoteLayout.standardId,
            title: 'Standard',
            subtitle: 'Adapts to each TV automatically',
          ),
          for (final l in layouts)
            tile(
              id: l.id,
              title: l.name,
              subtitle: l.builtIn
                  ? (l.id == 'builtin.music'
                        ? 'Big playback controls and what\'s playing'
                        : 'Just the essentials')
                  : '${l.items.length} buttons',
              layout: l,
            ),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Buttons a TV doesn\'t support are shown dimmed. Shared layouts '
              'carry their custom commands; macro buttons look for a macro '
              'with the same name on the receiving phone.',
            ),
          ),
        ],
      ),
    );
  }
}

/// Builds a layout: add, move, resize and remove buttons.
class LayoutEditor extends ConsumerStatefulWidget {
  const LayoutEditor({super.key, required this.initial});

  final RemoteLayout initial;

  @override
  ConsumerState<LayoutEditor> createState() => _LayoutEditorState();
}

class _LayoutEditorState extends ConsumerState<LayoutEditor> {
  late RemoteLayout _layout = widget.initial;
  late final _name = TextEditingController(text: widget.initial.name);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _setItems(List<LayoutItem> items) =>
      setState(() => _layout = _layout.copyWith(items: items));

  void _move(String movedId, String beforeId) {
    final items = [..._layout.items];
    final moved = items.firstWhere((i) => i.id == movedId);
    items.remove(moved);
    items.insert(items.indexWhere((i) => i.id == beforeId), moved);
    _setItems(items);
  }

  Future<void> _add() async {
    if (_layout.items.length >= RemoteLayout.maxItems) {
      _snack(context, 'A layout can have up to 60 buttons.');
      return;
    }
    final action = await showModalBottomSheet<ButtonAction>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const _ActionPicker(),
    );
    if (action == null) return;
    final (w, h) = action.minSize;
    _setItems([
      ..._layout.items,
      LayoutItem(
        id: LayoutLibrary.newItemId(),
        action: action,
        width: w,
        height: h,
      ),
    ]);
  }

  Future<void> _editItem(LayoutItem item) async {
    final result = await showModalBottomSheet<LayoutItem?>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _ItemEditor(item: item),
    );
    if (!mounted) return;
    // A null result with the sheet's delete button means remove.
    if (result == null) return;
    _setItems([
      for (final i in _layout.items)
        if (i.id != item.id) i else if (result.id != '') result,
    ]);
  }

  Future<void> _save() async {
    final name = _name.text.trim().isEmpty ? 'My remote' : _name.text.trim();
    final library = ref.read(layoutLibraryProvider.notifier);
    await library.save(_layout.copyWith(name: name));
    await library.setActive(_layout.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: TextField(
        controller: _name,
        decoration: const InputDecoration(
          border: InputBorder.none,
          hintText: 'Layout name',
        ),
      ),
      actions: [TextButton(onPressed: _save, child: const Text('Save & use'))],
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _add,
      icon: const Icon(Icons.add),
      label: const Text('Add button'),
    ),
    body: Column(
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text(
            'Tap a button to resize, relabel or remove it. Long-press '
            'and drag it onto another button to move it there.',
          ),
        ),
        Expanded(
          child: _layout.items.isEmpty
              ? const Center(child: Text('No buttons yet. Tap "Add button".'))
              : Padding(
                  padding: const EdgeInsets.only(bottom: 80),
                  child: CustomRemoteView(
                    layout: _layout,
                    editing: true,
                    onEdit: _editItem,
                    onMove: _move,
                  ),
                ),
        ),
      ],
    ),
  );
}

/// Chooses what a new button does.
class _ActionPicker extends ConsumerWidget {
  const _ActionPicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(remoteSessionProvider);
    final macros = ref.watch(macroLibraryProvider).value ?? const [];
    final keys = RemoteKey.values
        .where(
          (k) => !session.isConnected || session.capabilities.supportsKey(k),
        )
        .toList();

    Future<void> pickApp() async {
      final apps = session.isConnected && session.capabilities.appList
          ? await ref.read(remoteSessionProvider.notifier).listApps()
          : knownAppLinks;
      if (!context.mounted) return;
      final app = await showDialog<TvApp>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('Open which app?'),
          children: [
            for (final a in apps)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, a),
                child: Text(a.name),
              ),
          ],
        ),
      );
      if (app != null && context.mounted) {
        Navigator.pop(context, AppAction(app.id, app.name));
      }
    }

    Future<void> pickCommand() async {
      final command = await showDialog<CustomCommand>(
        context: context,
        builder: (_) => const CommandEditor(),
      );
      if (command != null && context.mounted) {
        Navigator.pop(context, CommandAction(command));
      }
    }

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      builder: (context, controller) => ListView(
        controller: controller,
        children: [
          ListTile(
            leading: const Icon(Icons.gamepad_outlined),
            title: const Text('D-pad'),
            onTap: () => Navigator.pop(context, const DpadAction()),
          ),
          ListTile(
            leading: const Icon(Icons.music_note),
            title: const Text('Now playing'),
            onTap: () => Navigator.pop(context, const NowPlayingAction()),
          ),
          ListTile(
            leading: const Icon(Icons.power),
            title: const Text('Turn on'),
            onTap: () => Navigator.pop(context, const PowerOnAction()),
          ),
          ListTile(
            leading: const Icon(Icons.apps),
            title: const Text('Open an app'),
            onTap: pickApp,
          ),
          for (final m in macros)
            ListTile(
              leading: const Icon(Icons.auto_awesome_outlined),
              title: Text('Macro: ${m.name}'),
              onTap: () => Navigator.pop(context, MacroAction(m.name)),
            ),
          ListTile(
            leading: const Icon(Icons.terminal),
            title: const Text('Custom command…'),
            subtitle: const Text('For advanced users'),
            onTap: pickCommand,
          ),
          const Divider(),
          for (final k in keys)
            ListTile(
              leading: Icon(layoutIcons[defaultIconFor(k)]),
              title: Text(keyLabel(k)),
              onTap: () => Navigator.pop(context, KeyAction(k)),
            ),
        ],
      ),
    );
  }
}

/// Size, label, icon and removal for one button. Pops the updated item, or
/// an item with an empty id to remove it.
class _ItemEditor extends StatefulWidget {
  const _ItemEditor({required this.item});

  final LayoutItem item;

  @override
  State<_ItemEditor> createState() => _ItemEditorState();
}

class _ItemEditorState extends State<_ItemEditor> {
  late LayoutItem _item = widget.item;
  late final _label = TextEditingController(text: widget.item.label ?? '');

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  Widget _stepper(
    String label,
    int value,
    int min,
    int max,
    LayoutItem Function(int) apply,
  ) => Row(
    children: [
      Expanded(child: Text('$label: $value')),
      IconButton(
        tooltip: 'Smaller',
        onPressed: value > min
            ? () => setState(() => _item = apply(value - 1))
            : null,
        icon: const Icon(Icons.remove),
      ),
      IconButton(
        tooltip: 'Larger',
        onPressed: value < max
            ? () => setState(() => _item = apply(value + 1))
            : null,
        icon: const Icon(Icons.add),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final (minW, minH) = _item.action.minSize;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _item.action.defaultLabel,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            _stepper(
              'Width',
              _item.width,
              minW,
              RemoteLayout.columns,
              (v) => _item.copyWith(width: v),
            ),
            _stepper(
              'Height',
              _item.height,
              minH,
              3,
              (v) => _item.copyWith(height: v),
            ),
            TextField(
              controller: _label,
              maxLength: 24,
              decoration: InputDecoration(
                labelText: 'Label',
                hintText: _item.action.defaultLabel,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final MapEntry(:key, :value) in layoutIcons.entries)
                  IconButton(
                    tooltip: key,
                    isSelected: (_item.icon ?? _item.action.defaultIcon) == key,
                    onPressed: () =>
                        setState(() => _item = _item.copyWith(icon: () => key)),
                    icon: Icon(value),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () => Navigator.pop(
                    context,
                    LayoutItem(id: '', action: _item.action),
                  ), // remove marker
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Remove'),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: () => Navigator.pop(
                    context,
                    _item.copyWith(
                      label: () => _label.text.trim().isEmpty
                          ? null
                          : _label.text.trim(),
                    ),
                  ),
                  child: const Text('Done'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Defines a custom command, validated as you type, with a Test button.
class CommandEditor extends ConsumerStatefulWidget {
  const CommandEditor({super.key});

  @override
  ConsumerState<CommandEditor> createState() => _CommandEditorState();
}

class _CommandEditorState extends ConsumerState<CommandEditor> {
  final _name = TextEditingController();
  final _value = TextEditingController();
  final _params = TextEditingController();
  late CustomCommandKind _kind =
      CustomCommandKind.forProtocol(
        ref.read(remoteSessionProvider).device?.protocol ?? '',
      ).firstOrNull ??
      CustomCommandKind.rokuKey;

  @override
  void dispose() {
    _name.dispose();
    _value.dispose();
    _params.dispose();
    super.dispose();
  }

  /// The command as typed, or an error explaining what's wrong.
  (CustomCommand?, String?) _build() {
    Map<String, Object?> params = const {};
    final raw = _params.text.trim();
    if (raw.isNotEmpty) {
      if (_kind == CustomCommandKind.webOsRequest) {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is! Map) {
            return (null, 'The payload must be a JSON object.');
          }
          params = decoded.cast<String, Object?>();
        } on FormatException {
          return (null, 'The payload is not valid JSON.');
        }
      } else if (_kind == CustomCommandKind.rokuLaunch) {
        params = {
          for (final line in const LineSplitter().convert(raw))
            if (line.contains('='))
              line.substring(0, line.indexOf('=')).trim(): line
                  .substring(line.indexOf('=') + 1)
                  .trim(),
        };
      }
    }
    final command = CustomCommand(
      id: LayoutLibrary.newItemId(),
      name: _name.text.trim(),
      kind: _kind,
      value: _value.text.trim(),
      params: params,
    );
    final problem = command.validate();
    return problem == null ? (command, null) : (null, problem);
  }

  String get _hint => switch (_kind) {
    CustomCommandKind.rokuKey => 'InputHDMI2',
    CustomCommandKind.rokuLaunch => '12',
    CustomCommandKind.webOsRequest => 'ssap://tv/channelUp',
    CustomCommandKind.webOsButton => 'RED',
    CustomCommandKind.androidKeyCode => '183',
    CustomCommandKind.androidLink => 'https://www.youtube.com',
    CustomCommandKind.samsungKey => 'KEY_HDMI2',
  };

  @override
  Widget build(BuildContext context) {
    final (command, problem) = _build();
    final session = ref.watch(remoteSessionProvider);
    final canTest =
        command != null &&
        session.isConnected &&
        session.device?.protocol == command.protocol;
    return AlertDialog(
      title: const Text('Custom command'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<CustomCommandKind>(
              isExpanded: true,
              initialValue: _kind,
              decoration: const InputDecoration(labelText: 'Type'),
              items: [
                for (final k in CustomCommandKind.values)
                  DropdownMenuItem(
                    value: k,
                    child: Text('${Protocols.label(k.protocol)}: ${k.label}'),
                  ),
              ],
              onChanged: (k) => setState(() => _kind = k!),
            ),
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Button name'),
              onChanged: (_) => setState(() {}),
            ),
            TextField(
              controller: _value,
              decoration: InputDecoration(
                labelText: _kind.label,
                hintText: _hint,
              ),
              onChanged: (_) => setState(() {}),
            ),
            if (_kind == CustomCommandKind.rokuLaunch ||
                _kind == CustomCommandKind.webOsRequest)
              TextField(
                controller: _params,
                minLines: 2,
                maxLines: 5,
                decoration: InputDecoration(
                  labelText: _kind == CustomCommandKind.rokuLaunch
                      ? 'Parameters (name=value per line, optional)'
                      : 'JSON payload (optional)',
                  hintText: _kind == CustomCommandKind.rokuLaunch
                      ? 'contentId=abc\nmediaType=movie'
                      : '{"channelNumber": "7"}',
                ),
                onChanged: (_) => setState(() {}),
              ),
            if (problem != null && _value.text.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  problem,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: canTest
              ? () =>
                    ref.read(remoteSessionProvider.notifier).sendCustom(command)
              : null,
          child: const Text('Test'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: command == null
              ? null
              : () => Navigator.pop(context, command),
          child: const Text('Add'),
        ),
      ],
    );
  }
}
