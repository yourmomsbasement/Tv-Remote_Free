import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/capabilities/remote_key.dart';
import '../../core/platform/haptics.dart';
import '../../ui/components/dpad.dart';
import '../../ui/components/remote_button.dart';
import '../../ui/themes/app_theme.dart';
import '../../ui/themes/remote_style.dart';
import '../settings/app_settings.dart';
import 'theme_definition.dart';
import 'theme_library.dart';

/// Lists built-in and imported remote themes; imports, exports and applies.
class ThemesScreen extends ConsumerWidget {
  const ThemesScreen({super.key});

  static void _snack(BuildContext context, String message) =>
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));

  Future<void> _apply(WidgetRef ref, ThemeDefinition theme) {
    final settings = ref.read(settingsProvider);
    return ref
        .read(appSettingsProvider.notifier)
        .save(settings.copyWith(themeId: theme.id));
  }

  Future<void> _importFromFile(BuildContext context, WidgetRef ref) async {
    final String text;
    try {
      final file = await FilePicker.pickFile(
        dialogTitle: 'Choose a theme file',
        type: FileType.custom,
        allowedExtensions: const ['json'],
      );
      if (file == null) return;
      final length = await file.length();
      if (length != null && length > maxThemeFileBytes) {
        if (context.mounted) {
          _snack(context, 'The theme file is too large (max 3 MB).');
        }
        return;
      }
      text = utf8.decode(await file.readAsBytes(), allowMalformed: true);
    } on Object catch (e) {
      if (context.mounted) _snack(context, 'Could not open the file: $e');
      return;
    }
    if (context.mounted) await _importText(context, ref, text);
  }

  Future<void> _importFromClipboard(BuildContext context, WidgetRef ref) async {
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    if (!context.mounted) return;
    if (text == null || text.trim().isEmpty) {
      _snack(context, 'The clipboard is empty.');
      return;
    }
    await _importText(context, ref, text);
  }

  Future<void> _importText(
    BuildContext context,
    WidgetRef ref,
    String text,
  ) async {
    final ThemeDefinition theme;
    try {
      theme = ThemeDefinition.parse(text);
    } on ThemeFormatException catch (e) {
      _snack(context, e.message);
      return;
    }
    final existing = (ref.read(themeLibraryProvider).value ?? const [])
        .where((t) => t.id == theme.id)
        .firstOrNull;
    final apply = await showDialog<bool>(
      context: context,
      builder: (_) => _ImportDialog(theme: theme, replaces: existing),
    );
    if (apply == null) return;
    await ref.read(themeLibraryProvider.notifier).install(theme);
    if (apply) await _apply(ref, theme);
    if (context.mounted) {
      _snack(context, apply ? '${theme.name} applied' : '${theme.name} added');
    }
  }

  Future<void> _export(BuildContext context, ThemeDefinition theme) async {
    final name = theme.id.replaceAll(RegExp(r'^(builtin|user)\.'), '');
    try {
      final path = await FilePicker.saveFile(
        dialogTitle: 'Save theme',
        fileName: '$name.tvtheme.json',
        bytes: utf8.encode(theme.source),
        mimeType: 'application/json',
      );
      if (path != null && context.mounted) _snack(context, 'Theme saved');
    } on Object {
      if (context.mounted) {
        _snack(context, 'Could not save the file. Try "Copy as text".');
      }
    }
  }

  Future<void> _copy(BuildContext context, ThemeDefinition theme) async {
    await Clipboard.setData(ClipboardData(text: theme.source));
    if (context.mounted) _snack(context, 'Theme copied as text');
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    ThemeDefinition theme,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${theme.name}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(themeLibraryProvider.notifier).remove(theme);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themes = ref.watch(themeLibraryProvider);
    final activeId = ref.watch(settingsProvider.select((s) => s.themeId));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Remote themes'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Import theme',
            icon: const Icon(Icons.file_download_outlined),
            onSelected: (v) => v == 'file'
                ? _importFromFile(context, ref)
                : _importFromClipboard(context, ref),
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
      body: themes.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load themes: $e')),
        data: (list) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            for (final theme in list)
              _ThemeCard(
                theme: theme,
                active:
                    theme.id == activeId ||
                    (activeId == defaultThemeId && theme.id == defaultThemeId),
                onApply: () => _apply(ref, theme),
                onAction: (action) => switch (action) {
                  'export' => _export(context, theme),
                  'copy' => _copy(context, theme),
                  'delete' => _delete(context, ref, theme),
                  _ => null,
                },
              ),
            const SizedBox(height: 8),
            const ListTile(
              leading: Icon(Icons.brush_outlined),
              title: Text('Make your own'),
              subtitle: Text(
                'Export any theme as a starting template, edit the colours '
                'in a text editor, then import it. The format is described '
                'in docs/THEMES.md in the project repository.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThemeCard extends StatelessWidget {
  const _ThemeCard({
    required this.theme,
    required this.active,
    required this.onApply,
    required this.onAction,
  });

  final ThemeDefinition theme;
  final bool active;
  final VoidCallback onApply;
  final void Function(String action) onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final modes = [
      if (theme.supportsLight) 'Light',
      if (theme.supportsDark) 'Dark',
    ].join(' · ');
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: active ? scheme.primary : scheme.outlineVariant,
          width: active ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onApply,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (theme.supportsLight)
                  Expanded(
                    child: ThemePreview(
                      theme: theme,
                      brightness: Brightness.light,
                    ),
                  ),
                if (theme.supportsDark)
                  Expanded(
                    child: ThemePreview(
                      theme: theme,
                      brightness: Brightness.dark,
                    ),
                  ),
              ],
            ),
            ListTile(
              title: Text(theme.name),
              subtitle: Text(
                [
                  if (theme.description != null) theme.description!,
                  [
                    if (theme.author != null) 'by ${theme.author}',
                    modes,
                    if (theme.builtIn) 'Built in',
                  ].join(' · '),
                ].join('\n'),
              ),
              isThreeLine: theme.description != null,
              leading: Icon(
                active ? Icons.check_circle : Icons.circle_outlined,
                color: active ? scheme.primary : null,
                semanticLabel: active ? 'Selected' : null,
              ),
              trailing: PopupMenuButton<String>(
                tooltip: 'More',
                onSelected: onAction,
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'export',
                    child: Text('Save as file'),
                  ),
                  const PopupMenuItem(
                    value: 'copy',
                    child: Text('Copy as text'),
                  ),
                  if (!theme.builtIn)
                    const PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A small, non-interactive rendering of the remote in [theme].
class ThemePreview extends StatelessWidget {
  const ThemePreview({
    super.key,
    required this.theme,
    required this.brightness,
    this.height = 150,
  });

  final ThemeDefinition theme;
  final Brightness brightness;
  final double height;

  @override
  Widget build(BuildContext context) {
    final data = AppTheme.build(brightness, theme);
    return Theme(
      data: data,
      child: Builder(
        builder: (context) {
          final style = RemoteStyle.of(context);
          final background = style.background;
          return ExcludeSemantics(
            child: IgnorePointer(
              child: Container(
                height: height,
                decoration: BoxDecoration(
                  color: data.scaffoldBackgroundColor,
                  image: background == null
                      ? null
                      : DecorationImage(
                          image: MemoryImage(background.bytes),
                          fit: background.fit,
                          opacity: background.opacity,
                        ),
                ),
                padding: const EdgeInsets.all(8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Column(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        RemoteButton(
                          icon: Icons.power_settings_new,
                          label: 'Power',
                          size: 34,
                          filled: true,
                          haptics: HapticStrength.off,
                          onPressed: () {},
                        ),
                        RemoteButton(
                          icon: Icons.home_outlined,
                          label: 'Home',
                          size: 34,
                          haptics: HapticStrength.off,
                          onPressed: () {},
                        ),
                      ],
                    ),
                    DPad(
                      size: height - 24,
                      haptics: HapticStrength.off,
                      onKey: (RemoteKey _) {},
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ImportDialog extends StatelessWidget {
  const _ImportDialog({required this.theme, this.replaces});

  final ThemeDefinition theme;
  final ThemeDefinition? replaces;

  @override
  Widget build(BuildContext context) {
    final warnings = theme.contrastWarnings();
    final error = Theme.of(context).colorScheme.error;
    return AlertDialog(
      title: Text('Import "${theme.name}"?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Row(
                children: [
                  if (theme.supportsLight)
                    Expanded(
                      child: ThemePreview(
                        theme: theme,
                        brightness: Brightness.light,
                        height: 120,
                      ),
                    ),
                  if (theme.supportsDark)
                    Expanded(
                      child: ThemePreview(
                        theme: theme,
                        brightness: Brightness.dark,
                        height: 120,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (theme.author != null) Text('By ${theme.author}'),
            if (theme.description != null) Text(theme.description!),
            if (replaces != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  replaces!.builtIn
                      ? 'This has the same id as a built-in theme.'
                      : 'This replaces your existing "${replaces!.name}".',
                ),
              ),
            for (final w in warnings)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber, size: 18, color: error),
                    const SizedBox(width: 6),
                    Expanded(child: Text(w)),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Add'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Add & apply'),
        ),
      ],
    );
  }
}
