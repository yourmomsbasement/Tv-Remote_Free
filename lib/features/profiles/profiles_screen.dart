import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/adapter/smart_tv_adapter.dart';
import '../remote/remote_session.dart';
import 'profile.dart';
import 'profiles.dart';

/// Asks for the household PIN. Returns the entered PIN or null.
Future<String?> askForPin(
  BuildContext context, {
  String title = 'Enter household PIN',
  String? message,
}) => showDialog<String>(
  context: context,
  builder: (_) => _PinEntryDialog(title: title, message: message),
);

/// Lets a parent through: always true outside child profiles; inside one,
/// true only after the correct PIN.
Future<bool> requireParent(BuildContext context, WidgetRef ref) async {
  if (!ref.read(activeProfileProvider).child) return true;
  final pin = await askForPin(
    context,
    message: 'This is locked in child mode.',
  );
  if (pin == null) return false;
  final ok = await ref.read(profilesProvider.notifier).checkPin(pin);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Wrong PIN')));
  }
  return ok;
}

/// Picks the active profile (from the remote's app bar).
Future<void> showProfileSwitcher(BuildContext context, WidgetRef ref) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => const _ProfileSwitcher(),
    );

class _ProfileSwitcher extends ConsumerWidget {
  const _ProfileSwitcher();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(profilesProvider).value ?? const ProfilesState();
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          for (final p in state.profiles)
            ListTile(
              leading: Icon(p.child ? Icons.child_care : Icons.person_outline),
              title: Text(p.name),
              trailing: p.id == state.activeId ? const Icon(Icons.check) : null,
              onTap: () => _switch(context, ref, state, p),
            ),
          ListTile(
            leading: const Icon(Icons.manage_accounts_outlined),
            title: const Text('Manage profiles'),
            onTap: () async {
              if (!await requireParent(context, ref) || !context.mounted) {
                return;
              }
              // Close the sheet, then open the screen from the page below it.
              final navigator = Navigator.of(context)..pop();
              await navigator.push(
                MaterialPageRoute(builder: (_) => const ProfilesScreen()),
              );
            },
          ),
        ],
      ),
    );
  }

  static Future<void> _switch(
    BuildContext context,
    WidgetRef ref,
    ProfilesState state,
    Profile target,
  ) async {
    String? pin;
    if (state.active.child && target.id != state.activeId) {
      pin = await askForPin(context, message: 'Leaving ${state.active.name}');
      if (pin == null) return;
    }
    final ok = await ref
        .read(profilesProvider.notifier)
        .activate(target.id, pin: pin);
    if (!context.mounted) return;
    if (ok) {
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Wrong PIN')));
    }
  }
}

/// Manages household profiles and the PIN.
class ProfilesScreen extends ConsumerWidget {
  const ProfilesScreen({super.key});

  Future<void> _changePin(BuildContext context, WidgetRef ref) async {
    final profiles = ref.read(profilesProvider.notifier);
    final state = await ref.read(profilesProvider.future);
    if (!context.mounted) return;
    if (state.hasPin) {
      final old = await askForPin(context, title: 'Current PIN');
      if (old == null || !context.mounted) return;
      if (!await profiles.checkPin(old)) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('Wrong PIN')));
        }
        return;
      }
    }
    if (!context.mounted) return;
    final pin = await askForPin(
      context,
      title: 'New PIN',
      message: '4 to 8 digits. Keep it from the kids.',
    );
    if (pin != null) await profiles.setPin(pin);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(profilesProvider).value ?? const ProfilesState();
    return Scaffold(
      appBar: AppBar(title: const Text('Household profiles')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ProfileEditor(
              initial: Profile(
                id: Profiles.newId(),
                name: '',
                child: true,
                simplified: true,
              ),
            ),
          ),
        ),
        icon: const Icon(Icons.person_add_alt),
        label: const Text('Add profile'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          for (final p in state.profiles)
            ListTile(
              leading: Icon(p.child ? Icons.child_care : Icons.person_outline),
              title: Text(p.name),
              subtitle: Text(_summary(p)),
              trailing: p.id == state.activeId
                  ? const Chip(label: Text('Active'))
                  : null,
              onTap: p.id == Profile.everyoneId
                  ? null
                  : () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ProfileEditor(initial: p),
                      ),
                    ),
            ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.pin_outlined),
            title: Text(
              state.hasPin ? 'Change household PIN' : 'Set household PIN',
            ),
            subtitle: const Text(
              'Needed to leave a child profile and to open '
              'settings, macros and themes while one is active.',
            ),
            onTap: () => _changePin(context, ref),
          ),
          const _HonestyNote(),
        ],
      ),
    );
  }

  static String _summary(Profile p) {
    if (p.id == Profile.everyoneId) return 'No restrictions';
    return [
      if (p.child) 'Child mode',
      if (p.simplified) 'Simple remote',
      if (p.allowedApps != null) '${p.allowedApps!.length} apps allowed',
      if (p.maxVolume != null) 'Volume ≤ ${p.maxVolume}',
      if (p.schedule != null) 'Viewing hours',
    ].join(' · ');
  }
}

class _HonestyNote extends StatelessWidget {
  const _HonestyNote();

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.all(16),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Profiles limit what this phone app does. They cannot stop '
              'someone using the TV\'s own remote, another phone, or the '
              'TV\'s menus. For real restrictions, also use the parental '
              'controls built into the TV and streaming apps.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    ),
  );
}

/// Creates or edits a profile.
class ProfileEditor extends ConsumerStatefulWidget {
  const ProfileEditor({super.key, required this.initial});

  final Profile initial;

  @override
  ConsumerState<ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends ConsumerState<ProfileEditor> {
  late Profile _p = widget.initial;
  late final _name = TextEditingController(text: widget.initial.name);
  Future<List<TvApp>>? _apps;

  static const _dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  void initState() {
    super.initState();
    final session = ref.read(remoteSessionProvider);
    if (session.isConnected && session.capabilities.appList) {
      _apps = ref.read(remoteSessionProvider.notifier).listApps();
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _isNew => !(ref.read(profilesProvider).value?.profiles ?? const [])
      .any((p) => p.id == _p.id);

  Future<void> _save() async {
    final profiles = ref.read(profilesProvider.notifier);
    final state = await ref.read(profilesProvider.future);
    if (!mounted) return;
    if (_p.child && !state.hasPin) {
      final pin = await askForPin(
        context,
        title: 'Choose a household PIN',
        message: 'Child profiles need a PIN (4 to 8 digits) to leave them.',
      );
      if (pin == null) return;
      await profiles.setPin(pin);
    }
    final name = _name.text.trim();
    await profiles.save(_p.copyWith(name: name.isEmpty ? 'Kids' : name));
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    await ref.read(profilesProvider.notifier).remove(_p);
    if (mounted) Navigator.pop(context);
  }

  Future<TimeOfDay?> _pickTime(TimeOfDay initial) =>
      showTimePicker(context: context, initialTime: initial);

  Widget _allowedApps() {
    final allowed = _p.allowedApps;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Only allow some apps'),
          subtitle: const Text(
            'Other apps are hidden from the Apps tab, '
            'and the watchlist is unavailable.',
          ),
          value: allowed != null,
          onChanged: (v) => setState(
            () => _p = _p.copyWith(allowedApps: () => v ? <String>{} : null),
          ),
        ),
        if (allowed != null)
          FutureBuilder<List<TvApp>>(
            future: _apps,
            builder: (context, snapshot) {
              final names =
                  {
                    ...allowed,
                    for (final a in snapshot.data ?? const <TvApp>[]) a.name,
                  }.toList()..sort(
                    (a, b) => a.toLowerCase().compareTo(b.toLowerCase()),
                  );
              if (_apps == null && names.isEmpty) {
                return const Text('Connect to a TV to choose from its apps.');
              }
              return Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final name in names)
                    FilterChip(
                      label: Text(name),
                      selected: allowed.any(
                        (a) =>
                            Profile.normalizeApp(a) ==
                            Profile.normalizeApp(name),
                      ),
                      onSelected: (on) => setState(() {
                        final next = {...allowed}
                          ..removeWhere(
                            (a) =>
                                Profile.normalizeApp(a) ==
                                Profile.normalizeApp(name),
                          );
                        if (on) next.add(name);
                        _p = _p.copyWith(allowedApps: () => next);
                      }),
                    ),
                ],
              );
            },
          ),
      ],
    );
  }

  Widget _schedule() {
    final schedule = _p.schedule;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Viewing hours'),
          subtitle: const Text('Outside these hours the remote is locked.'),
          value: schedule != null,
          onChanged: (v) => setState(
            () => _p = _p.copyWith(
              schedule: () => v
                  ? const ViewingSchedule(
                      days: {1, 2, 3, 4, 5, 6, 7},
                      start: TimeOfDay(hour: 7, minute: 0),
                      end: TimeOfDay(hour: 19, minute: 30),
                    )
                  : null,
            ),
          ),
        ),
        if (schedule != null) ...[
          Wrap(
            spacing: 4,
            children: [
              for (var d = 1; d <= 7; d++)
                FilterChip(
                  label: Text(_dayNames[d - 1]),
                  selected: schedule.days.contains(d),
                  onSelected: (on) => setState(() {
                    final days = {...schedule.days};
                    on ? days.add(d) : days.remove(d);
                    _p = _p.copyWith(
                      schedule: () => ViewingSchedule(
                        days: days,
                        start: schedule.start,
                        end: schedule.end,
                      ),
                    );
                  }),
                ),
            ],
          ),
          Row(
            children: [
              TextButton(
                onPressed: () async {
                  final t = await _pickTime(schedule.start);
                  if (t != null) {
                    setState(
                      () => _p = _p.copyWith(
                        schedule: () => ViewingSchedule(
                          days: schedule.days,
                          start: t,
                          end: schedule.end,
                        ),
                      ),
                    );
                  }
                },
                child: Text('From ${schedule.start.format(context)}'),
              ),
              TextButton(
                onPressed: () async {
                  final t = await _pickTime(schedule.end);
                  if (t != null) {
                    setState(
                      () => _p = _p.copyWith(
                        schedule: () => ViewingSchedule(
                          days: schedule.days,
                          start: schedule.start,
                          end: t,
                        ),
                      ),
                    );
                  }
                },
                child: Text('Until ${schedule.end.format(context)}'),
              ),
            ],
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(_isNew ? 'New profile' : 'Edit profile'),
      actions: [
        if (!_isNew)
          IconButton(
            tooltip: 'Delete',
            icon: const Icon(Icons.delete_outline),
            onPressed: _delete,
          ),
        TextButton(onPressed: _save, child: const Text('Save')),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: _name,
          decoration: const InputDecoration(
            labelText: 'Name',
            hintText: 'Kids',
          ),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Child mode'),
          subtitle: const Text(
            'Leaving this profile, settings, macros '
            'and themes need the household PIN.',
          ),
          value: _p.child,
          onChanged: (v) => setState(() => _p = _p.copyWith(child: v)),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Simple remote'),
          subtitle: const Text(
            'Only arrows, OK, Back, Home, volume and '
            'play/pause.',
          ),
          value: _p.simplified,
          onChanged: (v) => setState(() => _p = _p.copyWith(simplified: v)),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Maximum volume'),
          subtitle: const Text(
            'Needs a TV that reports its volume '
            '(e.g. LG); not enforceable on Roku.',
          ),
          value: _p.maxVolume != null,
          onChanged: (v) =>
              setState(() => _p = _p.copyWith(maxVolume: () => v ? 25 : null)),
        ),
        if (_p.maxVolume != null)
          Slider(
            value: _p.maxVolume!.toDouble(),
            min: 1,
            max: 100,
            divisions: 99,
            label: '${_p.maxVolume}',
            onChanged: (v) =>
                setState(() => _p = _p.copyWith(maxVolume: () => v.round())),
          ),
        const Divider(),
        _allowedApps(),
        const Divider(),
        _schedule(),
        const _HonestyNote(),
      ],
    ),
  );
}

class _PinEntryDialog extends StatefulWidget {
  const _PinEntryDialog({required this.title, this.message});

  final String title;
  final String? message;

  @override
  State<_PinEntryDialog> createState() => _PinEntryDialogState();
}

class _PinEntryDialogState extends State<_PinEntryDialog> {
  final _pin = TextEditingController();

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  void _submit() {
    if (Profiles.validPin(_pin.text)) Navigator.pop(context, _pin.text);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.message != null) Text(widget.message!),
        TextField(
          controller: _pin,
          autofocus: true,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 8,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(labelText: 'PIN'),
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _submit(),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: Profiles.validPin(_pin.text) ? _submit : null,
        child: const Text('OK'),
      ),
    ],
  );
}
