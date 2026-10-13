import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/discovery/discovered_device.dart';
import '../../core/errors.dart';
import '../../core/storage/device_record.dart';
import '../../protocols/demo/demo_driver.dart';
import '../profiles/profiles_screen.dart';
import '../remote/remote_screen.dart';
import '../remote/remote_session.dart';
import '../settings/settings_screen.dart';
import 'saved_devices.dart';

class DevicesScreen extends ConsumerStatefulWidget {
  const DevicesScreen({super.key});

  @override
  ConsumerState<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends ConsumerState<DevicesScreen> {
  final _found = <String, DiscoveredDevice>{};
  StreamSubscription<DiscoveredDevice>? _scan;
  String? _scanError;

  bool get _scanning => _scan != null;

  @override
  void initState() {
    super.initState();
    _startScan();
  }

  @override
  void dispose() {
    _scan?.cancel();
    super.dispose();
  }

  void _startScan() {
    _scan?.cancel();
    setState(() {
      _found.clear();
      _scanError = null;
    });
    _scan = ref
        .read(discoveryServiceProvider)
        .scan()
        .listen(
          (device) => setState(() => _found[device.id] = device),
          onError: (Object e) => setState(
            () => _scanError =
                'Network scan failed. Check that the app has local network access, '
                'or add the TV by IP address.',
          ),
          onDone: () {
            if (mounted) setState(() => _scan = null);
          },
        );
  }

  Future<void> _open(DeviceRecord device) async {
    final session = ref.read(remoteSessionProvider.notifier);
    unawaited(session.connect(device));
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const RemoteScreen()));
  }

  Future<void> _addByIp() async {
    final device = await showDialog<DiscoveredDevice>(
      context: context,
      builder: (_) => const _AddByIpDialog(),
    );
    if (device != null) await _open(device.toRecord());
  }

  Future<void> _edit(DeviceRecord device) async {
    final updated = await showDialog<DeviceRecord>(
      context: context,
      builder: (_) => _EditDeviceDialog(device: device),
    );
    if (updated != null) {
      await ref.read(savedDevicesProvider.notifier).save(updated);
    }
  }

  Future<void> _forget(DeviceRecord device) async {
    if (!await requireParent(context, ref) || !mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Forget ${device.name}?'),
        content: const Text(
          'The pairing is removed from this phone. You will need to approve '
          'the phone on the TV again to reconnect.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Forget'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(savedDevicesProvider.notifier).remove(device);
    }
  }

  @override
  Widget build(BuildContext context) {
    final saved = ref.watch(savedDevicesProvider).value ?? const [];
    final savedIds = saved.map((d) => d.id).toSet();
    final savedIps = saved.map((d) => '${d.protocol}@${d.ipAddress}').toSet();
    final newDevices = _found.values
        .where(
          (d) =>
              !savedIds.contains(d.id) &&
              !savedIps.contains('${d.protocol}@${d.ipAddress}'),
        )
        .toList();

    // Group saved TVs by room; TVs without a room go last.
    final rooms = <String, List<DeviceRecord>>{};
    for (final device in saved) {
      rooms.putIfAbsent(device.room ?? '', () => []).add(device);
    }
    final roomNames = rooms.keys.toList()
      ..sort(
        (a, b) => a.isEmpty
            ? 1
            : b.isEmpty
            ? -1
            : a.compareTo(b),
      );

    return Scaffold(
      appBar: AppBar(
        title: const Text('TVs'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () async {
              if (!await requireParent(context, ref) || !context.mounted) {
                return;
              }
              await Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addByIp,
        icon: const Icon(Icons.add),
        label: const Text('Add by IP'),
      ),
      body: RefreshIndicator(
        onRefresh: () async => _startScan(),
        child: ListView(
          padding: const EdgeInsets.only(bottom: 96),
          children: [
            for (final room in roomNames) ...[
              _SectionHeader(
                room.isEmpty
                    ? (roomNames.length == 1 ? 'Saved TVs' : 'Other TVs')
                    : room,
              ),
              for (final device in rooms[room]!)
                ListTile(
                  leading: const Icon(Icons.tv),
                  title: Text(device.name),
                  subtitle: Text(
                    [
                      Protocols.label(device.protocol),
                      if (device.ipAddress != null) device.ipAddress!,
                    ].join(' · '),
                  ),
                  onTap: () => _open(device),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: device.isFavorite
                            ? 'Remove from favorites'
                            : 'Add to favorites',
                        icon: Icon(
                          device.isFavorite ? Icons.star : Icons.star_border,
                        ),
                        onPressed: () => ref
                            .read(savedDevicesProvider.notifier)
                            .toggleFavorite(device),
                      ),
                      PopupMenuButton<String>(
                        tooltip: 'More',
                        onSelected: (action) =>
                            action == 'edit' ? _edit(device) : _forget(device),
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'edit',
                            child: Text('Rename / room'),
                          ),
                          PopupMenuItem(value: 'forget', child: Text('Forget')),
                        ],
                      ),
                    ],
                  ),
                ),
            ],
            _SectionHeader(
              'On this network',
              trailing: _scanning
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : IconButton(
                      tooltip: 'Scan again',
                      icon: const Icon(Icons.refresh),
                      onPressed: _startScan,
                    ),
            ),
            if (_scanError != null)
              ListTile(
                leading: const Icon(Icons.error_outline),
                title: Text(_scanError!),
              ),
            for (final device in newDevices)
              ListTile(
                leading: const Icon(Icons.tv_outlined),
                title: Text(device.name),
                subtitle: Text(
                  '${Protocols.label(device.protocol)} · ${device.ipAddress}',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _open(device.toRecord()),
              ),
            if (!savedIds.contains(DemoDriver.device.id))
              ListTile(
                leading: const Icon(Icons.play_circle_outline),
                title: const Text('Try the demo TV'),
                subtitle: const Text(
                  'A simulated TV for trying the app without one.',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _open(DemoDriver.device),
              ),
            if (!_scanning && newDevices.isEmpty && _scanError == null)
              const ListTile(
                leading: Icon(Icons.search_off),
                title: Text('No new TVs found'),
                subtitle: Text(
                  'Make sure the TV is on and on the same Wi-Fi. Some routers '
                  'block discovery; you can add the TV by IP address.',
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title, {this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 8, 4),
    child: Row(
      children: [
        Expanded(
          child: Semantics(
            header: true,
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleSmall
                  ?.copyWith(color: Theme.of(context).colorScheme.primary),
            ),
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

class _AddByIpDialog extends ConsumerStatefulWidget {
  const _AddByIpDialog();

  @override
  ConsumerState<_AddByIpDialog> createState() => _AddByIpDialogState();
}

class _AddByIpDialogState extends ConsumerState<_AddByIpDialog> {
  final _ip = TextEditingController();
  String? _protocol;
  String? _error;
  bool _busy = false;

  static final _ipPattern = RegExp(r'^(\d{1,3}\.){3}\d{1,3}$');

  @override
  void dispose() {
    _ip.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final ip = _ip.text.trim();
    if (!_ipPattern.hasMatch(ip)) {
      setState(() => _error = 'Enter an IPv4 address such as 192.168.1.20');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final device = await ref
          .read(discoveryServiceProvider)
          .probe(ip, protocol: _protocol);
      if (mounted) Navigator.pop(context, device);
    } on TvRemoteException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final drivers = ref.watch(driversProvider);
    return AlertDialog(
      title: const Text('Add TV by IP address'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _ip,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'IP address',
              hintText: '192.168.1.20',
              errorText: _error,
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            isExpanded: true,
            initialValue: _protocol,
            decoration: const InputDecoration(labelText: 'TV type'),
            items: [
              const DropdownMenuItem(value: null, child: Text('Detect')),
              for (final d in drivers)
                if (d.protocol != Protocols.demo)
                  DropdownMenuItem(
                    value: d.protocol,
                    child: Text(d.displayName),
                  ),
            ],
            onChanged: (v) => setState(() => _protocol = v),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Connect'),
        ),
      ],
    );
  }
}

class _EditDeviceDialog extends StatefulWidget {
  const _EditDeviceDialog({required this.device});

  final DeviceRecord device;

  @override
  State<_EditDeviceDialog> createState() => _EditDeviceDialogState();
}

class _EditDeviceDialogState extends State<_EditDeviceDialog> {
  late final _name = TextEditingController(text: widget.device.name);
  late final _room = TextEditingController(text: widget.device.room ?? '');

  @override
  void dispose() {
    _name.dispose();
    _room.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Edit TV'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _name,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        TextField(
          controller: _room,
          decoration: const InputDecoration(
            labelText: 'Room',
            hintText: 'Living room',
          ),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          final name = _name.text.trim();
          final room = _room.text.trim();
          Navigator.pop(
            context,
            DeviceRecord(
              id: widget.device.id,
              name: name.isEmpty ? widget.device.name : name,
              protocol: widget.device.protocol,
              manufacturer: widget.device.manufacturer,
              model: widget.device.model,
              ipAddress: widget.device.ipAddress,
              macAddress: widget.device.macAddress,
              room: room.isEmpty ? null : room,
              lastConnected: widget.device.lastConnected,
              isFavorite: widget.device.isFavorite,
            ),
          );
        },
        child: const Text('Save'),
      ),
    ],
  );
}
