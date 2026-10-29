import 'package:test/test.dart';

import 'package:cy_shine_music/core/models/enums.dart';
import 'package:cy_shine_music/core/sdk/internal/crypto_util.dart';
import 'package:cy_shine_music/core/sdk/playlist_adapters/kg_playlist_adapter.dart';
import 'package:cy_shine_music/core/sdk/playlist_sdk.dart';

const _globalId = 'collection_3_509005732_35_0';
const _chain = 'share_token';
const _target = 'global:$_globalId?chain=$_chain';

void main() {
  test('preserves both Kugou share parameters in either query order', () {
    for (final globalKey in ['global_collection_id', 'global_specialid']) {
      for (final query in [
        '$globalKey=$_globalId&chain=$_chain',
        'chain=$_chain&$globalKey=$_globalId',
      ]) {
        for (final source in [MusicSource.all, MusicSource.kg]) {
          final parsed = PlaylistSdk.parseTarget(
            'https://m3ws.kugou.com/share/index.php?$query',
            source: source,
          );
          expect(parsed?.source, MusicSource.kg);
          expect(parsed?.id, _target);
          expect(
            PlaylistSdk.parseTarget(parsed!.id, source: MusicSource.kg)?.id,
            _target,
          );
        }
      }
    }
  });

  test(
    'loads every shared Kugou page and keeps its token for refresh',
    () async {
      final pages = <int>[];
      final playlist = await KgPlaylistAdapter.parse(
        _target,
        jsonLoader: (url, {headers}) async {
          final uri = Uri.parse(url);
          expect(uri.host, 'm3ws.kugou.com');
          expect(uri.path, '/v2/zlist/list');
          final query = Map<String, String>.from(uri.queryParameters);
          expect(query['global_collection_id'], _globalId);
          expect(query['chain'], _chain);
          expect(query['pagesize'], '50');
          expect(query['share_type'], 'collect');
          expect(headers?['clienttime'], query['clienttime']);
          final signature = query.remove('signature');
          final parameters =
              query.entries.map((e) => '${e.key}=${e.value}').toList()..sort();
          const seed = 'NVPh5oo715z5DIWAeQlhMDsWXXQV4hwt';
          expect(
            signature,
            CryptoUtil.md5Hex('$seed${parameters.join()}$seed'),
          );
          final page = int.parse(query['page']!);
          pages.add(page);
          return _sharedPage(page, pageSize: 50, total: 52);
        },
        jsonPoster: _unavailableMetadata,
      );

      expect(pages, [1, 2]);
      expect(playlist.id, _target);
      expect(playlist.name, 'Shared playlist');
      expect(playlist.creator, 'Creator');
      expect(playlist.coverUrl, 'https://img.test/480/cover.jpg');
      expect(playlist.trackCount, 52);
      expect(playlist.tracks, hasLength(52));
      expect(playlist.tracks.last.name, 'Track 52');
      expect(
        PlaylistSdk.parseTarget(playlist.id, source: MusicSource.kg)?.id,
        _target,
      );
    },
  );

  test('continues shared Kugou pages shorter than the known total', () async {
    final pages = <int>[];
    final playlist = await KgPlaylistAdapter.parse(
      _target,
      jsonLoader: (url, {headers}) async {
        final page = int.parse(Uri.parse(url).queryParameters['page']!);
        pages.add(page);
        return _sharedPage(page, pageSize: 25, total: 52, wrapped: false);
      },
      jsonPoster: _unavailableMetadata,
    );
    expect(pages, [1, 2, 3]);
    expect(playlist.tracks, hasLength(52));
  });

  test('limits shared Kugou previews while retaining the full count', () async {
    var requests = 0;
    final playlist = await KgPlaylistAdapter.parse(
      _target,
      maxTracks: 7,
      jsonLoader: (url, {headers}) async {
        requests++;
        expect(Uri.parse(url).queryParameters['pagesize'], '7');
        return _sharedPage(1, pageSize: 7, total: 52);
      },
      jsonPoster: _unavailableMetadata,
    );
    expect(requests, 1);
    expect(playlist.trackCount, 52);
    expect(playlist.tracks, hasLength(7));
  });

  test(
    'resolves a Kugou chain before requesting the shared collection',
    () async {
      final urls = <String>[];
      final playlist = await KgPlaylistAdapter.parse(
        'chain:$_chain',
        jsonLoader: (url, {headers}) async {
          urls.add(url);
          if (url.contains('/schain/transfer')) {
            expect(Uri.parse(url).queryParameters['chain'], _chain);
            return {'global_collection_id': _globalId};
          }
          return _sharedPage(1, pageSize: 50, total: 1);
        },
        jsonPoster: _unavailableMetadata,
      );
      expect(urls, hasLength(2));
      expect(urls.last, contains('/v2/zlist/list'));
      expect(playlist.id, _target);
      expect(playlist.tracks, hasLength(1));
    },
  );

  test('keeps a gcid-shaped chain on the share path before decoding', () async {
    final playlist = await KgPlaylistAdapter.parse(
      'chain:gcid_share_token',
      jsonLoader: (url, {headers}) async {
        final uri = Uri.parse(url);
        expect(uri.queryParameters['chain'], 'gcid_share_token');
        if (uri.path == '/schain/transfer') {
          return {
            'info': {'global_collection_id': _globalId},
          };
        }
        return _sharedPage(1, pageSize: 50, total: 1);
      },
      jsonPoster: (url, {headers, body}) {
        expect(url, isNot(contains('batch_decode')));
        return _unavailableMetadata(url, headers: headers, body: body);
      },
    );
    expect(playlist.id, 'global:$_globalId?chain=gcid_share_token');
    expect(playlist.tracks, hasLength(1));
  });

  test(
    'falls back on a shared API error without discarding the token',
    () async {
      final urls = <String>[];
      final playlist = await KgPlaylistAdapter.parse(
        _target,
        jsonLoader: (url, {headers}) async {
          urls.add(url);
          if (url.contains('/v2/zlist/list')) {
            return {'status': 0, 'error_code': 20010};
          }
          return _globalPage(url);
        },
        jsonPoster: _unavailableMetadata,
      );
      expect(urls.first, contains('/v2/zlist/list'));
      expect(urls.any((url) => url.contains('/special/song_v2')), isTrue);
      expect(playlist.id, _target);
      expect(playlist.tracks, hasLength(2));
    },
  );

  test('continues global Kugou pages shorter than the known total', () async {
    final pages = <int>[];
    final playlist = await KgPlaylistAdapter.parse(
      'global:$_globalId',
      jsonLoader: (url, {headers}) async {
        if (url.contains('/special/song_v2')) {
          pages.add(int.parse(Uri.parse(url).queryParameters['page']!));
        }
        return _globalPage(url);
      },
      jsonPoster: _unavailableMetadata,
    );
    expect(pages, [1, 2]);
    expect(playlist.tracks, hasLength(2));
  });

  test(
    'loads concept-app global playlists from the current list API',
    () async {
      final playlist = await KgPlaylistAdapter.parse(
        'global:$_globalId',
        maxTracks: 1,
        jsonLoader: (url, {headers}) async {
          final uri = Uri.parse(url);
          if (uri.path == '/api/v5/special/info_v2') {
            return {
              'errcode': 0,
              'data': {
                'global_specialid': _globalId,
                'specialname': 'Concept playlist',
                'songcount': 1,
              },
            };
          }

          expect(uri.host, 'pubsongscdn.kugou.com');
          expect(uri.path, '/v2/get_other_list_file');
          final query = Map<String, String>.from(uri.queryParameters);
          expect(query['global_collection_id'], _globalId);
          expect(query['module'], 'playlist');
          expect(query['type'], '0');
          expect(query['page'], '1');
          expect(query['pagesize'], '1');
          expect(query['uid'], '0');
          expect(query['token'], '');
          expect(headers?['clienttime'], query['clienttime']);
          final signature = query.remove('signature');
          final parameters =
              query.entries
                  .map((entry) => '${entry.key}=${entry.value}')
                  .toList()
                ..sort();
          const seed = 'NVPh5oo715z5DIWAeQlhMDsWXXQV4hwt';
          expect(
            signature,
            CryptoUtil.md5Hex('$seed${parameters.join()}$seed'),
          );

          return {
            'error_code': 0,
            'status': 1,
            'data': {
              'count': 1,
              'info': [
                {
                  'audio_id': 92817,
                  'hash': 'CONCEPT-HASH',
                  'name': 'Concept Artist - Concept Track',
                  'singerinfo': [
                    {'name': 'Concept Artist'},
                  ],
                  'size': 2048,
                  'timelen': 180000,
                  'cover': 'http://img.test/concept.jpg',
                  'albuminfo': {'id': 42, 'name': 'Concept Album'},
                  'relate_goods': [
                    {'level': 4, 'hash': 'CONCEPT-320', 'size': 4096},
                  ],
                },
              ],
            },
          };
        },
        jsonPoster: _unavailableMetadata,
      );

      expect(playlist.name, 'Concept playlist');
      expect(playlist.trackCount, 1);
      expect(playlist.tracks, hasLength(1));
      final track = playlist.tracks.single;
      expect(track.name, 'Concept Track');
      expect(track.singer, 'Concept Artist');
      expect(track.albumName, 'Concept Album');
      expect(track.meta.picUrl, 'https://img.test/concept.jpg');
      expect(track.meta.qualitys.map((quality) => quality.type), [
        Quality.k128,
        Quality.k320,
      ]);
      expect(track.meta.qualitys.last.hash, 'CONCEPT-320');
    },
  );

  test('resolves numeric Kugou codes through the command endpoint', () async {
    final urls = <String>[];
    final playlist = await KgPlaylistAdapter.parse(
      '40209961',
      maxTracks: 1,
      jsonLoader: (url, {headers}) async {
        final uri = Uri.parse(url);
        urls.add(uri.path);
        if (uri.path == '/api/v5/special/info_v2') {
          return {
            'errcode': 0,
            'data': {
              'specialname': 'Code playlist',
              'songcount': 1,
              'global_specialid': _globalId,
            },
          };
        }
        expect(uri.host, 'pubsongscdn.kugou.com');
        expect(uri.path, '/v2/get_other_list_file');
        return {
          'error_code': 0,
          'status': 1,
          'data': {
            'count': 1,
            'info': [_song(1)],
          },
        };
      },
      jsonPoster: (url, {headers, body}) async {
        urls.add(Uri.parse(url).path);
        if (url.contains('/command/')) {
          expect(headers?['KG-RC'], '1');
          expect(body, {
            'appid': 1001,
            'clientver': 9020,
            'mid': '21511157a05844bd085308bc76ef3343',
            'clienttime': 640612895,
            'key': '36164c4015e704673c588ee202b9ecb8',
            'data': '40209961',
          });
          return {
            'status': 1,
            'err_code': 0,
            'data': {
              'info': {
                'type': 4,
                'name': 'Code playlist',
                'count': 1,
                'global_collection_id': _globalId,
              },
            },
          };
        }
        return _unavailableMetadata(url, headers: headers, body: body);
      },
    );

    expect(urls.first, '/command/');
    expect(urls, contains('/v2/get_other_list_file'));
    expect(playlist.name, 'Code playlist');
    expect(playlist.tracks, hasLength(1));
  });
}

Map<String, Object?> _song(int index) => {
  'audio_id': index,
  'hash': 'HASH-$index',
  'songname': 'Track $index',
  'singername': 'Singer',
};

Map<String, Object?> _sharedPage(
  int page, {
  required int pageSize,
  required int total,
  bool wrapped = true,
}) {
  final payload = <String, Object?>{
    'info': [
      {
        'name': 'Shared playlist',
        'count': total,
        'pic': 'http://img.test/{size}/cover.jpg',
        'intro': 'Description',
        'list_create_username': 'Creator',
      },
    ],
    'list': {
      'info': [
        for (
          var index = (page - 1) * pageSize + 1;
          index <= page * pageSize && index <= total;
          index++
        )
          _song(index),
      ],
    },
  };
  return {
    'status': 1,
    'error_code': 0,
    if (wrapped) 'data': payload else ...payload,
  };
}

Map<String, Object?> _globalPage(String url) {
  if (url.contains('/special/info_v2')) {
    return {
      'errcode': 0,
      'data': {'specialname': 'Global playlist', 'songcount': 2},
    };
  }
  final page = int.parse(Uri.parse(url).queryParameters['page']!);
  return {
    'errcode': 0,
    'data': {
      'total': 2,
      'info': [_song(page)],
    },
  };
}

Future<dynamic> _unavailableMetadata(
  String url, {
  Map<String, String>? headers,
  Object? body,
}) async => {'error_code': 1};
