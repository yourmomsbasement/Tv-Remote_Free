import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/devices/devices_screen.dart';
import '../features/remote/remote_session.dart';
import '../features/remote/sleep_timer.dart';
import '../features/settings/app_settings.dart';
import '../features/themes/theme_library.dart';
import '../ui/themes/app_theme.dart';

class TvRemoteApp extends ConsumerStatefulWidget {
  const TvRemoteApp({super.key});

  @override
  ConsumerState<TvRemoteApp> createState() => _TvRemoteAppState();
}

class _TvRemoteAppState extends ConsumerState<TvRemoteApp> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Drop TV connections in the background to save battery; restore them
    // when the app returns.
    _lifecycle = AppLifecycleListener(
      onPause: () {
        // A running sleep timer needs the connection to switch the TV off.
        if (ref.read(sleepTimerProvider).active) return;
        ref.read(remoteSessionProvider.notifier).suspend();
      },
      onResume: () => ref.read(remoteSessionProvider.notifier).resume(),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(settingsProvider.select((s) => s.themeMode));
    final theme = ref.watch(activeThemeProvider);
    return MaterialApp(
      title: 'TV Remote Free',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(theme),
      darkTheme: AppTheme.dark(theme),
      themeMode: effectiveThemeMode(themeMode, theme),
      home: const DevicesScreen(),
    );
  }
}
