import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:cy_shine_music/core/models/enums.dart';
import 'package:cy_shine_music/core/sdk/internal/crypto_util.dart';
import 'package:cy_shine_music/core/sdk/playlist_sdk.dart';
import 'package:cy_shine_music/core/sdk/qs_sdk.dart';
import 'package:cy_shine_music/core/storage/settings_store.dart';

void main() {
  test(
    'lyrics use the H5 web identity and preserve the native track ID',
    () async {
      final sdk = QsSdk(
        requester: (url, {required method, required headers, body}) async {
          final uri = Uri.parse(url);
          expect(uri.path, '/luna/h5/track_v2');
          expect(uri.queryParameters['device_platform'], 'web');
          expect(uri.queryParameters['track_id'], '6778775242320906241');
          expect(method, 'GET');
          expect(body, isNull);
          return {
            'lyric': {'type': 'krc', 'content': '[1050,500]<0,500,0>测试'},
          };
        },
      );
      final info = await sdk.getLyric(
        QsSdk.parseTrack(_track('6778775242320906241'))!,
      );
      expect(info.lyric, '[00:01.050]测试');
      expect(info.lxlyric, '[00:01.050]<0,500>测试');
    },
  );

  test(
    'missing lyrics on a valid track are empty but upstream failures surface',
    () async {
      var valid = true;
      final sdk = QsSdk(
        requester: (url, {required method, required headers, body}) async =>
            valid ? {'track': _track('123456')} : {'status_code': 1000062},
      );
      final music = QsSdk.parseTrack(_track('123456'))!;
      expect((await sdk.getLyric(music)).isEmpty, isTrue);
      valid = false;
      await expectLater(sdk.getLyric(music), throwsException);
    },
  );

  test(
    'coalesces homepage loads and reads native chart IDs and playlists',
    () async {
      var calls = 0;
      final sdk = QsSdk(
        requester: (url, {required method, required headers, body}) async {
          calls++;
          expect(Uri.parse(url).path, '/luna/pc/discover');
          expect(Uri.parse(url).queryParameters['device_platform'], 'windows');
          expect(method, 'POST');
          expect(body, '{}');
          expect(headers['x-ss-stub'], CryptoUtil.md5Hex(body!).toUpperCase());
          return _home;
        },
      );
      final playlists = sdk.featured();
      final boards = sdk.boards();
      expect((await playlists).single.id, '7031084003572074533');
      final board = (await boards).single;
      expect(calls, 1);
      expect(board.boardId, '7036274230471712007');
      expect(board.previewTracks.single.meta.songId, '6778775242320906241');
      expect(board.previewTracks.single.source, MusicSource.qs);
      expect(board.previewTracks.single.interval, '04:39');
      expect(board.previewTracks.single.singer, '歌手甲、歌手乙');
      expect(await sdk.featured(page: 2), isEmpty);
      await sdk.featured();
      expect(calls, 2); // A refresh obtains new recommendations.
    },
  );

  test(
    'playlist follows opaque cursors and sessions and skips unavailable rows',
    () async {
      final cursors = <String?>[];
      final sdk = QsSdk(
        requester: (url, {required method, required headers, body}) async {
          final query = Uri.parse(url).queryParameters;
          cursors.add(query['cursor']);
          expect(method, 'GET');
          expect(query['playlist_id'], '7031084003572074533');
          if (cursors.length == 1) {
            return {
              'playlist': _playlist,
              'media_resources': [
                _resource('1'),
                {'type': 'unavailable'},
              ],
              'next_cursor': 'opaque:next',
              'session_id': 'session-next',
              'has_more': true,
            };
          }
          expect(query['session_id'], 'session-next');
          return {
            'playlist': _playlist,
            'media_resources': [_resource('1'), _resource('2')],
            'has_more': false,
          };
        },
      );
      final detail = await sdk.playlist('7031084003572074533');
      expect(cursors, ['', 'opaque:next']);
      expect(detail.tracks.map((t) => t.meta.songId), ['1', '2']);
      expect(detail.trackCount, 2); // The upstream advertises three resources.
      expect(detail.creator, '歌单作者');
    },
  );

  test(
    'partial playlist keeps total and does not fetch unrequested pages',
    () async {
      var calls = 0;
      final sdk = QsSdk(
        requester: (url, {required method, required headers, body}) async {
          calls++;
          expect(Uri.parse(url).queryParameters['count'], '1');
          return {
            'playlist': _playlist,
            'media_resources': [_resource('1')],
            'next_cursor': 'next',
            'has_more': true,
          };
        },
      );
      final detail = await sdk.playlist('7031084003572074533', maxTracks: 1);
      expect(calls, 1);
      expect(detail.tracks, hasLength(1));
      expect(detail.totalTracks, 3);
    },
  );

  test(
    'chart preserves its type for saving and respects the requested limit',
    () async {
      final sdk = QsSdk(
        requester: (url, {required method, required headers, body}) async {
          expect(Uri.parse(url).path, '/luna/pc/charts/7036274230471712007');
          return jsonEncode({
            'chart': {
              'title': '热歌榜',
              'track_ranks': [
                {'track': _track('1')},
                {'track': _track('2')},
              ],
            },
          });
        },
      );
      final chart = await sdk.leaderboard(
        'chart:7036274230471712007',
        maxTracks: 1,
      );
      expect(chart.id, 'chart:7036274230471712007');
      expect(chart.totalTracks, 2);
      expect(chart.tracks.single.id, 'qs_1');
      expect(chart.tracks.single.meta.qualitys, isEmpty);
      expect(chart.tracks.single.toJson()['source'], 'qs');
    },
  );

  test(
    'failed homepage can be retried and invalid details are not empty success',
    () async {
      var calls = 0;
      final sdk = QsSdk(
        requester: (url, {required method, required headers, body}) async {
          if (++calls == 1) return {'status_code': 1000016};
          return _home;
        },
      );
      await expectLater(sdk.featured(), throwsException);
      expect(await sdk.featured(), hasLength(1));
      await expectLater(sdk.playlist('123456'), throwsException);
    },
  );

  test(
    'broken pagination cannot replace a saved playlist with partial data',
    () async {
      final sdk = QsSdk(
        requester: (url, {required method, required headers, body}) async => {
          'playlist': _playlist,
          'media_resources': [_resource('1')],
          'next_cursor': 'same-cursor',
          'has_more': true,
        },
      );
      await expectLater(sdk.playlist('7031084003572074533'), throwsException);
    },
  );

  test(
    'existing discovery order appends Qishui and search accepts its code',
    () {
      final order = decodeDiscoverySourceOrder(['kw', 'wy', 'tx', 'kg', 'mg']);
      expect(order, [
        MusicSource.kw,
        MusicSource.wy,
        MusicSource.tx,
        MusicSource.kg,
        MusicSource.mg,
        MusicSource.qs,
      ]);
      expect(decodeEnabledSearchSources(['kw', 'qs']), {
        MusicSource.kw,
        MusicSource.qs,
      });
    },
  );

  test('cover templates and full avatar URLs are handled separately', () {
    expect(
      QsSdk.imageUrl(_cover),
      'https://p3-luna.douyinpic.com/img/cover/path~tplv-b829550vbb-crop-center:640:640.jpg',
    );
    expect(
      QsSdk.imageUrl({
        'uri': 'avatar/path',
        'urls': ['https://images.test/avatar.jpg?size=640'],
        'need_complete_url': true,
      }),
      'https://images.test/avatar.jpg?size=640',
    );
  });

  test('share links identify playlists without misreading track links', () {
    expect(
      PlaylistSdk.parseTarget(
        'https://music.douyin.com/qishui/playlist/7031084003572074533',
      )?.source,
      MusicSource.qs,
    );
    expect(
      PlaylistSdk.parseTarget(
        'https://www.qishui.com/playlist?playlist_id=7031084003572074533',
      )?.id,
      '7031084003572074533',
    );
    expect(
      PlaylistSdk.parseTarget('https://music.douyin.com/qishui/track/123456'),
      isNull,
    );
    expect(kSearchSources, contains(MusicSource.qs));
  });
}

const _cover = {
  'uri': 'cover/path',
  'urls': ['https://p3-luna.douyinpic.com/img/'],
  'template_prefix': 'tplv-b829550vbb',
};
const _playlist = {
  'id': '7031084003572074533',
  'title': '测试推荐歌单',
  'count_tracks': 3,
  'url_cover': _cover,
  'owner': {'nickname': '歌单作者'},
};
Map<String, Object> _track(String id) => {
  'id': id,
  'name': '歌曲$id',
  'duration': 279197,
  'album': {'id': '900000000000000001', 'name': '测试专辑', 'url_cover': _cover},
  'artists': [
    {'name': '歌手甲'},
    {'name': '歌手乙'},
  ],
};
Map<String, Object> _resource(String id) => {
  'entity': {
    'track_wrapper': {'track': _track(id)},
  },
};
final _home = {
  'blocks': [
    {
      'type': 'discover_feed_playlist',
      'inner_block': [
        {
          'resources': [
            {
              'entity': {'playlist': _playlist},
            },
          ],
        },
      ],
    },
    {
      'type': 'discover_top_song_list',
      'inner_block': [
        {
          'type': 'discover_track_top_list',
          'title': '热歌榜',
          'inner_block_id': '7036274230471712007',
          'resources': [
            {
              'entity': {
                'ranked_track': {'track': _track('6778775242320906241')},
              },
            },
          ],
        },
      ],
    },
  ],
};
