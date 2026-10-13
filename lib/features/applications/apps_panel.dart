import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/adapter/smart_tv_adapter.dart';
import '../../core/errors.dart';
import '../remote/remote_session.dart';

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

class AppsPanel extends ConsumerWidget {
  const AppsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(remoteSessionProvider);
    if (!session.capabilities.appList && session.isConnected) {
      return const Center(
        child: Text('This TV does not let the phone list its apps.'),
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
          onRefresh: () => ref.refresh(tvAppsProvider.future),
          child: GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 140,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.9,
            ),
            itemCount: list.length,
            itemBuilder: (context, i) => _AppTile(app: list[i]),
          ),
        );
      },
    );
  }
}

class _AppTile extends ConsumerWidget {
  const _AppTile({required this.app});

  final TvApp app;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final fallback = Center(
      child: Text(
        app.name.isEmpty ? '?' : app.name.characters.first.toUpperCase(),
        style: Theme.of(context).textTheme.headlineMedium,
      ),
    );
    return Semantics(
      button: true,
      label: 'Open ${app.name}',
      excludeSemantics: true,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () =>
              ref.read(remoteSessionProvider.notifier).launchApp(app.id),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              children: [
                Expanded(
                  child: ColoredBox(
                    color: scheme.surfaceContainerHighest,
                    child: app.iconUrl == null
                        ? fallback
                        : Image.network(
                            app.iconUrl!,
                            fit: BoxFit.contain,
                            errorBuilder: (_, _, _) => fallback,
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
