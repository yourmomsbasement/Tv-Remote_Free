import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/adapter/smart_tv_adapter.dart';
import '../applications/apps_panel.dart';
import '../keyboard/keyboard_panel.dart';
import '../settings/app_settings.dart';
import '../settings/settings_screen.dart';
import '../touchpad/touchpad_panel.dart';
import 'pin_dialog.dart';
import 'remote_panel.dart';
import 'remote_session.dart';
import '../../ui/themes/remote_style.dart';

class RemoteScreen extends ConsumerStatefulWidget {
  const RemoteScreen({super.key});

  @override
  ConsumerState<RemoteScreen> createState() => _RemoteScreenState();
}

class _RemoteScreenState extends ConsumerState<RemoteScreen>
    with SingleTickerProviderStateMixin {
  static const _keyboardTab = 2;
  late final _tabs = TabController(length: 4, vsync: this);
  final _keyboardFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _tabs.animation!.addListener(_hideKeyboardOffTab);
  }

  /// Dismisses the phone keyboard as soon as the user moves off the
  /// Keyboard tab, by tapping another tab or swiping past halfway.
  void _hideKeyboardOffTab() {
    if (!_keyboardFocus.hasFocus) return;
    // Programmatic switch *to* the keyboard (auto-open) is still animating.
    if (_tabs.indexIsChanging && _tabs.index == _keyboardTab) return;
    if ((_tabs.animation!.value - _keyboardTab).abs() >= 0.5) {
      _keyboardFocus.unfocus();
    }
  }

  @override
  void dispose() {
    _tabs.animation?.removeListener(_hideKeyboardOffTab);
    _tabs.dispose();
    _keyboardFocus.dispose();
    super.dispose();
  }

  void _openKeyboard() {
    _tabs.animateTo(_keyboardTab);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _keyboardFocus.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(remoteSessionProvider);

    // Automatic keyboard presentation when the TV reports a focused field.
    ref.listen(remoteSessionProvider.select((s) => s.textFieldFocused), (
      previous,
      focused,
    ) {
      if (focused &&
          previous != true &&
          ref.read(settingsProvider).keyboardAutoOpen) {
        _openKeyboard();
      }
    });

    // Show the code entry as soon as the TV displays a code.
    ref.listen(remoteSessionProvider.select((s) => s.awaitingPin), (
      previous,
      awaiting,
    ) {
      if (awaiting && previous != true) {
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => const PinDialog(),
        );
      }
    });

    ref.listen(remoteSessionProvider.select((s) => s.error), (_, error) {
      // Connection errors are shown in the banner; commands get a snackbar.
      if (error == null || !ref.read(remoteSessionProvider).isConnected) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(error.message)));
      ref.read(remoteSessionProvider.notifier).clearError();
    });

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(session.device?.name ?? 'Remote'),
            Text(
              _statusLabel(session),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          if (session.capabilities.textInput)
            IconButton(
              tooltip: 'Keyboard',
              icon: const Icon(Icons.keyboard),
              onPressed: _openKeyboard,
            ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(icon: Icon(Icons.settings_remote), text: 'Remote'),
            Tab(icon: Icon(Icons.touch_app_outlined), text: 'Touchpad'),
            Tab(icon: Icon(Icons.keyboard_outlined), text: 'Keyboard'),
            Tab(icon: Icon(Icons.apps), text: 'Apps'),
          ],
        ),
      ),
      body: _ThemedBackground(
        child: Column(
          children: [
            _ConnectionBanner(session: session),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  const RemotePanel(),
                  const TouchpadPanel(),
                  KeyboardPanel(focusNode: _keyboardFocus),
                  const AppsPanel(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _statusLabel(RemoteSessionState session) =>
      switch (session.status) {
        ConnectionStatus.connected => 'Connected',
        ConnectionStatus.connecting => 'Connecting…',
        ConnectionStatus.awaitingPairing => 'Waiting for approval on TV',
        ConnectionStatus.disconnected =>
          session.reconnecting ? 'Reconnecting…' : 'Disconnected',
      };
}

class _ConnectionBanner extends ConsumerWidget {
  const _ConnectionBanner({required this.session});

  final RemoteSessionState session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final remote = ref.read(remoteSessionProvider.notifier);
    if (session.awaitingPin) {
      return MaterialBanner(
        leading: const Icon(Icons.pin_outlined),
        content: const Text('Enter the code shown on your TV.'),
        actions: [
          FilledButton(
            onPressed: () => showDialog<void>(
              context: context,
              barrierDismissible: false,
              builder: (_) => const PinDialog(),
            ),
            child: const Text('Enter code'),
          ),
        ],
      );
    }
    if (session.awaitingPairing) {
      return const MaterialBanner(
        leading: Icon(Icons.tv),
        content: Text(
          'Accept the connection request on your TV screen using the TV '
          'remote.',
        ),
        actions: [
          SizedBox(width: 24, height: 24, child: CircularProgressIndicator()),
        ],
      );
    }
    if (session.status == ConnectionStatus.connecting) {
      return const LinearProgressIndicator();
    }
    if (session.status == ConnectionStatus.disconnected &&
        !session.reconnecting) {
      final error = session.error;
      return MaterialBanner(
        leading: const Icon(Icons.portable_wifi_off),
        content: Text(
          error?.message ??
              'Not connected. Make sure the TV is on and on the same Wi-Fi.',
        ),
        actions: [
          if (session.canPowerOn)
            TextButton(onPressed: remote.powerOn, child: const Text('Turn on')),
          TextButton(
            onPressed: remote.reconnect,
            child: const Text('Reconnect'),
          ),
        ],
      );
    }
    if (session.reconnecting) {
      return const LinearProgressIndicator();
    }
    return const SizedBox.shrink();
  }
}

/// Paints the active theme's background image, if it has one.
class _ThemedBackground extends StatelessWidget {
  const _ThemedBackground({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final background = RemoteStyle.of(context).background;
    if (background == null) return child;
    return DecoratedBox(
      decoration: BoxDecoration(
        image: DecorationImage(
          image: MemoryImage(background.bytes),
          fit: background.fit,
          opacity: background.opacity,
        ),
      ),
      child: child,
    );
  }
}
