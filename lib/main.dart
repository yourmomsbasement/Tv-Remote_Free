import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/providers.dart';
import 'core/storage/device_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final repository = await DeviceRepository.open();
  runApp(
    ProviderScope(
      overrides: [deviceRepositoryProvider.overrideWithValue(repository)],
      child: const TvRemoteApp(),
    ),
  );
}
