import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_remote_free/app/providers.dart';
import 'package:tv_remote_free/core/storage/device_repository.dart';
import 'package:tv_remote_free/features/watchlist/watchlist.dart';

import '../support/test_database.dart';

void main() {
  late DeviceRepository repo;
  late ProviderContainer container;

  setUp(() async {
    repo = await openTestRepository();
    container = ProviderContainer(
      overrides: [deviceRepositoryProvider.overrideWithValue(repo)],
    );
    container.listen(watchlistProvider, (_, _) {});
  });

  tearDown(() async {
    container.dispose();
    await repo.close();
  });

  Watchlist list() => container.read(watchlistProvider.notifier);
  Future<List<WatchItem>> items() => container.read(watchlistProvider.future);

  test('adds from shared text, newest first, without duplicates', () async {
    await list().addFromText('Great talk https://youtu.be/abc');
    await list().addFromText('https://www.netflix.com/title/1', title: 'Show');
    await list().addFromText('https://youtu.be/abc', title: 'Renamed');
    final all = await items();
    expect(all.map((i) => i.title), ['Renamed', 'Show']);
    expect(await list().addFromText('nothing to see'), isNull);
  });

  test('tracks watched items and removes', () async {
    final item = (await list().addFromText('https://youtu.be/abc'))!;
    await list().setWatched(item, true);
    expect((await items()).single.watched, isTrue);
    await list().remove(item);
    expect(await items(), isEmpty);
  });

  test('export and import round-trip; bad files are refused', () async {
    await list().addFromText('https://youtu.be/abc', title: 'A');
    final b = (await list().addFromText('https://youtu.be/xyz', title: 'B'))!;
    await list().setWatched(b, true);
    final backup = await list().export();
    for (final i in await items()) {
      await list().remove(i);
    }
    expect(await list().import(backup), 2);
    final restored = await items();
    expect(restored.map((i) => (i.title, i.watched)).toSet(), {
      ('A', false),
      ('B', true),
    });
    // Importing again updates rather than duplicates.
    expect(await list().import(backup), 2);
    expect(await items(), hasLength(2));
    expect(
      () => list().import('{"format":"something-else"}'),
      throwsFormatException,
    );
    expect(() => list().import('not json'), throwsFormatException);
  });
}
