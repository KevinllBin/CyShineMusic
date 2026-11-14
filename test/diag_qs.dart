// Manual network diagnostic: flutter test test/diag_qs.dart -r expanded
// Calls public catalogue/lyric endpoints; does not log in or download audio.
import 'package:flutter_test/flutter_test.dart';

import 'package:cy_shine_music/core/api/music_api.dart';
import 'package:cy_shine_music/core/models/enums.dart';
import 'package:cy_shine_music/core/models/search_category.dart';
import 'package:cy_shine_music/core/models/online_collection_kind.dart';
import 'package:cy_shine_music/core/sdk/internal/sdk_http.dart';
import 'package:cy_shine_music/core/sdk/qs_sdk.dart';
import 'package:cy_shine_music/features/player/lyric_parser.dart';

void main() {
  test(
    'live Qishui search, suggestions, pagination and catalog navigation',
    () async {
      final api = MusicApi(enabledSearchSources: {MusicSource.qs});
      final first = await api.searchMusic(
        keyword: '周杰伦',
        source: MusicSource.qs,
      );
      final second = await api.searchMusic(
        keyword: '周杰伦',
        source: MusicSource.qs,
        page: 2,
      );
      expect(first.list, isNotEmpty);
      expect(first.limit, 20);
      expect(second.list, isNotEmpty);
      expect(
        first.list
            .map((m) => m.id)
            .toSet()
            .intersection(second.list.map((m) => m.id).toSet()),
        isEmpty,
      );
      final tips = await api.searchTip(keyword: '周杰', source: MusicSource.qs);
      expect(tips, isNotEmpty);
      // ignore: avoid_print
      print(
        '汽水歌曲搜索：${first.list.length}/${second.list.length}，两页无重复；联想 ${tips.length} 条',
      );
      for (final category in [
        SearchCategory.artists,
        SearchCategory.albums,
        SearchCategory.playlists,
      ]) {
        final result = await api.searchContent(
          keyword: '周杰伦',
          source: MusicSource.qs,
          category: category,
        );
        expect(
          result.catalog[category],
          isNotEmpty,
          reason: result.notices.join('；'),
        );
        final item = result.catalog[category]!.first;
        final detail = await api.getCollection(
          source: MusicSource.qs,
          id: item.summary.id,
          kind: switch (category) {
            SearchCategory.artists => OnlineCollectionKind.artist,
            SearchCategory.albums => OnlineCollectionKind.album,
            _ => OnlineCollectionKind.playlist,
          },
          maxTracks: 3,
        );
        expect(detail.tracks, isNotEmpty);
        // ignore: avoid_print
        print(
          '汽水${category.label}搜索：${result.catalog[category]!.length} 条；详情 ${detail.tracks.length} 首已加载',
        );
      }
      final aggregated = await api.searchMusic(
        keyword: '周杰伦',
        source: MusicSource.all,
      );
      expect(aggregated.list.every((m) => m.source == MusicSource.qs), isTrue);
      expect(aggregated.list, isNotEmpty);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'live Qishui lyrics reach the player with word timings and translations',
    () async {
      final api = MusicApi();
      for (final id in [
        '6778775242320906241',
        '6849381964508596226',
        '6732580534901278722',
      ]) {
        final music = QsSdk.parseTrack({'id': id, 'name': '歌词诊断'})!;
        final lyric = await api.getLyric(musicInfo: music);
        final parsed = KaraokeLyricsParser.parse(lyric);
        expect(parsed.lines, isNotEmpty);
        expect(parsed.lines.any((line) => line.hasWordTiming), isTrue);
        if (id == '6732580534901278722') {
          expect(
            parsed.lines.any((line) => line.translation?.isNotEmpty == true),
            isTrue,
          );
        }
        // ignore: avoid_print
        print(
          '汽水歌词 $id：${parsed.lines.length} 行；逐字 ${parsed.lines.where((line) => line.hasWordTiming).length} 行；翻译 ${parsed.lines.where((line) => line.translation?.isNotEmpty == true).length} 行',
        );
      }
    },
    timeout: const Timeout(Duration(minutes: 1)),
  );

  test('live Qishui discovery, chart and paginated playlist', () async {
    final api = MusicApi();
    final playlistsFuture = api.featuredPlaylists(source: MusicSource.qs);
    final boardsFuture = api.getLeaderboards(MusicSource.qs);
    final playlists = await playlistsFuture;
    final boards = await boardsFuture;
    expect(playlists, isNotEmpty);
    expect(boards, isNotEmpty);
    // ignore: avoid_print
    print(
      '推荐歌单 ${playlists.length} 个；榜单：${boards.map((b) => b.name).join('、')}',
    );

    final board = await api.getLeaderboard(
      source: MusicSource.qs,
      boardId: boards.first.boardId,
    );
    expect(board.tracks, isNotEmpty);
    final savedBoard = await api.parsePlaylist(
      input: board.id,
      source: board.source,
    );
    expect(savedBoard.id, board.id);
    expect(savedBoard.name, board.name);
    // ignore: avoid_print
    print('${board.name} ${board.tracks.length} 首；收藏更新可回读');

    // A known public playlist with more than one page of tracks.
    const id = '7103425966566819854';
    final partial = await api.parsePlaylist(
      input: id,
      source: MusicSource.qs,
      maxTracks: 40,
    );
    final full = await api.parsePlaylist(input: id, source: MusicSource.qs);
    expect(partial.tracks, hasLength(40));
    expect(full.tracks.length, greaterThanOrEqualTo(partial.tracks.length));
    expect(full.tracks.map((t) => t.id).toSet(), hasLength(full.tracks.length));
    expect(full.totalTracks, full.tracks.length);
    expect(full.tracks.first.source, MusicSource.qs);
    // ignore: avoid_print
    print(
      '歌单首批 ${partial.tracks.length}/${partial.totalTracks}，完整 ${full.tracks.length} 首',
    );

    final cover = playlists.first.coverUrl;
    expect(cover, isNotNull);
    final response = await SdkHttp.fetch<dynamic>(cover!, method: 'HEAD');
    expect(response.statusCode, 200);
    // ignore: avoid_print
    print('歌单封面 HTTP ${response.statusCode}');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
