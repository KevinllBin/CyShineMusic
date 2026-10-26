// ignore_for_file: avoid_print
// Manual network diagnostic: flutter test test/diag_catalog.dart -r expanded
import 'package:test/test.dart';

import 'package:cy_shine_music/core/models/enums.dart';
import 'package:cy_shine_music/core/models/search_category.dart';
import 'package:cy_shine_music/core/sdk/catalog_sdk.dart';
import 'package:cy_shine_music/core/sdk/playlist_sdk.dart';

void main() {
  test('tx artist paging live search', () async {
    final first = await CatalogSdk.search(
      '陈',
      MusicSource.tx,
      SearchCategory.artists,
      1,
      3,
    );
    final second = await CatalogSdk.search(
      '陈',
      MusicSource.tx,
      SearchCategory.artists,
      2,
      3,
    );
    print(
      'tx artist pages: ${first.items.map((i) => i.summary.id).join(', ')} / ${second.items.map((i) => i.summary.id).join(', ')}',
    );
    expect(first.hasMore, isTrue);
    expect(first.items, hasLength(3));
    expect(second.items, isNotEmpty);
    final ids = first.items.map((i) => i.summary.id).toSet();
    expect(second.items.every((i) => !ids.contains(i.summary.id)), isTrue);
  });

  test('tx artist English live search', () async {
    final result = await CatalogSdk.search(
      'Taylor Swift',
      MusicSource.tx,
      SearchCategory.artists,
      1,
      3,
    );
    print(
      'tx artist English: ${result.items.map((i) => i.summary.name).join(', ')}',
    );
    expect(result.items.first.summary.name, 'Taylor Swift');
  });

  for (final source in [MusicSource.wy, MusicSource.tx, MusicSource.kw]) {
    for (final category in [
      SearchCategory.artists,
      SearchCategory.playlists,
      SearchCategory.albums,
    ]) {
      test(
        '${source.code} ${category.name} live search and detail',
        () async {
          final result = await CatalogSdk.search(
            category == SearchCategory.albums ? '范特西' : '周杰伦',
            source,
            category,
            1,
            3,
          );
          print(
            '${source.code}/${category.name}: ${result.items.length} / ${result.total}; ${result.items.map((i) => '${i.summary.id}: ${i.summary.name}').join(', ')}',
          );
          expect(result.items, isNotEmpty);
          if (category == SearchCategory.playlists) {
            final playlist = await PlaylistSdk.parse(
              input: result.items.first.summary.id,
              source: source,
              maxTracks: 3,
            );
            print(
              '  playlist: ${playlist.name}; ${playlist.tracks.length}/${playlist.totalTracks}',
            );
            expect(playlist.tracks, isNotEmpty);
            return;
          }
          final item = result.items.first;
          final detail = await CatalogSdk.detail(
            source,
            item.summary.id,
            artist: category == SearchCategory.artists,
            maxTracks: 3,
          );
          print(
            '  ${detail.name}: ${detail.tracks.length}/${detail.totalTracks}; ${detail.tracks.map((s) => '${s.name} (${s.meta.songId})').join(', ')}',
          );
          expect(detail.tracks, isNotEmpty);
          expect(detail.tracks.every((s) => s.source == source), isTrue);
        },
        timeout: const Timeout(Duration(seconds: 90)),
      );
    }
  }
}
