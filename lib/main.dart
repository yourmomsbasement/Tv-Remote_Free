import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'app/app.dart';
import 'app/providers.dart';
import 'core/storage/app_icon_cache.dart';
import 'core/storage/device_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final repository = await DeviceRepository.open();
  final cacheDir = await getApplicationCacheDirectory();
  final iconCache = AppIconCache(Directory('${cacheDir.path}/app_icons'));
  unawaited(iconCache.prune());
  runApp(
    ProviderScope(
      overrides: [
        deviceRepositoryProvider.overrideWithValue(repository),
        appIconCacheProvider.overrideWithValue(iconCache),
      ],
      child: const TvRemoteApp(),
    ),
  );
}
