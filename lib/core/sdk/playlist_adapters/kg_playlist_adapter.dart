import '../../models/enums.dart';
import '../../models/music_info.dart';
import '../../models/playlist_info.dart';
import '../internal/builders.dart';
import '../internal/format.dart';
import '../internal/sdk_http.dart';

typedef KgJsonPoster =
    Future<dynamic> Function(
      String url, {
      Map<String, String>? headers,
      Object? body,
    });

class KgPlaylistAdapter {
  const KgPlaylistAdapter._();

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
  }) async {
    final load = jsonLoader ?? SdkHttp.getJson;
    final infoBody = await load(
      'http://mobilecdnbj.kugou.com/api/v3/special/info'
      '?version=9108&plat=0&specialid=$id',
      headers: _headers,
    );
    final info = infoBody is Map ? infoBody['data'] : null;
    if (infoBody is! Map || infoBody['status'] != 1 || info is! Map) {
      throw Exception('酷狗歌单信息加载失败');
    }

    const pageSize = 30;
    const maxTracks = 10000;
    final rawSongs = <Map>[];
    var expected = _int(info['songcount']) ?? 0;
    for (var page = 1; rawSongs.length < maxTracks; page++) {
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
      rawSongs.addAll(pageSongs.take(maxTracks - rawSongs.length));
      if (pageSongs.isEmpty) break;
      if (expected > 0 && rawSongs.length >= expected) break;
      if (expected <= 0 && pageSongs.length < pageSize) break;
    }

    final songs = await _completeSongs(rawSongs, jsonPoster ?? _postJson);
    final tracks = songs
        .take(expected > 0 ? expected : rawSongs.length)
        .map(_parseSong)
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
          if (detail != null) completed[start + offset] = detail;
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

  static MusicInfo? _parseSong(Map item) {
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

    add(
      Quality.k128,
      audio?['filesize'] ?? audio?['filesize_128'] ?? item['filesize'],
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

    var name = _text(item['songname'] ?? item['SongName']);
    var singer = _text(item['author_name'] ?? item['singername']) ?? '';
    final filename = _text(item['filename']) ?? '';
    if (name == null && filename.isNotEmpty) {
      final separator = filename.indexOf(' - ');
      if (separator >= 0) {
        singer = filename.substring(0, separator).trim();
        name = filename.substring(separator + 3).trim();
      } else {
        name = filename;
      }
    }
    final durationMs = num.tryParse(audio?['timelength']?.toString() ?? '');
    final durationSeconds = durationMs == null
        ? num.tryParse(item['duration']?.toString() ?? '0') ?? 0
        : durationMs / 1000;
    final albumName = _text(album?['album_name'] ?? item['album_name']);
    final audioTrans = audio?['trans_param'] as Map?;
    final itemTrans = item['trans_param'] as Map?;
    return buildMusicInfo(
      name: decodeName(name),
      singer: decodeName(singer),
      source: MusicSource.kg,
      songId: songId,
      qualitys: qualities,
      interval: formatPlayTime(durationSeconds),
      albumName: decodeName(albumName),
      albumId: album?['album_id'] ?? item['album_id'],
      hash: baseHash,
      picUrl: _image(
        album?['sizable_cover'] ??
            audioTrans?['union_cover'] ??
            itemTrans?['union_cover'] ??
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
}
