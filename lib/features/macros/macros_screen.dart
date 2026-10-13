import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/adapter/smart_tv_adapter.dart';
import '../../core/capabilities/remote_key.dart';
import '../applications/app_links.dart';
import '../devices/saved_devices.dart';
import '../remote/remote_session.dart';
import 'macro.dart';
import 'macro_library.dart';
import 'macro_runner.dart';

/// Lists saved macros; run, create and edit them.
class MacrosScreen extends ConsumerWidget {
  const MacrosScreen({super.key});

  static Future<void> run(BuildContext context, WidgetRef ref, Macro macro) {
    ref.read(macroRunnerProvider.notifier).run(macro);
    return showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      builder: (_) => const _RunSheet(),
    );
  }

  Future<void> _edit(BuildContext context, Macro macro) =>
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => MacroEditor(initial: macro)));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final macros = ref.watch(macroLibraryProvider);
    final devices = ref.watch(savedDevicesProvider).value ?? const [];
    String deviceName(String? id) => id == null
        ? 'Current TV'
        : devices.where((d) => d.id == id).firstOrNull?.name ?? 'Removed TV';

    return Scaffold(
      appBar: AppBar(title: const Text('Macros')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(
          context,
          Macro(id: MacroLibrary.newId(), name: '', steps: const []),
        ),
        icon: const Icon(Icons.add),
        label: const Text('New macro'),
      ),
      body: macros.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load macros: $e')),
        data: (list) => list.isEmpty
            ? _EmptyState(
                onExample: () =>
                    _edit(context, Macro.movieNight(MacroLibrary.newId())),
              )
            : ListView(
                padding: const EdgeInsets.only(bottom: 96),
                children: [
                  for (final macro in list)
                    ListTile(
                      leading: const Icon(Icons.playlist_play),
                      title: Text(macro.name),
                      subtitle: Text(
                        '${deviceName(macro.deviceId)} · '
                        '${macro.steps.length} '
                        'step${macro.steps.length == 1 ? '' : 's'}',
                      ),
                      onTap: () => _edit(context, macro),
                      trailing: IconButton.filledTonal(
                        tooltip: 'Run ${macro.name}',
                        icon: const Icon(Icons.play_arrow),
                        onPressed: macro.steps.isEmpty
                            ? null
                            : () => run(context, ref, macro),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onExample});

  final VoidCallback onExample;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.auto_awesome, size: 48),
          const SizedBox(height: 16),
          const Text(
            'Macros run several steps with one tap — for example: turn '
            'on the TV, wait for it, open Netflix and set the volume.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: onExample,
            child: const Text('Start from "Movie night"'),
          ),
        ],
      ),
    ),
  );
}

/// Progress of the running macro, step by step.
class _RunSheet extends ConsumerWidget {
  const _RunSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final run = ref.watch(macroRunnerProvider);
    final macro = run.macro;
    if (macro == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              run.running
                  ? 'Running ${macro.name}…'
                  : run.succeeded
                  ? '${macro.name} finished'
                  : '${macro.name} did not finish',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (var i = 0; i < macro.steps.length; i++)
                    ListTile(
                      dense: true,
                      leading: switch (run.outcomes[i].status) {
                        StepStatus.pending => const Icon(
                          Icons.radio_button_unchecked,
                        ),
                        StepStatus.running => const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        StepStatus.done => Icon(
                          Icons.check_circle,
                          color: scheme.primary,
                        ),
                        StepStatus.skipped => const Icon(Icons.redo),
                        StepStatus.failed => Icon(
                          Icons.error,
                          color: scheme.error,
                        ),
                        StepStatus.notRun => const Icon(Icons.block),
                      },
                      title: Text(macro.steps[i].describe()),
                      subtitle: run.outcomes[i].message == null
                          ? null
                          : Text(run.outcomes[i].message!),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            run.running
                ? OutlinedButton(
                    onPressed: () =>
                        ref.read(macroRunnerProvider.notifier).cancel(),
                    child: const Text('Cancel'),
                  )
                : FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
          ],
        ),
      ),
    );
  }
}

/// Creates or edits a macro.
class MacroEditor extends ConsumerStatefulWidget {
  const MacroEditor({super.key, required this.initial});

  final Macro initial;

  @override
  ConsumerState<MacroEditor> createState() => _MacroEditorState();
}

class _MacroEditorState extends ConsumerState<MacroEditor> {
  late Macro _macro = widget.initial;
  late final _name = TextEditingController(text: widget.initial.name);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _isNew => !(ref.read(macroLibraryProvider).value ?? const []).any(
    (m) => m.id == _macro.id,
  );

  Macro get _current => _macro.copyWith(
    name: _name.text.trim().isEmpty ? 'My macro' : _name.text.trim(),
  );

  Future<void> _save() async {
    await ref.read(macroLibraryProvider.notifier).save(_current);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    await ref.read(macroLibraryProvider.notifier).remove(_macro);
    if (mounted) Navigator.pop(context);
  }

  void _setSteps(List<MacroStep> steps) =>
      setState(() => _macro = _macro.copyWith(steps: steps));

  Future<void> _addStep() async {
    final step = await showModalBottomSheet<MacroStep>(
      context: context,
      showDragHandle: true,
      builder: (_) => const _StepTypePicker(),
    );
    if (step != null) _setSteps([..._macro.steps, step]);
  }

  Future<void> _editStep(int index) async {
    final updated = await _StepTypePicker.configure(
      context,
      _macro.steps[index],
    );
    if (updated != null) {
      _setSteps([..._macro.steps]..[index] = updated);
    }
  }

  @override
  Widget build(BuildContext context) {
    final devices = ref.watch(savedDevicesProvider).value ?? const [];
    final session = ref.watch(remoteSessionProvider);
    // Warnings are shown when the macro's TV is the one connected now.
    final targetConnected =
        session.isConnected &&
        (_macro.deviceId == null || _macro.deviceId == session.device?.id);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'New macro' : 'Edit macro'),
        actions: [
          if (!_isNew)
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
          IconButton(
            tooltip: 'Run now',
            icon: const Icon(Icons.play_arrow),
            onPressed: _macro.steps.isEmpty
                ? null
                : () => MacrosScreen.run(context, ref, _current),
          ),
          TextButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addStep,
        icon: const Icon(Icons.add),
        label: const Text('Add step'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: 'Name',
              hintText: 'Movie night',
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            isExpanded: true,
            initialValue: devices.any((d) => d.id == _macro.deviceId)
                ? _macro.deviceId
                : null,
            decoration: const InputDecoration(labelText: 'TV'),
            items: [
              const DropdownMenuItem(
                value: null,
                child: Text('Whichever TV is connected'),
              ),
              for (final d in devices)
                DropdownMenuItem(value: d.id, child: Text(d.name)),
            ],
            onChanged: (id) =>
                setState(() => _macro = _macro.copyWith(deviceId: () => id)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Stop if a step fails'),
            subtitle: const Text(
              'Steps the TV does not support are always skipped.',
            ),
            value: _macro.stopOnError,
            onChanged: (v) =>
                setState(() => _macro = _macro.copyWith(stopOnError: v)),
          ),
          const Divider(),
          if (_macro.steps.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'No steps yet. Tap "Add step".',
                textAlign: TextAlign.center,
              ),
            ),
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            onReorderItem: (from, to) {
              final steps = [..._macro.steps];
              steps.insert(to, steps.removeAt(from));
              _setSteps(steps);
            },
            children: [
              for (var i = 0; i < _macro.steps.length; i++)
                ListTile(
                  key: ObjectKey(_macro.steps[i]),
                  contentPadding: EdgeInsets.zero,
                  leading: ReorderableDragStartListener(
                    index: i,
                    child: const Icon(Icons.drag_handle),
                  ),
                  title: Text('${i + 1}. ${_macro.steps[i].describe()}'),
                  subtitle: switch (targetConnected
                      ? _macro.steps[i].unsupportedReason(session.capabilities)
                      : null) {
                    final String reason => Text('Will be skipped: $reason'),
                    null => null,
                  },
                  onTap: () => _editStep(i),
                  trailing: IconButton(
                    tooltip: 'Remove step',
                    icon: const Icon(Icons.close),
                    onPressed: () => _setSteps([..._macro.steps]..removeAt(i)),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Chooses a step type, then configures it.
class _StepTypePicker extends StatelessWidget {
  const _StepTypePicker();

  static const _types = <(String, IconData, MacroStep)>[
    ('Turn on the TV', Icons.power, PowerOnStep()),
    ('Wait for the TV to respond', Icons.hourglass_bottom, WaitConnectedStep()),
    ('Press a button', Icons.radio_button_checked, KeyStep(RemoteKey.home)),
    ('Open an app or input', Icons.apps, LaunchAppStep(appId: '', appName: '')),
    ('Set the volume', Icons.volume_up, VolumeStep(15)),
    ('Wait', Icons.timer_outlined, DelayStep(2000)),
    ('Type text', Icons.keyboard, TextStep('')),
  ];

  /// Opens the settings dialog for [step]; returns null if cancelled.
  static Future<MacroStep?> configure(BuildContext context, MacroStep step) =>
      switch (step) {
        PowerOnStep() => Future.value(step),
        _ => showDialog<MacroStep>(
          context: context,
          builder: (_) => _StepDialog(step: step),
        ),
      };

  @override
  Widget build(BuildContext context) => SafeArea(
    child: ListView(
      shrinkWrap: true,
      children: [
        for (final (label, icon, template) in _types)
          ListTile(
            leading: Icon(icon),
            title: Text(label),
            onTap: () async {
              final step = await configure(context, template);
              if (context.mounted) Navigator.pop(context, step);
            },
          ),
      ],
    ),
  );
}

class _StepDialog extends ConsumerStatefulWidget {
  const _StepDialog({required this.step});

  final MacroStep step;

  @override
  ConsumerState<_StepDialog> createState() => _StepDialogState();
}

class _StepDialogState extends ConsumerState<_StepDialog> {
  late MacroStep _step = widget.step;
  late final _text = TextEditingController(
    text: switch (widget.step) {
      TextStep(:final text) => text,
      LaunchAppStep(:final appId) => appId,
      _ => '',
    },
  );
  Future<List<TvApp>>? _apps;

  @override
  void initState() {
    super.initState();
    if (widget.step is LaunchAppStep) {
      final session = ref.read(remoteSessionProvider);
      _apps = session.isConnected && session.capabilities.appList
          ? ref.read(remoteSessionProvider.notifier).listApps()
          : Future.value(
              session.capabilities.appLaunch ? knownAppLinks : const [],
            );
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  bool get _valid => switch (_step) {
    LaunchAppStep(:final appId) => appId.trim().isNotEmpty,
    TextStep(:final text) => text.isNotEmpty,
    _ => true,
  };

  Widget _content() => switch (_step) {
    WaitConnectedStep(:final timeoutSeconds) => _slider(
      'Give up after $timeoutSeconds s',
      timeoutSeconds.toDouble(),
      5,
      120,
      (v) => WaitConnectedStep(timeoutSeconds: v.round()),
    ),
    DelayStep(:final milliseconds) => _slider(
      DelayStep(milliseconds).describe(),
      milliseconds / 1000,
      0.5,
      30,
      (v) => DelayStep((v * 2).round() * 500),
    ),
    VolumeStep(:final level) => _slider(
      'Volume $level',
      level.toDouble(),
      0,
      100,
      (v) => VolumeStep(v.round()),
    ),
    KeyStep(:final key, :final times) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        DropdownButtonFormField<RemoteKey>(
          isExpanded: true,
          initialValue: key,
          decoration: const InputDecoration(labelText: 'Button'),
          items: [
            for (final k in RemoteKey.values)
              DropdownMenuItem(value: k, child: Text(keyLabel(k))),
          ],
          onChanged: (k) => setState(() => _step = KeyStep(k!, times: times)),
        ),
        _slider(
          'Press $times time${times == 1 ? '' : 's'}',
          times.toDouble(),
          1,
          10,
          (v) => KeyStep(key, times: v.round()),
        ),
      ],
    ),
    TextStep(:final submit) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _text,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Text'),
          onChanged: (v) => setState(() => _step = TextStep(v, submit: submit)),
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Press Enter afterwards'),
          value: submit,
          onChanged: (v) =>
              setState(() => _step = TextStep(_text.text, submit: v ?? false)),
        ),
      ],
    ),
    LaunchAppStep() => _appPicker(),
    PowerOnStep() => const SizedBox.shrink(),
  };

  Widget _slider(
    String label,
    double value,
    double min,
    double max,
    MacroStep Function(double) build,
  ) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label),
      Slider(
        value: value.clamp(min, max),
        min: min,
        max: max,
        onChanged: (v) => setState(() => _step = build(v)),
      ),
    ],
  );

  Widget _appPicker() => FutureBuilder<List<TvApp>>(
    future: _apps,
    builder: (context, snapshot) {
      final apps = snapshot.data ?? const <TvApp>[];
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (snapshot.connectionState == ConnectionState.waiting)
            const LinearProgressIndicator(),
          if (apps.isNotEmpty)
            SizedBox(
              height: 240,
              width: double.maxFinite,
              child: ListView(
                children: [
                  for (final app in apps)
                    ListTile(
                      selected: (_step as LaunchAppStep).appId == app.id,
                      leading: Icon(
                        (_step as LaunchAppStep).appId == app.id
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                      ),
                      title: Text(app.name),
                      onTap: () => setState(() {
                        _text.text = app.id;
                        _step = LaunchAppStep(appId: app.id, appName: app.name);
                      }),
                    ),
                ],
              ),
            )
          else if (snapshot.connectionState != ConnectionState.waiting)
            const Text(
              'Connect to the TV to choose from its apps, or '
              'enter the app id.',
            ),
          TextField(
            controller: _text,
            decoration: const InputDecoration(labelText: 'App id or link'),
            onChanged: (v) => setState(
              () => _step = LaunchAppStep(appId: v.trim(), appName: v.trim()),
            ),
          ),
        ],
      );
    },
  );

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(_step.describe()),
    content: SingleChildScrollView(child: _content()),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _valid ? () => Navigator.pop(context, _step) : null,
        child: const Text('OK'),
      ),
    ],
  );
}
