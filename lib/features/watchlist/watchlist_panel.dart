import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/content/content_link.dart';
import '../../core/platform/haptics.dart';
import '../remote/remote_session.dart';
import '../settings/app_settings.dart';
import 'watchlist.dart';

/// Saved movies, shows and videos, opened on the TV with one tap.
class WatchlistPanel extends ConsumerWidget {
  const WatchlistPanel({super.key});

  static void _snack(BuildContext context, String message) =>
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));

  Future<void> _open(
    BuildContext context,
    WidgetRef ref,
    WatchItem item,
  ) async {
    Haptics.play(HapticEvent.press, ref.read(settingsProvider).hapticStrength);
    final link = item.link;
    if (link == null) return;
    final exact = await ref
        .read(remoteSessionProvider.notifier)
        .openContent(link);
    if (!context.mounted || exact == null) return;
    _snack(
      context,
      exact
          ? 'Opening "${item.title}" on the TV'
          : 'Opened ${link.service.displayName}. This TV cannot jump straight '
                'to the title, so find it there.',
    );
  }

  Future<void> _menu(BuildContext context, WidgetRef ref, String action) async {
    final watchlist = ref.read(watchlistProvider.notifier);
    switch (action) {
      case 'export':
        try {
          await FilePicker.saveFile(
            dialogTitle: 'Save watchlist',
            fileName: 'watchlist.json',
            bytes: utf8.encode(await watchlist.export()),
            mimeType: 'application/json',
          );
        } on Object {
          if (context.mounted) _snack(context, 'Could not save the file.');
        }
      case 'copy':
        await Clipboard.setData(ClipboardData(text: await watchlist.export()));
        if (context.mounted) _snack(context, 'Watchlist copied as text');
      case 'import':
        try {
          final file = await FilePicker.pickFile(
            type: FileType.custom,
            allowedExtensions: const ['json'],
          );
          if (file == null) return;
          final count = await watchlist.import(
            utf8.decode(await file.readAsBytes(), allowMalformed: true),
          );
          if (context.mounted) _snack(context, 'Imported $count items');
        } on FormatException catch (e) {
          if (context.mounted) _snack(context, e.message);
        } on Object {
          if (context.mounted) _snack(context, 'Could not read the file.');
        }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(watchlistProvider).value ?? const <WatchItem>[];
    final session = ref.watch(remoteSessionProvider);
    final canOpen = session.isConnected && session.capabilities.contentLaunch;
    final toWatch = items.where((i) => !i.watched).toList();
    final watched = items.where((i) => i.watched).toList();

    Widget tile(WatchItem item) => Dismissible(
      key: ValueKey(item.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        color: Theme.of(context).colorScheme.errorContainer,
        child: const Icon(Icons.delete_outline),
      ),
      onDismissed: (_) {
        final watchlist = ref.read(watchlistProvider.notifier);
        watchlist.remove(item);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text('Removed "${item.title}"'),
              action: SnackBarAction(
                label: 'Undo',
                onPressed: () =>
                    watchlist.addFromText(item.url, title: item.title),
              ),
            ),
          );
      },
      child: ListTile(
        leading: CircleAvatar(
          child: Text(item.service.displayName.characters.first),
        ),
        title: Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text(item.service.displayName),
        enabled: canOpen,
        onTap: canOpen ? () => _open(context, ref, item) : null,
        trailing: Checkbox(
          value: item.watched,
          semanticLabel: 'Watched',
          onChanged: (v) =>
              ref.read(watchlistProvider.notifier).setWatched(item, v ?? false),
        ),
      ),
    );

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
          child: Row(
            children: [
              FilledButton.tonalIcon(
                onPressed: () => showAddToWatchlist(context),
                icon: const Icon(Icons.add_link),
                label: const Text('Add link'),
              ),
              const Spacer(),
              PopupMenuButton<String>(
                tooltip: 'Backup',
                onSelected: (a) => _menu(context, ref, a),
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'export',
                    child: Text('Save backup file'),
                  ),
                  PopupMenuItem(
                    value: 'copy',
                    child: Text('Copy backup as text'),
                  ),
                  PopupMenuItem(value: 'import', child: Text('Import backup')),
                ],
              ),
            ],
          ),
        ),
        if (!canOpen && session.isConnected)
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('This TV cannot open links from the phone.'),
          ),
        if (items.isEmpty)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Text(
              'Save movies, shows and videos to watch on the TV later. Share '
              'a link to this app from YouTube, Netflix or a browser (Android), '
              'or copy a link and tap "Add link".',
              textAlign: TextAlign.center,
            ),
          ),
        for (final item in toWatch) tile(item),
        if (watched.isNotEmpty)
          ExpansionTile(
            title: Text('Watched (${watched.length})'),
            children: [for (final item in watched) tile(item)],
          ),
      ],
    );
  }
}

/// Asks for a link (prefilled from [sharedText] or the clipboard) and title.
Future<void> showAddToWatchlist(BuildContext context, {String? sharedText}) =>
    showDialog<void>(
      context: context,
      builder: (_) => _AddDialog(sharedText: sharedText),
    );

class _AddDialog extends ConsumerStatefulWidget {
  const _AddDialog({this.sharedText});

  final String? sharedText;

  @override
  ConsumerState<_AddDialog> createState() => _AddDialogState();
}

class _AddDialogState extends ConsumerState<_AddDialog> {
  late final _link = TextEditingController(text: widget.sharedText ?? '');
  final _title = TextEditingController();
  ContentLink? _parsed;
  String? _error;

  @override
  void initState() {
    super.initState();
    _onLinkChanged(_link.text);
  }

  @override
  void dispose() {
    _link.dispose();
    _title.dispose();
    super.dispose();
  }

  void _onLinkChanged(String text) {
    final parsed = ContentLink.parse(text);
    setState(() {
      _parsed = parsed;
      _error = null;
      if (parsed != null && _title.text.isEmpty) {
        _title.text = ContentLink.suggestTitle(text, parsed);
      }
    });
  }

  Future<void> _paste() async {
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
    _link.text = text;
    _title.clear();
    _onLinkChanged(text);
  }

  Future<void> _save() async {
    final item = await ref
        .read(watchlistProvider.notifier)
        .addFromText(_link.text, title: _title.text);
    if (!mounted) return;
    if (item == null) {
      setState(
        () => _error = 'No link found. Paste a link to a show or video.',
      );
      return;
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Add to watchlist'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _link,
            decoration: InputDecoration(
              labelText: 'Link',
              hintText: 'https://www.youtube.com/watch?v=…',
              errorText: _error,
              helperText: _parsed == null
                  ? null
                  : _parsed!.service == StreamingService.other
                  ? 'Opens on TVs that can open web links'
                  : _parsed!.service.displayName,
              suffixIcon: IconButton(
                tooltip: 'Paste',
                icon: const Icon(Icons.content_paste),
                onPressed: _paste,
              ),
            ),
            keyboardType: TextInputType.url,
            onChanged: _onLinkChanged,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _title,
            decoration: const InputDecoration(labelText: 'Title'),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _parsed == null ? null : _save,
        child: const Text('Add'),
      ),
    ],
  );
}
