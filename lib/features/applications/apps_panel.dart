import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/adapter/smart_tv_adapter.dart';
import '../../core/errors.dart';
import '../../core/platform/haptics.dart';
import '../settings/app_settings.dart';
import '../profiles/profiles.dart';
import '../remote/remote_session.dart';
import 'app_links.dart';

/// Apps installed on the connected TV, reloaded on each connection.
final tvAppsProvider = FutureProvider.autoDispose<List<TvApp>>((ref) async {
  final (connected, appList, _) = ref.watch(
    remoteSessionProvider.select(
      (s) => (s.isConnected, s.capabilities.appList, s.device?.id),
    ),
  );
  if (!connected || !appList) return const [];
  final apps = await ref.read(remoteSessionProvider.notifier).listApps();
  return [...apps]
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
});

/// App icons fetched from the TV, cached for the rest of the session so
/// switching tabs does not download them again. Keyed by device and app.
final appIconProvider =
    FutureProvider.family<
      Uint8List?,
      (String deviceId, String appId, String? iconUrl)
    >((ref, key) async {
      ref.keepAlive();
      final (_, appId, iconUrl) = key;
      return ref
          .read(remoteSessionProvider.notifier)
          .fetchAppIcon(TvApp(id: appId, name: '', iconUrl: iconUrl));
    });

class AppsPanel extends ConsumerWidget {
  const AppsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(activeProfileProvider);
    final session = ref.watch(remoteSessionProvider);
    if (!session.capabilities.appList && session.isConnected) {
      if (!session.capabilities.appLaunch) {
        return const Center(
          child: Text('This TV does not let the phone open apps.'),
        );
      }
      return _AppGrid(
        apps: [
          for (final a in knownAppLinks)
            if (profile.allowsApp(a.name)) a,
        ],
        header: 'This TV cannot list its apps. These open if installed.',
      );
    }
    final apps = ref.watch(tvAppsProvider);
    return apps.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(e is TvRemoteException ? e.message : 'Could not load apps'),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => ref.invalidate(tvAppsProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
      data: (list) {
        if (list.isEmpty) {
          return Center(
            child: Text(
              session.isConnected ? 'No apps found' : 'Not connected',
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: () {
            ref.invalidate(appIconProvider);
            return ref.refresh(tvAppsProvider.future);
          },
          child: _AppGrid(
            apps: [
              for (final a in list)
                if (profile.allowsApp(a.name)) a,
            ],
          ),
        );
      },
    );
  }
}

class _AppGrid extends StatelessWidget {
  const _AppGrid({required this.apps, this.header});

  final List<TvApp> apps;
  final String? header;

  @override
  Widget build(BuildContext context) => CustomScrollView(
    physics: const AlwaysScrollableScrollPhysics(),
    slivers: [
      if (header != null)
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          sliver: SliverToBoxAdapter(child: Text(header!)),
        ),
      SliverPadding(
        padding: const EdgeInsets.all(16),
        sliver: SliverGrid.builder(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 140,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.9,
          ),
          itemCount: apps.length,
          itemBuilder: (context, i) => _AppTile(app: apps[i]),
        ),
      ),
    ],
  );
}

class _AppTile extends ConsumerWidget {
  const _AppTile({required this.app});

  final TvApp app;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deviceId =
        ref.watch(remoteSessionProvider.select((s) => s.device?.id)) ?? '';
    final icon = ref
        .watch(appIconProvider((deviceId, app.id, app.iconUrl)))
        .value;
    return Semantics(
      button: true,
      label: 'Open ${app.name}',
      excludeSemantics: true,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            Haptics.play(
              HapticEvent.press,
              ref.read(settingsProvider).hapticStrength,
            );
            ref.read(remoteSessionProvider.notifier).launchApp(app.id);
          },
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: icon == null
                          ? _LetterTile(name: app.name)
                          : Image.memory(
                              icon,
                              key: ValueKey(app.id),
                              fit: BoxFit.contain,
                              gaplessPlayback: true,
                              errorBuilder: (_, _, _) =>
                                  _LetterTile(name: app.name),
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(app.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Placeholder while an icon loads, or when the TV has none: the app's
/// initial on a colour derived from its name, so tiles stay distinguishable.
class _LetterTile extends StatelessWidget {
  const _LetterTile({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final scheme = ColorScheme.fromSeed(
      seedColor: HSLColor.fromAHSL(
        1,
        (name.hashCode % 360).abs().toDouble(),
        0.55,
        0.5,
      ).toColor(),
      brightness: brightness,
    );
    return ColoredBox(
      color: scheme.primaryContainer,
      child: Center(
        child: Text(
          name.isEmpty ? '?' : name.characters.first.toUpperCase(),
          style: Theme.of(context).textTheme.headlineMedium
              ?.copyWith(color: scheme.onPrimaryContainer),
        ),
      ),
    );
  }
}
