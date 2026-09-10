import 'dart:convert';
import 'dart:typed_data';

import '../models/enums.dart';
import '../models/leaderboard_info.dart';
import '../models/music_info.dart';
import '../models/playlist_info.dart';
import '../ui/cover_image_source.dart';
import 'internal/builders.dart';
import 'internal/crypto_util.dart';
import 'internal/format.dart';
import 'internal/sdk_http.dart';
import 'internal/tx_quality.dart';
import 'leaderboard_catalog.dart';
import 'playlist_adapters/kg_playlist_adapter.dart';
import 'playlist_adapters/kw_playlist_adapter.dart';
import 'playlist_adapters/mg_playlist_adapter.dart';
import 'playlist_sdk.dart';

typedef LeaderboardJsonPoster =
    Future<dynamic> Function(
      String url, {
      Map<String, String>? headers,
      Object? body,
    });

typedef LeaderboardPlaylistLoader =
    Future<PlaylistInfo> Function(
      String id, {
      required MusicSource source,
      int? maxTracks,
    });

class LeaderboardSdk {
  const LeaderboardSdk._();

  static final Uint8List _kwKey = Uint8List.fromList(const [
    112,
    87,
    39,
    61,
    199,
    250,
    41,
    191,
    57,
    68,
    45,
    114,
    221,
    94,
    140,
    228,
  ]);
  static const _kwAppId = 'y67sprxhhpws';

  static List<LeaderboardSummary> boards(MusicSource source) =>
      List<LeaderboardSummary>.unmodifiable(leaderboardCatalogFor(source));

  static Future<LeaderboardSummary> preview(
    LeaderboardSummary board, {
    int limit = 3,
    SdkJsonLoader? jsonLoader,
    LeaderboardJsonPoster? jsonPoster,
    LeaderboardPlaylistLoader? playlistLoader,
  }) async {
    final detail = await get(
      source: board.source,
      boardId: board.boardId,
      maxTracks: limit,
      jsonLoader: jsonLoader,
      jsonPoster: jsonPoster,
      playlistLoader: playlistLoader,
    );
    return board.copyWith(
      coverUrl: detail.coverUrl,
      updateFrequency: board.updateFrequency ?? _updateFrequency(board, detail),
      previewTracks: detail.tracks.take(limit).toList(growable: false),
    );
  }

  static Future<PlaylistInfo> get({
    required MusicSource source,
    required String boardId,
    int? maxTracks,
    SdkJsonLoader? jsonLoader,
    LeaderboardJsonPoster? jsonPoster,
    LeaderboardPlaylistLoader? playlistLoader,
  }) {
    final board = _findBoard(source, boardId);
    return switch (source) {
      MusicSource.wy => (playlistLoader ?? _loadPlaylist)(
        boardId,
        source: source,
        maxTracks: maxTracks,
      ),
      MusicSource.tx => _getTx(
        board,
        maxTracks: maxTracks,
        post: jsonPoster ?? _postJson,
      ),
      MusicSource.kw => _getKw(
        board,
        maxTracks: maxTracks,
        load: jsonLoader ?? SdkHttp.getJson,
      ),
      MusicSource.kg => _getKg(
        board,
        maxTracks: maxTracks,
        load: jsonLoader ?? SdkHttp.getJson,
      ),
      MusicSource.mg => _getMg(
        board,
        maxTracks: maxTracks,
        load: jsonLoader ?? SdkHttp.getJson,
      ),
      MusicSource.all => throw Exception('排行榜不支持“全部”音源'),
    };
  }

  static LeaderboardSummary _findBoard(MusicSource source, String boardId) {
    for (final board in leaderboardCatalogFor(source)) {
      if (board.boardId == boardId || board.id == boardId) return board;
    }
    final nativeId = boardId.replaceFirst('${source.code}__', '');
    return LeaderboardSummary(
      id: '${source.code}__$nativeId',
      boardId: nativeId,
      name: '${source.label}排行榜',
      source: source,
    );
  }

  static Future<PlaylistInfo> _loadPlaylist(
    String id, {
    required MusicSource source,
    int? maxTracks,
  }) {
    return PlaylistSdk.parse(input: id, source: source, maxTracks: maxTracks);
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
    return _decodeJson(response.body);
  }

  static Future<PlaylistInfo> _getTx(
    LeaderboardSummary board, {
    required int? maxTracks,
    required LeaderboardJsonPoster post,
  }) async {
    final limit = _limit(maxTracks, fallback: 300, maximum: 300);
    final body = _decodeJson(
      await post(
        'https://u.y.qq.com/cgi-bin/musicu.fcg',
        headers: const {
          'User-Agent':
              'Mozilla/5.0 (compatible; MSIE 9.0; Windows NT 6.1; '
              'WOW64; Trident/5.0)',
        },
        body: {
          'toplist': {
            'module': 'musicToplist.ToplistInfoServer',
            'method': 'GetDetail',
            'param': {
              'topid': int.tryParse(board.boardId) ?? board.boardId,
              'num': limit,
            },
          },
          'comm': {'uin': 0, 'format': 'json', 'ct': 20, 'cv': 1859},
        },
      ),
    );
    final request = body is Map ? body['toplist'] : null;
    final data = request is Map ? request['data'] : null;
    if (body is! Map ||
        body['code'] != 0 ||
        request is! Map ||
        request['code'] != 0 ||
        data is! Map) {
      throw Exception('QQ 排行榜加载失败');
    }
    final info = data['data'] as Map? ?? const {};
    final songs = (data['songInfoList'] as List? ?? const []).whereType<Map>();
    final tracks = songs
        .map(_parseTxTrack)
        .whereType<MusicInfo>()
        .toList(growable: false);
    return PlaylistInfo(
      id: board.boardId,
      name: _text(info['title']) ?? board.name,
      source: MusicSource.tx,
      tracks: dedupeMusic(tracks),
      coverUrl: _httpsImage(info['frontPicUrl'] ?? info['headPicUrl']),
      creator: 'QQ音乐',
      description: _plainText(info['intro']),
      playCount: _int(info['listenNum']),
      trackCount: _int(info['totalNum']) ?? tracks.length,
    );
  }

  static MusicInfo? _parseTxTrack(Map item) {
    final file = item['file'];
    final songMid = item['mid'];
    final mediaMid = file is Map ? file['media_mid'] : null;
    if (file is! Map || songMid == null || mediaMid == null) return null;
    final album = item['album'] as Map?;
    final albumMid = _text(album?['mid']) ?? '';
    return buildMusicInfo(
      name: _text(item['title'] ?? item['name']) ?? '',
      singer: formatSingerName(item['singer']),
      source: MusicSource.tx,
      songId: songMid,
      qualitys: parseTxQualityOptions(fileData: file, versions: item['vs']),
      interval: formatPlayTime(
        num.tryParse(item['interval']?.toString() ?? '0') ?? 0,
      ),
      albumName: _text(album?['name']) ?? '',
      albumId: albumMid,
      picUrl: albumMid.isEmpty
          ? null
          : 'https://y.gtimg.cn/music/photo_new/T002R500x500M000$albumMid.jpg',
      strMediaMid: mediaMid.toString(),
      metaId: item['id'],
      albumMid: albumMid,
    );
  }

  static Future<PlaylistInfo> _getKg(
    LeaderboardSummary board, {
    required int? maxTracks,
    required SdkJsonLoader load,
  }) async {
    const pageCapacity = 100;
    final requested = maxTracks != null && maxTracks > 0 ? maxTracks : 1000;
    final songs = <Map>[];
    var total = 0;
    for (var page = 1; songs.length < requested; page++) {
      final remaining = requested - songs.length;
      final pageSize = remaining < pageCapacity ? remaining : pageCapacity;
      final uri = Uri.http('mobilecdnbj.kugou.com', '/api/v3/rank/song', {
        'version': '9108',
        'ranktype': '1',
        'plat': '0',
        'pagesize': '$pageSize',
        'area_code': '1',
        'page': '$page',
        'rankid': board.boardId,
        'with_res_tag': '0',
        'show_portrait_mv': '1',
      });
      final body = await load(uri.toString());
      final data = body is Map ? body['data'] : null;
      if (body is! Map || body['errcode'] != 0 || data is! Map) {
        throw Exception('酷狗排行榜加载失败');
      }
      total = _int(data['total']) ?? total;
      final pageSongs = (data['info'] as List? ?? const [])
          .whereType<Map>()
          .toList(growable: false);
      songs.addAll(pageSongs.take(remaining));
      if (pageSongs.length < pageSize || (total > 0 && songs.length >= total)) {
        break;
      }
    }
    final tracks = songs
        .map(KgPlaylistAdapter.parseTrack)
        .whereType<MusicInfo>()
        .toList(growable: false);
    final cover = tracks
        .map((item) => item.meta.picUrl)
        .whereType<String>()
        .firstOrNull;
    return PlaylistInfo(
      id: board.boardId,
      name: board.name,
      source: MusicSource.kg,
      tracks: dedupeMusic(tracks),
      coverUrl: cover,
      creator: '酷狗音乐',
      trackCount: total > 0 ? total : tracks.length,
    );
  }

  static Future<PlaylistInfo> _getMg(
    LeaderboardSummary board, {
    required int? maxTracks,
    required SdkJsonLoader load,
  }) async {
    final body = await load(
      'https://app.c.nf.migu.cn/MIGUM2.0/v1.0/content/'
      'querycontentbyId.do?columnId=${board.boardId}&needAll=0',
      headers: const {
        'Referer': 'https://app.c.nf.migu.cn/',
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 5.1.1) AppleWebKit/537.36 '
            'Mobile Safari/537.36',
        'channel': '0146921',
      },
    );
    final info = body is Map ? body['columnInfo'] : null;
    if (body is! Map || body['code'] != '000000' || info is! Map) {
      throw Exception('咪咕排行榜加载失败');
    }
    final limit = _limit(maxTracks, fallback: 200, maximum: 200);
    final tracks = (info['contents'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => item['objectInfo'])
        .whereType<Map>()
        .take(limit)
        .map(MgPlaylistAdapter.parseTrack)
        .whereType<MusicInfo>()
        .toList(growable: false);
    final operations = info['opNumItem'] as Map?;
    return PlaylistInfo(
      id: board.boardId,
      name: _text(info['columnTitle']) ?? board.name,
      source: MusicSource.mg,
      tracks: dedupeMusic(tracks),
      coverUrl: _httpsImage(info['columnPicUrl'] ?? info['columnSmallpicUrl']),
      creator: '咪咕音乐',
      description: _text(info['columnDes']),
      playCount: _int(operations?['playNum']),
      trackCount: _int(info['contentsCount']) ?? tracks.length,
    );
  }

  static Future<PlaylistInfo> _getKw(
    LeaderboardSummary board, {
    required int? maxTracks,
    required SdkJsonLoader load,
  }) async {
    const pageCapacity = 100;
    final requested = maxTracks != null && maxTracks > 0 ? maxTracks : 1000;
    final songs = <Map>[];
    Map? firstPage;
    var total = 0;
    for (var page = 0; songs.length < requested; page++) {
      final remaining = requested - songs.length;
      final pageSize = remaining < pageCapacity ? remaining : pageCapacity;
      final request = <String, dynamic>{
        'uid': '',
        'devId': '',
        'sFrom': 'kuwo_sdk',
        'user_type': 'AP',
        'carSource': 'kwplayercar_ar_6.0.1.0_apk_keluze.apk',
        'id': board.boardId,
        'pn': page,
        'rn': pageSize,
      };
      final encoded = base64.encode(
        CryptoUtil.aesEncryptEcbPkcs7(
          Uint8List.fromList(utf8.encode(jsonEncode(request))),
          _kwKey,
        ),
      );
      final time = DateTime.now().millisecondsSinceEpoch;
      final sign = CryptoUtil.md5Hex('$_kwAppId$encoded$time').toUpperCase();
      final uri = Uri.https('wbd.kuwo.cn', '/api/bd/bang/bang_info', {
        'data': encoded,
        'time': '$time',
        'appId': _kwAppId,
        'sign': sign,
      });
      final body = _decodeKw(await load(uri.toString()));
      final data = body is Map ? body['data'] : null;
      if (body is! Map || body['code'] != 200 || data is! Map) {
        throw Exception('酷我排行榜加载失败');
      }
      firstPage ??= data;
      total = _int(data['total']) ?? total;
      final pageSongs = (data['musiclist'] as List? ?? const [])
          .whereType<Map>()
          .toList(growable: false);
      songs.addAll(pageSongs.take(remaining));
      if (pageSongs.length < pageSize || (total > 0 && songs.length >= total)) {
        break;
      }
    }
    final data = firstPage;
    if (data == null) throw Exception('酷我排行榜加载失败');
    final tracks = songs
        .map(KwPlaylistAdapter.parseTrack)
        .whereType<MusicInfo>()
        .toList(growable: false);
    return PlaylistInfo(
      id: board.boardId,
      name: _text(data['name']) ?? board.name,
      source: MusicSource.kw,
      tracks: dedupeMusic(tracks),
      coverUrl: CoverImageSource.normalizeUrl(_text(data['pic'])),
      creator: '酷我音乐',
      description: _text(data['info']),
      trackCount: total > 0 ? total : tracks.length,
    );
  }

  static dynamic _decodeKw(dynamic encrypted) {
    if (encrypted is Map) return encrypted;
    if (encrypted is! String || encrypted.trim().isEmpty) return encrypted;
    try {
      final decoded = Uri.decodeComponent(encrypted.trim());
      final clear = CryptoUtil.aesDecryptEcbPkcs7(
        base64.decode(decoded),
        _kwKey,
      );
      return jsonDecode(utf8.decode(clear));
    } catch (_) {
      return encrypted;
    }
  }

  static dynamic _decodeJson(dynamic body) {
    if (body is! String) return body;
    try {
      return jsonDecode(body);
    } catch (_) {
      return body;
    }
  }

  static int _limit(
    int? requested, {
    required int fallback,
    required int maximum,
  }) {
    if (requested == null || requested <= 0) return fallback;
    return requested > maximum ? maximum : requested;
  }

  static String _updateFrequency(
    LeaderboardSummary board,
    PlaylistInfo detail,
  ) {
    final text = '${board.name}\n${detail.description ?? ''}';
    if (text.contains('实时')) return '实时更新';
    if (text.contains('每周') || text.contains('周榜')) return '每周更新';
    if (text.contains('每月') || text.contains('月榜')) return '每月更新';
    return '每日更新';
  }

  static int? _int(Object? value) =>
      value is num ? value.toInt() : int.tryParse(value?.toString() ?? '');

  static String? _text(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  static String? _httpsImage(Object? value) {
    var text = _text(value);
    if (text == null) return null;
    if (text.startsWith('//')) text = 'https:$text';
    if (text.startsWith('http://')) {
      text = text.replaceFirst('http://', 'https://');
    }
    return text;
  }

  static String? _plainText(Object? value) {
    final text = _text(value);
    return text?.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
  }
}
