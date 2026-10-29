import '../../models/enums.dart';
import '../../models/music_info.dart';
import '../../models/playlist_info.dart';
import '../internal/builders.dart';
import '../internal/crypto_util.dart';
import '../internal/format.dart';
import '../internal/kg_quality.dart';
import '../internal/sdk_http.dart';
import '../kg_sdk.dart';

typedef KgJsonPoster =
    Future<dynamic> Function(
      String url, {
      Map<String, String>? headers,
      Object? body,
    });

class KgPlaylistAdapter {
  const KgPlaylistAdapter._();

  static const _globalPrefix = 'global:';
  static const _chainPrefix = 'chain:';
  static const _gcidPrefix = 'gcid:';
  static const _codePrefix = 'code:';
  static const _kgAndroidSignatureSeed = 'OIlwieks28dk2k092lksi2UIkp';
  static const _kgWebSignatureSeed = 'NVPh5oo715z5DIWAeQlhMDsWXXQV4hwt';

  static const _headers = {
    'User-Agent': 'Mozilla/5.0',
    'Referer': 'https://www.kugou.com/',
  };

  static const _detailHeaders = {
    'KG-THash': '13a3164',
    'KG-RC': '1',
    'KG-Fake': '0',
    'KG-RF': '00869891',
    'User-Agent': 'Android712-AndroidPhone-11451-376-0-FeeCacheUpdate-wifi',
    'x-router': 'kmr.service.kugou.com',
  };

  static Future<PlaylistInfo> parse(
    String id, {
    SdkJsonLoader? jsonLoader,
    KgJsonPoster? jsonPoster,
    int? maxTracks,
  }) async {
    final load = jsonLoader ?? SdkHttp.getJson;
    final post = jsonPoster ?? _postJson;
    // Fixture loaders stay isolated from live privilege requests. The normal
    // app path uses the default loaders and enriches tracks with Atmos/master
    // variants from Kugou's privilege endpoint.
    final enrichQualityDetails = jsonLoader == null && jsonPoster == null;
    final target = id.trim();
    if (target.startsWith(_globalPrefix)) {
      final globalTarget = target.substring(_globalPrefix.length).trim();
      final queryIndex = globalTarget.indexOf('?');
      final globalId = queryIndex < 0
          ? globalTarget
          : globalTarget.substring(0, queryIndex);
      final chain = queryIndex < 0
          ? null
          : _text(
              Uri.splitQueryString(
                globalTarget.substring(queryIndex + 1),
              )['chain'],
            );
      return _parseGlobalCollection(
        globalId,
        chain: chain,
        load: load,
        post: post,
        enrichQualityDetails: enrichQualityDetails,
        maxTracks: maxTracks,
      );
    }
    if (target.startsWith(_chainPrefix)) {
      final chain = target.substring(_chainPrefix.length).trim();
      return _parseChain(
        chain,
        load: load,
        post: post,
        enrichQualityDetails: enrichQualityDetails,
        maxTracks: maxTracks,
      );
    }
    if (target.startsWith(_gcidPrefix)) {
      final gcid = target.substring(_gcidPrefix.length).trim();
      final globalId = await _decodeGcid(gcid, post);
      return _parseGlobalCollection(
        globalId,
        load: load,
        post: post,
        enrichQualityDetails: enrichQualityDetails,
        maxTracks: maxTracks,
      );
    }
    if (target.startsWith(_codePrefix)) {
      final code = target.substring(_codePrefix.length).trim();
      final playlist = await _parseShareCode(
        code,
        load: load,
        post: post,
        enrichQualityDetails: enrichQualityDetails,
        maxTracks: maxTracks,
      );
      if (playlist == null) throw Exception('酷狗码无效或已过期');
      return playlist;
    }
    if (RegExp(r'^\d{4,}$').hasMatch(target)) {
      final codePlaylist = await _parseShareCode(
        target,
        load: load,
        post: post,
        enrichQualityDetails: enrichQualityDetails,
        maxTracks: maxTracks,
      );
      if (codePlaylist != null) return codePlaylist;
    }

    try {
      return await _parseSpecial(
        target,
        load: load,
        post: post,
        enrichQualityDetails: enrichQualityDetails,
        maxTracks: maxTracks,
      );
    } catch (_) {
      final globalId = await _globalCollectionIdForSpecial(target, load);
      if (globalId == null) rethrow;
      return _parseGlobalCollection(
        globalId,
        load: load,
        post: post,
        enrichQualityDetails: enrichQualityDetails,
        maxTracks: maxTracks,
      );
    }
  }

  static Future<PlaylistInfo?> _parseShareCode(
    String code, {
    required SdkJsonLoader load,
    required KgJsonPoster post,
    required bool enrichQualityDetails,
    int? maxTracks,
  }) async {
    if (!RegExp(r'^\d{4,}$').hasMatch(code)) return null;
    try {
      final response = await post(
        'https://t.kugou.com/command/',
        headers: const {
          'KG-RC': '1',
          'KG-THash': 'network_super_call.cpp:3676261689:379',
          'User-Agent':
              'Mozilla/5.0 (Linux; Android 10; HUAWEI HMA-AL00) '
              'AppleWebKit/537.36 Mobile Safari/537.36',
        },
        body: {
          'appid': 1001,
          'clientver': 9020,
          'mid': '21511157a05844bd085308bc76ef3343',
          'clienttime': 640612895,
          'key': '36164c4015e704673c588ee202b9ecb8',
          'data': code,
        },
      );
      final data = response is Map ? response['data'] : null;
      final errorCode = response is Map
          ? _int(response['err_code'] ?? response['error_code'])
          : null;
      final info = data is Map ? data['info'] : null;
      if (response is! Map ||
          _int(response['status']) != 1 ||
          errorCode != 0 ||
          info is! Map) {
        return null;
      }

      final globalId = _text(info['global_collection_id']);
      if (globalId != null) {
        return _parseGlobalCollection(
          globalId,
          load: load,
          post: post,
          enrichQualityDetails: enrichQualityDetails,
          maxTracks: maxTracks,
        );
      }
      final specialId = _text(info['id']);
      if (_int(info['type']) == 2 && specialId != null) {
        return _parseSpecial(
          specialId,
          load: load,
          post: post,
          enrichQualityDetails: enrichQualityDetails,
          maxTracks: maxTracks,
        );
      }
    } catch (_) {
      // A bare number can still be a legacy numeric playlist ID; let that
      // parser try after command-code lookup fails.
    }
    return null;
  }

  static Future<PlaylistInfo> _parseSpecial(
    String id, {
    required SdkJsonLoader load,
    required KgJsonPoster post,
    required bool enrichQualityDetails,
    int? maxTracks,
  }) async {
    final infoBody = await load(
      'http://mobilecdnbj.kugou.com/api/v3/special/info'
      '?version=9108&plat=0&specialid=$id',
      headers: _headers,
    );
    final info = infoBody is Map ? infoBody['data'] : null;
    if (infoBody is! Map || infoBody['status'] != 1 || info is! Map) {
      throw Exception('酷狗歌单信息加载失败');
    }

    const defaultPageSize = 30;
    final hardLimit = _trackLimit(maxTracks);
    final pageSize =
        maxTracks != null && maxTracks > 0 && maxTracks < defaultPageSize
        ? maxTracks
        : defaultPageSize;
    final rawSongs = <Map>[];
    var expected = _int(info['songcount']) ?? 0;
    for (var page = 1; rawSongs.length < hardLimit; page++) {
      final body = await load(
        'http://mobilecdnbj.kugou.com/api/v3/special/song'
        '?version=9108&page=$page&pagesize=$pageSize&plat=0&specialid=$id',
        headers: _headers,
      );
      final data = body is Map ? body['data'] : null;
      if (body is! Map || body['status'] != 1 || data is! Map) {
        throw Exception('酷狗歌单歌曲加载失败');
      }
      expected = _int(data['total']) ?? expected;
      final pageSongs = (data['info'] as List? ?? const [])
          .whereType<Map>()
          .toList(growable: false);
      rawSongs.addAll(pageSongs.take(hardLimit - rawSongs.length));
      if (pageSongs.isEmpty) break;
      if (expected > 0 &&
          rawSongs.length >= _targetCount(expected, hardLimit)) {
        break;
      }
      if (expected <= 0 && pageSongs.length < pageSize) break;
    }

    final songs = await _completeSongs(rawSongs, post);
    final qualityDetails = enrichQualityDetails
        ? await _qualityDetailsFor(songs)
        : const <String, List<QualityOption>>{};
    final tracks = songs
        .take(expected > 0 ? expected : rawSongs.length)
        .map(
          (song) => parseTrack(
            song,
            qualityDetails: qualityDetails[kgHashKey(_trackHash(song))],
          ),
        )
        .whereType<MusicInfo>()
        .toList(growable: false);
    return PlaylistInfo(
      id: id,
      name: info['specialname']?.toString() ?? '酷狗歌单 $id',
      source: MusicSource.kg,
      coverUrl: _image(info['imgurl']),
      creator: _text(info['nickname']),
      description: _text(info['intro']),
      playCount: _int(info['playcount']),
      trackCount: expected > 0 ? expected : tracks.length,
      tracks: dedupeMusic(tracks),
    );
  }

  static Future<PlaylistInfo> _parseGlobalCollection(
    String id, {
    String? chain,
    required SdkJsonLoader load,
    required KgJsonPoster post,
    required bool enrichQualityDetails,
    int? maxTracks,
  }) async {
    if (id.isEmpty) throw Exception('酷狗歌单 ID 无效');
    Map? sharedInfo;
    List<Map>? sharedSongs;
    if (chain != null) {
      try {
        final shared = await _loadSharedCollection(
          id,
          chain: chain,
          load: load,
          maxTracks: maxTracks,
        );
        sharedInfo = shared.info;
        sharedSongs = shared.songs;
      } catch (_) {
        // Older collections may only support the global detail API.
      }
    }
    final info = sharedInfo ?? await _loadGlobalInfo(id, load);
    var expected = _int(info['songcount']) ?? 0;
    var rawSongs = sharedSongs;
    if (rawSongs == null) {
      try {
        final collection = await _loadOtherGlobalSongs(
          id,
          load: load,
          maxTracks: maxTracks,
        );
        rawSongs = collection.songs;
        if (collection.total > 0) expected = collection.total;
      } catch (_) {
        // Keep the older mobile API as a fallback for collections not exposed
        // by the concept-app share endpoint.
        rawSongs = await _loadGlobalSongs(
          id,
          expected: expected,
          load: load,
          maxTracks: maxTracks,
        );
      }
    }
    final songs = await _completeSongs(rawSongs, post);
    final qualityDetails = enrichQualityDetails
        ? await _qualityDetailsFor(songs)
        : const <String, List<QualityOption>>{};
    final tracks = songs
        .take(expected > 0 ? expected : rawSongs.length)
        .map(
          (song) => parseTrack(
            song,
            qualityDetails: qualityDetails[kgHashKey(_trackHash(song))],
          ),
        )
        .whereType<MusicInfo>()
        .toList(growable: false);
    return PlaylistInfo(
      // Retain the share token so refreshing an imported playlist uses it too.
      id: chain == null
          ? _text(info['global_specialid']) ?? id
          : 'global:$id?chain=${Uri.encodeQueryComponent(chain)}',
      name: info['specialname']?.toString() ?? '酷狗歌单 $id',
      source: MusicSource.kg,
      coverUrl: _image(info['imgurl']),
      creator: _text(info['nickname']),
      description: _text(info['intro']),
      playCount: _int(info['playcount']),
      trackCount: expected > 0 ? expected : tracks.length,
      tracks: dedupeMusic(tracks),
    );
  }

  static Future<PlaylistInfo> _parseChain(
    String chain, {
    required SdkJsonLoader load,
    required KgJsonPoster post,
    required bool enrichQualityDetails,
    int? maxTracks,
  }) async {
    if (chain.isEmpty) throw Exception('酷狗分享链接无效');
    String? transferredGlobalId;
    try {
      final transfer = await load(
        Uri.https('m.kugou.com', '/schain/transfer', {
          'pagesize': '50',
          'chain': chain,
          'su': '1',
          'page': '1',
        }).toString(),
        headers: _globalHeaders('1586163263991'),
      );
      if (transfer is Map) {
        final data = transfer['data'];
        final payload = data is Map ? data : transfer;
        final info = payload['info'];
        transferredGlobalId =
            _text(payload['global_collection_id']) ??
            (info is Map ? _text(info['global_collection_id']) : null);
      }
    } catch (_) {
      // Some share links only expose their collection ID in the HTML page.
    }
    if (transferredGlobalId != null) {
      return _parseGlobalCollection(
        transferredGlobalId,
        chain: chain,
        load: load,
        post: post,
        enrichQualityDetails: enrichQualityDetails,
        maxTracks: maxTracks,
      );
    }
    if (chain.startsWith('gcid_')) {
      final globalId = await _decodeGcid(chain, post);
      return _parseGlobalCollection(
        globalId,
        chain: chain,
        load: load,
        post: post,
        enrichQualityDetails: enrichQualityDetails,
        maxTracks: maxTracks,
      );
    }
    final body = await SdkHttp.getText(
      'https://m.kugou.com/share/?chain=$chain&id=$chain',
      headers: const {
        'User-Agent':
            'Mozilla/5.0 (iPhone; CPU iPhone OS 13_2_3 like Mac OS X) '
            'AppleWebKit/605.1.15 Mobile Safari/604.1',
      },
    );
    final globalId =
        _matchFirst(
          body,
          RegExp(r'"global_collection_id":"([A-Za-z0-9_]+)"'),
        ) ??
        _matchFirst(body, RegExp(r'"global_specialid":"([A-Za-z0-9_]+)"'));
    if (globalId != null) {
      return _parseGlobalCollection(
        globalId,
        chain: chain,
        load: load,
        post: post,
        enrichQualityDetails: enrichQualityDetails,
        maxTracks: maxTracks,
      );
    }
    throw Exception('酷狗分享链接不是可导入的歌单');
  }

  static Future<({Map info, List<Map> songs})> _loadSharedCollection(
    String id, {
    required String chain,
    required SdkJsonLoader load,
    int? maxTracks,
  }) async {
    final hardLimit = _trackLimit(maxTracks);
    final pageSize = hardLimit < 50 ? hardLimit : 50;
    final clientTime = DateTime.now().millisecondsSinceEpoch.toString();
    final songs = <Map>[];
    Map? info;
    var total = 0;
    for (var page = 1; songs.length < hardLimit; page++) {
      final body = await load(
        _signedGlobalUrl('/v2/zlist/list', [
          const MapEntry('srcappid', '2919'),
          const MapEntry('clientver', '20000'),
          MapEntry('clienttime', clientTime),
          MapEntry('mid', clientTime),
          MapEntry('uuid', clientTime),
          const MapEntry('dfid', '-'),
          const MapEntry('listid', '15'),
          const MapEntry('type', '0'),
          MapEntry('pagesize', '$pageSize'),
          MapEntry('global_collection_id', id),
          MapEntry('page', '$page'),
          const MapEntry('share_type', 'collect'),
          const MapEntry('appid', '1058'),
          MapEntry('chain', chain),
        ], host: 'm3ws.kugou.com'),
        headers: _globalHeaders(clientTime),
      );
      final data = body is Map ? body['data'] : null;
      final payload = data is Map ? data : body;
      final infos = payload is Map ? payload['info'] : null;
      final list = payload is Map ? payload['list'] : null;
      final items = list is Map ? list['info'] : null;
      final errorCode = body is Map
          ? _int(body['error_code'] ?? body['errcode'] ?? body['err_code'])
          : null;
      if (body is! Map ||
          (body['status'] != null && _int(body['status']) != 1) ||
          (errorCode != null && errorCode != 0) ||
          items is! List) {
        throw Exception('酷狗分享歌单加载失败');
      }
      if (page == 1) {
        if (infos is! List || infos.isEmpty || infos.first is! Map) {
          throw Exception('酷狗分享歌单信息加载失败');
        }
        info = infos.first as Map;
        total = _int(info['count']) ?? 0;
      }
      final pageSongs = items.whereType<Map>().toList(growable: false);
      songs.addAll(pageSongs.take(hardLimit - songs.length));
      if (total > 0 && songs.length >= _targetCount(total, hardLimit)) break;
      if (pageSongs.isEmpty) {
        if (total > songs.length) throw Exception('酷狗分享歌单歌曲不完整');
        break;
      }
      if (total <= 0 && pageSongs.length < pageSize) break;
    }
    return (
      info: {
        'specialname': info?['name'],
        'songcount': total,
        'imgurl': info?['pic'],
        'intro': info?['intro'],
        'nickname': info?['list_create_username'],
        'playcount': info?['playcount'],
      },
      songs: songs,
    );
  }

  static Future<String> _decodeGcid(String gcid, KgJsonPoster post) async {
    if (gcid.isEmpty) throw Exception('酷狗歌单编码无效');
    const params =
        'dfid=-&appid=1005&mid=0&clientver=20109&clienttime=640612895&uuid=-';
    final body = _gcidDecodeBody(gcid);
    final signature = _signedAndroidRequest(params, body);
    final response = await post(
      'https://t.kugou.com/v1/songlist/batch_decode'
      '?$params&signature=$signature',
      headers: const {
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 10; HUAWEI HMA-AL00) '
            'AppleWebKit/537.36 Mobile Safari/537.36',
        'Referer': 'https://m.kugou.com/',
      },
      body: body,
    );
    final err = response is Map
        ? _int(
            response['err_code'] ??
                response['errcode'] ??
                response['error_code'],
          )
        : null;
    final data = response is Map ? response['data'] : null;
    final list = data is Map ? data['list'] : null;
    final first = list is List && list.isNotEmpty ? list.first : null;
    final globalId = first is Map ? _text(first['global_collection_id']) : null;
    if (response is! Map || err != 0 || globalId == null) {
      throw Exception('酷狗歌单编码解析失败');
    }
    return globalId;
  }

  static Future<Map> _loadGlobalInfo(String id, SdkJsonLoader load) async {
    final body = await load(
      _signedGlobalUrl('/api/v5/special/info_v2', [
        const MapEntry('appid', '1058'),
        const MapEntry('specialid', '0'),
        MapEntry('global_specialid', id),
        const MapEntry('format', 'jsonp'),
        const MapEntry('srcappid', '2919'),
        const MapEntry('clientver', '20000'),
        const MapEntry('clienttime', '1586163242519'),
        const MapEntry('mid', '1586163242519'),
        const MapEntry('uuid', '1586163242519'),
        const MapEntry('dfid', '-'),
      ]),
      headers: _globalHeaders('1586163242519'),
    );
    final data = body is Map ? body['data'] : null;
    final err = body is Map
        ? _int(body['errcode'] ?? body['error_code'])
        : null;
    if (body is! Map || err != 0 || data is! Map) {
      throw Exception('酷狗歌单信息加载失败');
    }
    return data;
  }

  static Future<List<Map>> _loadGlobalSongs(
    String id, {
    required int expected,
    required SdkJsonLoader load,
    int? maxTracks,
  }) async {
    const defaultPageSize = 300;
    final hardLimit = _trackLimit(maxTracks);
    final pageSize =
        maxTracks != null && maxTracks > 0 && maxTracks < defaultPageSize
        ? maxTracks
        : defaultPageSize;
    final songs = <Map>[];
    var total = expected;
    for (var page = 1; songs.length < hardLimit; page++) {
      final body = await load(
        _signedGlobalUrl('/api/v5/special/song_v2', [
          const MapEntry('appid', '1058'),
          const MapEntry('specialid', '0'),
          MapEntry('global_specialid', id),
          const MapEntry('plat', '0'),
          const MapEntry('version', '8000'),
          MapEntry('page', '$page'),
          MapEntry('pagesize', '$pageSize'),
          const MapEntry('srcappid', '2919'),
          const MapEntry('clientver', '20000'),
          const MapEntry('clienttime', '1586163263991'),
          const MapEntry('mid', '1586163263991'),
          const MapEntry('uuid', '1586163263991'),
          const MapEntry('dfid', '-'),
        ]),
        headers: _globalHeaders('1586163263991'),
      );
      final data = body is Map ? body['data'] : null;
      final err = body is Map
          ? _int(body['errcode'] ?? body['error_code'] ?? body['err_code'])
          : null;
      if (body is! Map || err != 0 || data is! Map) {
        throw Exception('酷狗歌单歌曲加载失败');
      }
      total = _int(data['total']) ?? total;
      final pageSongs = (data['info'] as List? ?? const [])
          .whereType<Map>()
          .toList(growable: false);
      songs.addAll(pageSongs.take(hardLimit - songs.length));
      if (pageSongs.isEmpty) break;
      if (total > 0 && songs.length >= _targetCount(total, hardLimit)) break;
      if (total <= 0 && pageSongs.length < pageSize) break;
    }
    return songs;
  }

  static Future<({List<Map> songs, int total})> _loadOtherGlobalSongs(
    String id, {
    required SdkJsonLoader load,
    int? maxTracks,
  }) async {
    const defaultPageSize = 20;
    final hardLimit = _trackLimit(maxTracks);
    final pageSize =
        maxTracks != null && maxTracks > 0 && maxTracks < defaultPageSize
        ? maxTracks
        : defaultPageSize;
    final clientTime = DateTime.now().millisecondsSinceEpoch.toString();
    final songs = <Map>[];
    var total = 0;

    for (var page = 1; songs.length < hardLimit; page++) {
      final body = await load(
        _signedGlobalUrl('/v2/get_other_list_file', [
          MapEntry('clienttime', clientTime),
          MapEntry('mid', clientTime),
          MapEntry('uuid', clientTime),
          const MapEntry('dfid', '-'),
          const MapEntry('srcappid', '2919'),
          const MapEntry('clientver', '20000'),
          const MapEntry('appid', '1058'),
          const MapEntry('uid', '0'),
          const MapEntry('token', ''),
          const MapEntry('type', '0'),
          const MapEntry('module', 'playlist'),
          MapEntry('page', '$page'),
          MapEntry('pagesize', '$pageSize'),
          MapEntry('global_collection_id', id),
        ], host: 'pubsongscdn.kugou.com'),
        headers: _globalHeaders(clientTime),
      );
      final data = body is Map ? body['data'] : null;
      final errorCode = body is Map ? _int(body['error_code']) : null;
      if (body is! Map ||
          errorCode != 0 ||
          _int(body['status']) != 1 ||
          data is! Map ||
          data['info'] is! List) {
        throw Exception('酷狗新版歌单歌曲加载失败');
      }

      total = _int(data['count']) ?? total;
      final pageSongs = (data['info'] as List).whereType<Map>().toList(
        growable: false,
      );
      songs.addAll(pageSongs.take(hardLimit - songs.length));
      if (pageSongs.isEmpty) {
        if (total > songs.length) throw Exception('酷狗新版歌单歌曲不完整');
        break;
      }
      if (total > 0 && songs.length >= _targetCount(total, hardLimit)) break;
      if (total <= 0 && pageSongs.length < pageSize) break;
    }

    return (songs: songs, total: total);
  }

  static Future<String?> _globalCollectionIdForSpecial(
    String id,
    SdkJsonLoader load,
  ) async {
    if (!RegExp(r'^\d{4,}$').hasMatch(id)) return null;
    try {
      final body = await load(
        'http://mobilecdnbj.kugou.com/api/v5/special/info?specialid=$id',
        headers: _headers,
      );
      final data = body is Map ? body['data'] : null;
      if (data is! Map) return null;
      return _text(data['global_specialid']);
    } catch (_) {
      return null;
    }
  }

  static Future<List<Map>> _completeSongs(
    List<Map> rawSongs,
    KgJsonPoster post,
  ) async {
    if (rawSongs.isEmpty) return rawSongs;
    final completed = List<Map>.from(rawSongs);
    for (var start = 0; start < rawSongs.length; start += 100) {
      final end = (start + 100).clamp(0, rawSongs.length);
      final batch = rawSongs.sublist(start, end);
      try {
        final body = await post(
          'http://gateway.kugou.com/v3/album_audio/audio',
          headers: _detailHeaders,
          body: {
            'data': [
              for (final song in batch)
                {'hash': _text(song['hash'] ?? song['FileHash']) ?? ''},
            ],
            'area_code': '1',
            'show_privilege': 1,
            'show_album_info': '1',
            'is_publish': '',
            'appid': 1005,
            'clientver': 11451,
            'mid': '1',
            'dfid': '-',
            'clienttime': DateTime.now().millisecondsSinceEpoch,
            'key': 'OIlwieks28dk2k092lksi2UIkp',
            'fields':
                'album_info,author_name,audio_info,ori_audio_name,base,'
                'songname,classification',
          },
        );
        final groups = body is Map ? body['data'] : null;
        final errorCode = body is Map
            ? _int(body['error_code'] ?? body['errcode'])
            : null;
        if (body is! Map || errorCode != 0 || groups is! List) continue;
        for (var offset = 0; offset < batch.length; offset++) {
          if (offset >= groups.length) break;
          final detail = _firstDetail(groups[offset]);
          if (detail != null) {
            completed[start + offset] = _mergeSongDetail(batch[offset], detail);
          }
        }
      } catch (_) {
        // Old playlist fields remain usable when metadata completion fails.
      }
    }
    return completed;
  }

  static Future<dynamic> _postJson(
    String url, {
    Map<String, String>? headers,
    Object? body,
  }) async {
    final response = await SdkHttp.fetch<dynamic>(
      url,
      method: 'POST',
      headers: headers,
      body: body,
    );
    return response.body;
  }

  static Map? _firstDetail(Object? group) {
    if (group is Map) return group;
    if (group is! List) return null;
    for (final item in group) {
      if (item is Map) return item;
    }
    return null;
  }

  static Map _mergeSongDetail(Map raw, Map detail) {
    final merged = Map<dynamic, dynamic>.from(raw);
    for (final entry in detail.entries) {
      final value = entry.value;
      if (value == null) continue;
      if (value is String && value.trim().isEmpty) continue;
      final existing = merged[entry.key];
      if (existing is Map && value is Map) {
        merged[entry.key] = _mergeSongDetail(existing, value);
      } else {
        merged[entry.key] = value;
      }
    }
    return merged;
  }

  static Future<Map<String, List<QualityOption>>> _qualityDetailsFor(
    Iterable<Map> songs,
  ) async {
    final resources = <KgPrivilegeResource>[];
    for (final song in songs) {
      final hash = _trackHash(song);
      if (hash.isEmpty) continue;
      final audio = song['audio_info'] as Map?;
      final album = song['album_info'] as Map?;
      resources.add(
        KgPrivilegeResource(
          hash: hash,
          albumId: audio?['album_id'] ?? album?['album_id'] ?? song['album_id'],
        ),
      );
    }
    return KgSdk.getQualityDetails(resources);
  }

  static String _trackHash(Map item) {
    final audio = item['audio_info'] as Map?;
    return _text(audio?['hash'] ?? item['hash'] ?? item['FileHash']) ?? '';
  }

  static MusicInfo? parseTrack(
    Map item, {
    Iterable<QualityOption>? qualityDetails,
  }) {
    final audio = item['audio_info'] as Map?;
    final album = item['album_info'] as Map?;
    final baseHash =
        _text(audio?['hash']) ?? _text(item['hash'] ?? item['FileHash']);
    final songId =
        audio?['audio_id'] ??
        item['audio_id'] ??
        item['album_audio_id'] ??
        item['songid'];
    if (songId == null || baseHash == null) return null;

    final qualities = <QualityOption>[];
    void add(Quality quality, Object? bytes, Object? hash) {
      final hashText = _text(hash);
      final size = sizeFormat(bytes);
      if (hashText == null && size == null) return;
      qualities.add(QualityOption(type: quality, size: size, hash: hashText));
    }

    final relatedGoods = item['relate_goods'] as List? ?? const [];
    final relatedByQuality = <Quality, QualityOption>{};
    for (final good in relatedGoods.whereType<Map>()) {
      final quality = switch (_int(good['level'])) {
        2 => Quality.k128,
        4 => Quality.k320,
        5 => Quality.flac,
        6 => Quality.hires,
        _ => null,
      };
      final size = sizeFormat(good['size']);
      if (quality == null || size == null) continue;
      relatedByQuality[quality] = QualityOption(
        type: quality,
        size: size,
        hash: _text(good['hash']),
      );
    }

    add(
      Quality.k128,
      audio?['filesize'] ??
          audio?['filesize_128'] ??
          item['filesize'] ??
          item['size'],
      baseHash,
    );
    add(
      Quality.k320,
      audio?['filesize_320'] ?? item['320filesize'] ?? item['filesize_320'],
      audio?['hash_320'] ?? item['320hash'] ?? item['hash_320'],
    );
    add(
      Quality.flac,
      audio?['filesize_flac'] ?? item['sqfilesize'] ?? item['filesize_flac'],
      audio?['hash_flac'] ?? item['sqhash'] ?? item['hash_flac'],
    );
    add(
      Quality.flac24bit,
      audio?['filesize_high'] ?? item['filesize_high'],
      audio?['hash_high'] ?? item['hash_high'],
    );
    add(Quality.ape, item['filesize_ape'], item['hash_ape']);
    final qualityFallback = [...qualities];
    for (final related in relatedByQuality.values) {
      final index = qualityFallback.indexWhere(
        (option) => option.type == related.type,
      );
      if (index < 0) {
        qualityFallback.add(related);
      } else {
        qualityFallback[index] = related;
      }
    }
    final mergedQualities = qualityDetails == null
        ? qualityFallback
        : mergeKgQualityOptions(qualityFallback, qualityDetails);

    var name = _text(item['songname'] ?? item['SongName']);
    var singer =
        _text(item['author_name'] ?? item['singername']) ??
        formatSingerName(item['authors'], nameKey: 'author_name');
    final singerInfo = item['singerinfo'] as List?;
    if (singer.isEmpty && singerInfo != null) {
      singer = singerInfo
          .whereType<Map>()
          .map((author) => _text(author['name']))
          .whereType<String>()
          .join('、');
    }
    final filename = _text(item['filename'] ?? item['name']) ?? '';
    if (name == null && filename.isNotEmpty) {
      final separator = filename.indexOf(' - ');
      if (separator >= 0) {
        singer = filename.substring(0, separator).trim();
        name = filename.substring(separator + 3).trim();
      } else {
        name = filename;
      }
    }
    final durationMs = num.tryParse(
      (audio?['timelength'] ?? item['timelen'])?.toString() ?? '',
    );
    final durationSeconds = durationMs == null
        ? num.tryParse(item['duration']?.toString() ?? '0') ?? 0
        : durationMs / 1000;
    final albumInfo = item['albuminfo'] as Map?;
    final albumName = _text(
      album?['album_name'] ??
          albumInfo?['name'] ??
          item['album_name'] ??
          item['remark'],
    );
    final audioTrans = audio?['trans_param'] as Map?;
    final itemTrans = item['trans_param'] as Map?;
    return buildMusicInfo(
      name: decodeName(name),
      singer: decodeName(singer),
      source: MusicSource.kg,
      songId: songId,
      qualitys: mergedQualities,
      interval: formatPlayTime(durationSeconds),
      albumName: decodeName(albumName),
      albumId: album?['album_id'] ?? albumInfo?['id'] ?? item['album_id'],
      hash: baseHash,
      picUrl: _image(
        album?['sizable_cover'] ??
            audioTrans?['union_cover'] ??
            itemTrans?['union_cover'] ??
            item['cover'] ??
            item['image'] ??
            item['Image'] ??
            item['img'] ??
            item['imgurl'] ??
            item['album_img'] ??
            item['album_imgurl'],
      ),
    );
  }

  static int? _int(Object? value) =>
      value is num ? value.toInt() : int.tryParse(value?.toString() ?? '');

  static int _trackLimit(int? maxTracks) {
    const hardLimit = 10000;
    if (maxTracks == null || maxTracks <= 0 || maxTracks > hardLimit) {
      return hardLimit;
    }
    return maxTracks;
  }

  static int _targetCount(int expected, int hardLimit) =>
      expected < hardLimit ? expected : hardLimit;

  static String? _text(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  static String? _image(Object? value) {
    var text = _text(value)?.replaceAll('{size}', '480');
    if (text == null) return null;
    if (text.startsWith('//')) text = 'https:$text';
    if (text.startsWith('http://')) {
      text = text.replaceFirst('http://', 'https://');
    }
    return text;
  }

  static String _signedGlobalUrl(
    String path,
    List<MapEntry<String, String>> parameters, {
    String host = 'mobiles.kugou.com',
  }) {
    final signText =
        parameters.map((entry) => '${entry.key}=${entry.value}').toList()
          ..sort();
    final signature = CryptoUtil.md5Hex(
      '$_kgWebSignatureSeed${signText.join()}$_kgWebSignatureSeed',
    );
    final query = [
      for (final entry in parameters)
        '${Uri.encodeQueryComponent(entry.key)}='
            '${Uri.encodeQueryComponent(entry.value)}',
      'signature=$signature',
    ].join('&');
    return 'https://$host$path?$query';
  }

  static String _signedAndroidRequest(String params, String body) {
    final signText = params.split('&')..sort();
    return CryptoUtil.md5Hex(
      '$_kgAndroidSignatureSeed${signText.join()}$body'
      '$_kgAndroidSignatureSeed',
    );
  }

  static String _gcidDecodeBody(String gcid) {
    return '{"ret_info":1,"data":[{"id":"$gcid","id_type":2}]}';
  }

  static Map<String, String> _globalHeaders(String clientTime) => {
    'mid': clientTime,
    'Referer': 'https://m3ws.kugou.com/share/index.php',
    'User-Agent':
        'Mozilla/5.0 (iPhone; CPU iPhone OS 11_0 like Mac OS X) '
        'AppleWebKit/604.1.38 (KHTML, like Gecko) Version/11.0 Mobile/15A372 '
        'Safari/604.1',
    'dfid': '-',
    'clienttime': clientTime,
  };

  static String? _matchFirst(String text, RegExp pattern) {
    final match = pattern.firstMatch(text);
    return match?.group(1);
  }
}
