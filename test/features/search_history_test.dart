import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_remote_free/app/providers.dart';
import 'package:tv_remote_free/core/storage/device_repository.dart';
import 'package:tv_remote_free/features/keyboard/keyboard_panel.dart';
import 'package:tv_remote_free/features/keyboard/search_history.dart';
import 'package:tv_remote_free/features/settings/app_settings.dart';

import '../support/test_database.dart';

void main() {
  late DeviceRepository repo;
  late ProviderContainer container;

  setUp(() async {
    repo = await openTestRepository();
    container = ProviderContainer(
      overrides: [deviceRepositoryProvider.overrideWithValue(repo)],
    );
    container.listen(searchHistoryProvider, (_, _) {});
    await container.read(appSettingsProvider.future);
  });

  tearDown(() async {
    container.dispose();
    await repo.close();
  });

  SearchHistory history() => container.read(searchHistoryProvider.notifier);
  Future<List<String>> entries() =>
      container.read(searchHistoryProvider.future);

  test('newest first, de-duplicated ignoring case, capped', () async {
    await history().record('cats');
    await history().record('  dogs ');
    await history().record('CATS');
    expect(await entries(), ['CATS', 'dogs']);
    for (var i = 0; i < 30; i++) {
      await history().record('q$i');
    }
    expect(await entries(), hasLength(SearchHistory.maxEntries));
    expect((await entries()).first, 'q29');
  });

  test('ignores empty and overlong entries; supports removal', () async {
    await history().record('   ');
    await history().record('x' * (SearchHistory.maxLength + 1));
    expect(await entries(), isEmpty);
    await history().record('a');
    await history().record('b');
    await history().remove('a');
    expect(await entries(), ['b']);
  });

  test('persists across restarts', () async {
    await history().record('saved');
    final second = ProviderContainer(
      overrides: [deviceRepositoryProvider.overrideWithValue(repo)],
    );
    second.listen(searchHistoryProvider, (_, _) {});
    expect(await second.read(searchHistoryProvider.future), ['saved']);
    second.dispose();
  });

  test('turning the setting off deletes history and stops recording', () async {
    await history().record('private');
    final settings = container.read(settingsProvider);
    await container
        .read(appSettingsProvider.notifier)
        .save(settings.copyWith(rememberSearches: false));
    expect(await entries(), isEmpty);
    await history().record('more');
    expect(await entries(), isEmpty);
    expect(await repo.getSetting('search_history'), '[]');
  });

  test('pasted line breaks become spaces', () {
    expect(
      singleLineForTv('line one\r\n  line two\n\nthree '),
      'line one line two three',
    );
  });
}
