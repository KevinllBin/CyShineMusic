import 'package:test/test.dart';

import 'package:cy_shine_music/core/models/enums.dart';
import 'package:cy_shine_music/core/models/playlist_summary.dart';
import 'package:cy_shine_music/features/discovery/discovery_browse_cache.dart';

List<PlaylistSummary> playlists(
  int count, {
  MusicSource source = MusicSource.tx,
}) => List.generate(
  count,
  (index) =>
      PlaylistSummary(id: '$index', name: 'Playlist $index', source: source),
);

void main() {
  late DiscoveryBrowseCache cache;
  setUp(() => cache = DiscoveryBrowseCache());

  void save(
    List<PlaylistSummary> firstPage,
    List<PlaylistSummary> items, {
    MusicSource source = MusicSource.tx,
    String category = 'hot',
    double offset = 2500,
  }) => cache.save(
    source: source,
    categoryId: category,
    firstPage: firstPage,
    items: items,
    nextPage: 4,
    hasMore: false,
    scrollOffset: offset,
  );

  test('all five platforms restore their own loaded range and position', () {
    final firstPages = {
      for (final source in MusicSource.values.where(
        (s) => s != MusicSource.all,
      ))
        source: playlists(30, source: source),
    };
    for (final entry in firstPages.entries) {
      save(entry.value, playlists(90, source: entry.key), source: entry.key);
    }
    for (final entry in firstPages.entries) {
      final restored = cache.restore(
        source: entry.key,
        categoryId: 'hot',
        firstPage: entry.value,
      )!;
      expect(restored.items, hasLength(90));
      expect(restored.items.every((item) => item.source == entry.key), isTrue);
      expect(restored.nextPage, 4);
      expect(restored.hasMore, isFalse);
      expect(restored.scrollOffset, 2500);
    }
  });

  test(
    'refresh invalidates pagination even when the new first page looks equal',
    () {
      final firstPage = playlists(30);
      save(firstPage, playlists(90));
      expect(
        cache.restore(
          source: MusicSource.tx,
          categoryId: 'hot',
          firstPage: [...firstPage],
        ),
        isNull,
      );
    },
  );

  test('changing category discards both old pages and the old offset', () {
    final firstPage = playlists(30);
    save(firstPage, playlists(90));
    expect(
      cache.restore(
        source: MusicSource.tx,
        categoryId: 'folk',
        firstPage: firstPage,
      ),
      isNull,
    );
    expect(
      cache.restore(
        source: MusicSource.tx,
        categoryId: 'hot',
        firstPage: firstPage,
      ),
      isNull,
    );
  });

  test(
    'oversized inactive list evicts its offset without affecting another source',
    () {
      final firstPage = playlists(30);
      save(firstPage, playlists(DiscoveryBrowseCache.maxItemsPerSource));
      final retained = cache.restore(
        source: MusicSource.tx,
        categoryId: 'hot',
        firstPage: firstPage,
      );
      expect(
        retained!.items,
        hasLength(DiscoveryBrowseCache.maxItemsPerSource),
      );
      final otherPage = playlists(30, source: MusicSource.kg);
      save(otherPage, otherPage, source: MusicSource.kg);
      save(firstPage, playlists(DiscoveryBrowseCache.maxItemsPerSource + 1));
      expect(
        cache.restore(
          source: MusicSource.tx,
          categoryId: 'hot',
          firstPage: firstPage,
        ),
        isNull,
      );
      expect(
        cache.restore(
          source: MusicSource.kg,
          categoryId: 'hot',
          firstPage: otherPage,
        ),
        isNotNull,
      );
    },
  );

  test('saving a loading or failed page removes stale browse state', () {
    final firstPage = playlists(30);
    save(firstPage, playlists(90));
    cache.save(
      source: MusicSource.tx,
      categoryId: 'hot',
      firstPage: null,
      items: [],
      nextPage: 2,
      hasMore: false,
      scrollOffset: 0,
    );
    expect(
      cache.restore(
        source: MusicSource.tx,
        categoryId: 'hot',
        firstPage: firstPage,
      ),
      isNull,
    );
  });

  test('snapshot owns its list and clamps overscroll to a valid position', () {
    final firstPage = playlists(30);
    final items = playlists(90);
    save(firstPage, items, offset: -60);
    items.clear();
    final restored = cache.restore(
      source: MusicSource.tx,
      categoryId: 'hot',
      firstPage: firstPage,
    )!;
    expect(restored.items, hasLength(90));
    expect(restored.scrollOffset, 0);
    expect(() => restored.items.clear(), throwsUnsupportedError);
  });
}
