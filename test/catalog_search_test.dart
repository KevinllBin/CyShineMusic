import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cy_shine_music/core/api/music_api.dart';
import 'package:cy_shine_music/core/models/enums.dart';
import 'package:cy_shine_music/core/models/music_info.dart';
import 'package:cy_shine_music/core/models/music_query.dart';
import 'package:cy_shine_music/core/models/search_category.dart';
import 'package:cy_shine_music/core/models/search_response.dart';
import 'package:cy_shine_music/core/sdk/catalog/kw_catalog.dart';
import 'package:cy_shine_music/core/sdk/catalog/tx_catalog.dart';
import 'package:cy_shine_music/core/sdk/catalog/wy_catalog.dart';
import 'package:cy_shine_music/core/storage/settings_store.dart';
import 'package:cy_shine_music/features/search/search_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'collection filtering preserves order and matches all terms across metadata',
    () {
      final tracks = [
        _song('first', 'Blue Sky', 'Singer', 'Live'),
        _song('second', 'Blue', 'Other', 'Studio'),
      ];
      expect(filterMusicByQuery(tracks, '  BLUE live ').map((s) => s.id), [
        'first',
      ]);
      expect(filterMusicByQuery(tracks, 'blue').map((s) => s.id), [
        'first',
        'second',
      ]);
      expect(filterMusicByQuery(tracks, 'missing'), isEmpty);
      expect(identical(filterMusicByQuery(tracks, ''), tracks), isTrue);
    },
  );

  test(
    'NetEase artist reports available hot songs rather than discography size',
    () async {
      final result = await WyCatalog.detail(
        '123',
        artist: true,
        maxTracks: 1,
        loader: (_, {headers}) async => {
          'code': 200,
          'artist': {'name': 'Artist', 'musicSize': 900},
          'hotSongs': [
            {'id': 1, 'name': 'First'},
            {'id': 2, 'name': 'Second'},
          ],
        },
      );
      expect(result.totalTracks, 2);
      expect(result.tracks.single.meta.songId, 1);
    },
  );

  test(
    'Kuwo artist paging uses numeric song IDs and stops at the requested range',
    () async {
      final pages = <int>[];
      final result = await KwCatalog.detail(
        '336',
        artist: true,
        maxTracks: 120,
        loader: (url, {headers}) async {
          final page = int.parse(Uri.parse(url).queryParameters['pn']!);
          pages.add(page);
          return {
            'artist': 'Artist',
            'total': '250',
            'musiclist': [
              for (var i = 0; i < 100; i++)
                {
                  'musicrid': '${page * 100 + i}',
                  'name': 'Song $i',
                  'duration': '120',
                },
            ],
          };
        },
      );
      expect(pages, [0, 1]);
      expect(result.tracks, hasLength(120));
      expect(result.tracks.last.meta.songId, '119');
      expect(result.totalTracks, 250);
    },
  );

  test('QQ album keeps track order and playback media identifiers', () async {
    final result = await TxCatalog.detail(
      'album-mid',
      artist: false,
      loader: (_, {headers}) async => {
        'code': 0,
        'data': {
          'name': 'Album',
          'list': [
            {
              'songmid': 'b',
              'strMediaMid': 'media-b',
              'songid': 2,
              'songname': 'First',
            },
            {
              'songmid': 'a',
              'strMediaMid': 'media-a',
              'songid': 1,
              'songname': 'Second',
            },
          ],
        },
      },
    );
    expect(result.tracks.map((s) => s.meta.songId), ['b', 'a']);
    expect(result.tracks.first.meta.strMediaMid, 'media-b');
    expect(result.tracks.first.meta.metaId, 2);
  });

  for (final page in [1, 2]) {
    test(
      'QQ artist desktop search parses page $page and the shared total',
      () async {
        final result = await TxCatalog.search(
          '周杰伦 & Jay Chou',
          SearchCategory.artists,
          page,
          6,
          loader: (url, {headers}) async {
            final uri = Uri.parse(url);
            expect(uri.host, 'u.y.qq.com');
            final request = jsonDecode(uri.queryParameters['data']!) as Map;
            expect(request.keys, ['music.search.SearchCgiService']);
            final node = request['music.search.SearchCgiService'] as Map;
            expect(node['module'], 'music.search.SearchCgiService');
            expect(node['method'], 'DoSearchForQQMusicDesktop');
            expect(node['param'], {
              'search_type': 1,
              'query': '周杰伦 & Jay Chou',
              'page_num': page,
              'num_per_page': 6,
            });
            expect(headers?['Referer'], 'https://y.qq.com/');
            // The live endpoint returns JSON with a text/plain content type.
            return jsonEncode(
              _qqSearchResponse('singer', [
                {
                  'singerMID': '0025NhlN2yWrP4',
                  'singerName': '周杰伦',
                  'singerPic': 'http://y.gtimg.cn/artist.jpg',
                  'songNum': 1011,
                  'albumNum': 43,
                },
              ], total: 8),
            );
          },
        );
        final item = result.items.single;
        expect(item.category, SearchCategory.artists);
        expect(item.summary.source, MusicSource.tx);
        expect(item.summary.id, '0025NhlN2yWrP4');
        expect(item.summary.name, '周杰伦');
        expect(item.summary.coverUrl, 'https://y.gtimg.cn/artist.jpg');
        expect(item.summary.trackCount, 1011);
        expect(item.subtitle, '1011 首歌曲 · 43 张专辑');
        expect(result.total, 8);
        expect(result.hasMore, page == 1);
      },
    );
  }

  test('QQ album desktop search keeps its type and release metadata', () async {
    final result = await TxCatalog.search(
      '范特西',
      SearchCategory.albums,
      1,
      3,
      loader: (url, {headers}) async {
        final request =
            jsonDecode(Uri.parse(url).queryParameters['data']!) as Map;
        expect(
          request['music.search.SearchCgiService']['param']['search_type'],
          2,
        );
        return _qqSearchResponse('album', [
          {
            'albumMID': '000I5jJB3blWeN',
            'albumName': '范特西',
            'albumPic': 'http://y.gtimg.cn/album.jpg',
            'singerName': '周杰伦',
            'song_count': 10,
            'publicTime': '2001-09-14',
          },
        ], total: 277);
      },
    );
    expect(result.items.single.summary.id, '000I5jJB3blWeN');
    expect(result.items.single.summary.creator, '周杰伦');
    expect(result.items.single.summary.trackCount, 10);
    expect(result.items.single.subtitle, '周杰伦 · 2001-09-14');
    expect(result.total, 277);
    expect(result.hasMore, isTrue);
  });

  test('QQ artist accepts a successful search with no matches', () async {
    final result = await TxCatalog.search(
      'unmatched',
      SearchCategory.artists,
      1,
      6,
      loader: (_, {headers}) async => _qqSearchResponse('singer', [], total: 0),
    );
    expect(result.items, isEmpty);
    expect(result.total, 0);
    expect(result.hasMore, isFalse);
  });

  test('QQ artist rejects service errors and missing result lists', () async {
    for (final response in [
      {'code': 500},
      {
        'code': 0,
        'music.search.SearchCgiService': {'code': 1000},
      },
      {
        'code': 0,
        'music.search.SearchCgiService': {
          'code': 0,
          'data': {'code': 1000},
        },
      },
      {
        'code': 0,
        'music.search.SearchCgiService': {'code': 0, 'data': {}},
      },
    ]) {
      await expectLater(
        TxCatalog.search(
          '周杰伦',
          SearchCategory.artists,
          1,
          6,
          loader: (_, {headers}) async => response,
        ),
        throwsException,
      );
    }
  });

  test(
    'catalog response rejects an error instead of showing an empty result',
    () async {
      await expectLater(
        WyCatalog.search(
          'test',
          SearchCategory.albums,
          1,
          10,
          loader: (_, {headers}) async => {'code': 403},
        ),
        throwsException,
      );
      await expectLater(
        KwCatalog.search(
          'test',
          SearchCategory.artists,
          1,
          10,
          loader: (_, {headers}) async => '<html>blocked</html>',
        ),
        throwsFormatException,
      );
    },
  );

  group('search state', () {
    late ProviderContainer container;
    late _PendingApi api;
    late SearchController controller;
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      api = _PendingApi();
      container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          musicApiProvider.overrideWithValue(api),
        ],
      );
      controller = container.read(searchControllerProvider.notifier);
    });
    tearDown(() => container.dispose());

    test('catalog failure notices do not cache a failed search', () async {
      final first = controller.search(keyword: '周杰伦');
      api.complete(0, 'partial', notices: ['QQ 艺人加载失败，可切换平台或重试']);
      await first;
      expect(
        container.read(searchControllerProvider).response!.notices,
        isNotEmpty,
      );

      final retry = controller.search(keyword: '周杰伦');
      expect(api.requests, hasLength(2));
      api.complete(1, 'recovered');
      await retry;
      await controller.search(keyword: '周杰伦');
      expect(api.requests, hasLength(2));
      expect(
        container.read(searchControllerProvider).response!.list.single.id,
        'recovered',
      );
    });

    test(
      'switching categories ignores late results and keeps separate caches',
      () async {
        final first = controller.search(keyword: 'test');
        controller.setCategory(SearchCategory.albums);
        expect(api.requests, hasLength(2));
        api.complete(1, 'album');
        await Future<void>.delayed(Duration.zero);
        api.complete(0, 'overview');
        await first;
        expect(
          container.read(searchControllerProvider).response!.list.single.id,
          'album',
        );
        controller.setCategory(SearchCategory.all);
        expect(
          container.read(searchControllerProvider).response!.list.single.id,
          'overview',
        );
        expect(api.requests, hasLength(2));
      },
    );

    test(
      'identical pending queries join and clearing discards their response',
      () async {
        final first = controller.search(keyword: 'test');
        final second = controller.search(keyword: 'test');
        expect(api.requests, hasLength(1));
        controller.resetToDiscovery();
        api.complete(0, 'late');
        await Future.wait([first, second]);
        expect(
          container.read(searchControllerProvider).isSearchActive,
          isFalse,
        );
        expect(container.read(searchControllerProvider).response, isNull);
      },
    );

    test(
      'each category restores its page while a new keyword resets pages',
      () async {
        controller.setCategory(SearchCategory.songs);
        final first = controller.search(keyword: 'test', page: 3);
        api.complete(0, 'songs');
        await first;
        controller.setCategory(SearchCategory.albums);
        api.complete(1, 'albums');
        await Future<void>.delayed(Duration.zero);
        controller.setCategory(SearchCategory.songs);
        expect(container.read(searchControllerProvider).page, 3);
        final next = controller.search(keyword: 'new');
        api.complete(2, 'new');
        await next;
        controller.setCategory(SearchCategory.albums);
        expect(container.read(searchControllerProvider).page, 1);
        api.complete(3, 'new-albums');
        await Future<void>.delayed(Duration.zero);
      },
    );

    test(
      'reordering sources does not strand an active single-platform request',
      () async {
        final pending = controller.search(
          keyword: 'test',
          source: MusicSource.wy,
        );
        await container.read(settingsProvider.notifier).setDiscoverySourceOrder(
          [MusicSource.tx, MusicSource.wy],
        );
        api.complete(0, 'single');
        await pending;
        expect(container.read(searchControllerProvider).loading, isFalse);
        expect(
          container.read(searchControllerProvider).response!.list.single.id,
          'single',
        );
      },
    );

    test(
      'changing aggregate source order cannot repopulate cache with an old request',
      () async {
        final first = controller.search(
          keyword: 'test',
          source: MusicSource.all,
        );
        await container.read(settingsProvider.notifier).setDiscoverySourceOrder(
          [MusicSource.tx, MusicSource.wy],
        );
        expect(api.requests, hasLength(2));
        api.complete(1, 'new-order');
        await Future<void>.delayed(Duration.zero);
        api.complete(0, 'old-order');
        await first;
        await controller.search(keyword: 'test', source: MusicSource.all);
        expect(
          container.read(searchControllerProvider).response!.list.single.id,
          'new-order',
        );
        expect(api.requests, hasLength(2));
      },
    );
  });
}

MusicInfo _song(String id, String name, String singer, String album) =>
    MusicInfo.fromJson({
      'id': id,
      'name': name,
      'singer': singer,
      'source': 'wy',
      'meta': {'songId': id, 'albumName': album},
    });

Map<String, Object> _qqSearchResponse(
  String category,
  List<Map<String, Object>> items, {
  required int total,
}) => {
  'code': 0,
  'music.search.SearchCgiService': {
    'code': 0,
    'data': {
      'code': 0,
      'body': {
        category: {'list': items},
      },
      'meta': {'sum': total},
    },
  },
};

class _PendingApi extends MusicApi {
  final requests =
      <
        ({SearchCategory category, int page, Completer<SearchResponse> result})
      >[];
  @override
  Future<SearchResponse> searchContent({
    required String keyword,
    required MusicSource source,
    required SearchCategory category,
    int page = 1,
    int limit = 30,
  }) {
    final result = Completer<SearchResponse>();
    requests.add((category: category, page: page, result: result));
    return result.future;
  }

  void complete(int index, String id, {List<String> notices = const []}) {
    final request = requests[index];
    request.result.complete(
      SearchResponse(
        list: [_song(id, id, '', '')],
        page: request.page,
        limit: 30,
        allPage: 5,
        total: 150,
        source: MusicSource.all,
        notices: notices,
      ),
    );
  }
}
