import 'package:flutter_test/flutter_test.dart';

import 'package:cy_shine_music/core/models/enums.dart';
import 'package:cy_shine_music/core/models/search_category.dart';
import 'package:cy_shine_music/core/sdk/catalog/qs_catalog.dart';
import 'package:cy_shine_music/core/sdk/qs_sdk.dart';

void main() {
  test('empty reads retry once and a failed page remains retryable', () async {
    var blank = true;
    var attempts = 0;
    final catalog = QsCatalog(
      _sdk((url, {required method, required headers, body}) async {
        attempts++;
        if (blank) return null;
        return {
          'result_groups': [
            {
              'id': 'tracks',
              'data': [
                {
                  'entity': {'track': _track('123456')},
                },
              ],
            },
          ],
        };
      }),
    );
    await expectLater(
      catalog.searchTracks('测试'),
      throwsA(isA<QsEmptyResponseException>()),
    );
    expect(attempts, 2);
    blank = false;
    expect((await catalog.searchTracks('测试')).list, hasLength(1));
    expect(attempts, 3);
  });

  test(
    'identical upstream pages are shared across platform and aggregate searches',
    () async {
      var calls = 0;
      final catalog = QsCatalog(
        _sdk((url, {required method, required headers, body}) async {
          calls++;
          return {
            'result_groups': [
              {
                'id': 'tracks',
                'data': [
                  {
                    'entity': {'track': _track('123456')},
                  },
                ],
              },
            ],
          };
        }),
      );
      await catalog.searchTracks('测试', limit: 20);
      await catalog.searchTracks('测试', limit: 30);
      expect(calls, 1);
    },
  );

  test(
    'song search uses native 20-item offsets and omits rejected parameters',
    () async {
      final catalog = QsCatalog(
        _sdk((url, {required method, required headers, body}) async {
          final uri = Uri.parse(url);
          expect(uri.path, '/luna/search/track');
          expect(uri.queryParameters['q'], '测试 + 歌曲');
          expect(uri.queryParameters['cursor'], '20');
          expect(uri.queryParameters['device_id'], 'fixture-device');
          expect(uri.queryParameters.containsKey('count'), isFalse);
          expect(url, contains('search_id='));
          expect(url, contains('from_search_id='));
          expect(uri.queryParameters.containsKey('debug_params'), isFalse);
          return {
            'result_groups': [
              {
                'id': 'tracks',
                'has_more': false,
                'data': [
                  {
                    'entity': {'track': _track('6778775242320906241')},
                  },
                  {
                    'entity': {'track': _track('6778775242320906241')},
                  },
                ],
              },
            ],
          };
        }),
      );
      final page = await catalog.searchTracks(' 测试 + 歌曲 ', page: 2);
      expect(page.list.single.meta.songId, '6778775242320906241');
      expect(page.list.single.source, MusicSource.qs);
      expect(page.hasMore, isFalse);
    },
  );

  test('search suggestions are strings and are deduplicated', () async {
    final catalog = QsCatalog(
      _sdk((url, {required method, required headers, body}) async {
        expect(Uri.parse(url).path, '/luna/pc/sug');
        return {
          'sugs': [
            {'suggestion': '测试歌曲'},
            {'suggestion': '测试歌曲'},
            {'suggestion': ''},
          ],
        };
      }),
    );
    expect(await catalog.tip('测试'), ['测试歌曲']);
  });

  test(
    'all supported catalog kinds retain native IDs, covers and navigation type',
    () async {
      final catalog = QsCatalog(
        _sdk((url, {required method, required headers, body}) async {
          final type = Uri.parse(url).path.split('/').last;
          return {
            'result_groups': [
              {
                'id': '${type}s',
                'has_more': true,
                'data': [
                  {
                    'entity': {
                      type: {
                        'id': '900000000000000001',
                        'name': '测试内容',
                        'title': '测试歌单',
                        'url_cover': _cover,
                        'url_avatar': _cover,
                        'count_tracks': 10,
                      },
                    },
                  },
                ],
              },
            ],
          };
        }),
      );
      for (final category in [
        SearchCategory.artists,
        SearchCategory.albums,
        SearchCategory.playlists,
      ]) {
        final result = await catalog.search('测试', category, 1, 20);
        expect(result.items.single.category, category);
        expect(result.items.single.summary.id, '900000000000000001');
        expect(
          result.items.single.summary.coverUrl,
          'https://images.test/cover.jpg',
        );
        expect(result.hasMore, isTrue);
      }
    },
  );

  test('empty results are valid and malformed data is reported', () async {
    var malformed = false;
    final catalog = QsCatalog(
      _sdk(
        (url, {required method, required headers, body}) async => malformed
            ? {
                'result_groups': [
                  {'id': 'tracks'},
                ],
              }
            : {'result_groups': []},
      ),
    );
    expect((await catalog.searchTracks('不存在')).list, isEmpty);
    malformed = true;
    await expectLater(catalog.searchTracks('测试'), throwsException);
    expect((await catalog.searchTracks(' ')).list, isEmpty);
  });

  test(
    'artist details paginate by returned cursors and keep the total for partial loading',
    () async {
      final cursors = <String?>[];
      final catalog = QsCatalog(
        _sdk((url, {required method, required headers, body}) async {
          final uri = Uri.parse(url);
          if (!uri.path.endsWith('/tracks')) {
            return {
              'artist_info': {
                'id': '123456',
                'name': '测试歌手',
                'count_tracks': 3,
                'url_avatar': _cover,
              },
            };
          }
          cursors.add(uri.queryParameters['cursor']);
          return {
            'tracks': [
              for (final id in cursors.length == 1 ? ['1', '2'] : ['3'])
                _track(id),
            ],
            'next_cursor': 'native-next',
          };
        }),
      );
      final partial = await catalog.detail(
        '123456',
        artist: true,
        maxTracks: 2,
      );
      expect(partial.tracks, hasLength(2));
      expect(partial.totalTracks, 3);
      cursors.clear();
      final full = await catalog.detail('123456', artist: true);
      expect(cursors, ['0', 'native-next']);
      expect(full.totalTracks, 3);
    },
  );

  test(
    'album detail exposes only the available tracks and obeys display limits',
    () async {
      final catalog = QsCatalog(
        _sdk(
          (url, {required method, required headers, body}) async => {
            'album_info': {
              'name': '测试专辑',
              'count_tracks': 99,
              'url_cover': _cover,
            },
            'tracks': [_track('1'), _track('2')],
          },
        ),
      );
      final album = await catalog.detail('654321', artist: false, maxTracks: 1);
      expect(album.tracks, hasLength(1));
      expect(album.totalTracks, 2);
    },
  );
}

const _cover = {
  'urls': ['https://images.test/cover.jpg'],
};
Map<String, dynamic> _track(String id) => {
  'id': id,
  'name': '测试歌曲',
  'artists': [
    {'name': '测试歌手'},
  ],
};

QsSdk _sdk(QsJsonRequester requester) => QsSdk(
  requester: (url, {required method, required headers, body}) async {
    if (Uri.parse(url).path == '/service/2/desktop/device_register/') {
      return {
        'device_id_str': 'fixture-device',
        'install_id_str': 'fixture-install',
      };
    }
    return requester(url, method: method, headers: headers, body: body);
  },
);
