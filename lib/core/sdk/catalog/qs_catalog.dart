import 'dart:math';

import '../../models/catalog_result.dart';
import '../../models/enums.dart';
import '../../models/music_info.dart';
import '../../models/playlist_info.dart';
import '../../models/playlist_summary.dart';
import '../../models/search_category.dart';
import '../internal/builders.dart';
import '../qs_sdk.dart';

// The upstream search endpoint serves fixed 20-item pages; it rejects `count`.
const int qsSearchPageSize = 20;
final qishuiCatalog = QsCatalog(qishuiSdk);

class QsCatalog {
  QsCatalog(this._sdk);
  final QsSdk _sdk;
  final _searchCache = <String, ({DateTime expires, Future<Map> value})>{};
  Future<Map<String, String>>? _device;
  Future<void> _requestTail = Future.value();
  DateTime? _lastRead;

  Future<Map> _get(String path, {Map<String, String> query = const {}}) {
    final result = _requestTail.then((_) async {
      final device = await (_device ??= _registerDevice());
      final elapsed = _lastRead == null
          ? 600
          : DateTime.now().difference(_lastRead!).inMilliseconds;
      if (elapsed < 600) {
        await Future<void>.delayed(Duration(milliseconds: 600 - elapsed));
      }
      try {
        return await _sdk.request(path, query: {...device, ...query});
      } on QsEmptyResponseException {
        await Future<void>.delayed(const Duration(milliseconds: 600));
        return await _sdk.request(path, query: {...device, ...query});
      } finally {
        _lastRead = DateTime.now();
      }
    });
    _requestTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  Future<Map<String, String>> _registerDevice() async {
    try {
      final uuid = _uuid();
      final data = await _sdk.request(
        '/service/2/desktop/device_register/',
        query: {
          'device_platform': 'PC',
          'os': 'Windows',
          'app_version': '3.7.0',
        },
        body: {
          'header': {
            'device_id': '',
            'install_id': '',
            'os': 'Windows',
            'device_platform': 'PC',
            'sdk_version': '1.0',
            'sdk_version_code': 1,
            'aid': 386088,
            'mc': '00:00:00:00:00:00',
            'channel': 'official',
            'package': 'com.soda.music',
            'language': 'zh-CN',
            'app_version': '3.7.0',
            'os_version': 'Windows 10: 10.0',
            'device_model': 'no detected',
            'time_zone': 'Asia/Shanghai',
            'tz_name': 'Asia/Shanghai',
            'tz_offset': 0,
            'resolution': 'no detected',
            'app_region': 'cn',
            'app_language': 'zh-CN',
            'display_name': '汽水音乐',
            'pc_uuid': uuid,
            'pc_serial': '',
          },
          'gen_time': DateTime.now().millisecondsSinceEpoch,
          'magic_tag': 'ss_app_log',
        },
      );
      final did = _text(data['device_id_str']);
      final iid = _text(data['install_id_str']);
      if (did == null || iid == null) throw Exception('汽水音乐搜索初始化失败');
      return {'device_id': did, 'iid': iid, 'fp': did};
    } catch (_) {
      _device = null;
      rethrow;
    }
  }

  Future<Map> _searchData(String keyword, String type, int page) async {
    final key = '$type:$page:$keyword';
    final now = DateTime.now();
    final cached = _searchCache[key];
    if (cached != null && cached.expires.isAfter(now)) return cached.value;
    if (_searchCache.length >= 24) _searchCache.remove(_searchCache.keys.first);
    final result = _get(
      '/luna/search/$type',
      query: {
        'q': keyword,
        'cursor': '${((page < 1 ? 1 : page) - 1) * qsSearchPageSize}',
        'search_id': _uuid(),
        'search_method': 'track',
        'from_search_id': '',
        'search_scene': '',
      },
    );
    // The same upstream page is shared by the platform and aggregate searches.
    _searchCache[key] = (
      expires: now.add(const Duration(minutes: 1)),
      value: result,
    );
    try {
      return await result;
    } catch (_) {
      if (identical(_searchCache[key]?.value, result)) _searchCache.remove(key);
      rethrow;
    }
  }

  Future<({List<MusicInfo> list, bool hasMore})> searchTracks(
    String keyword, {
    int page = 1,
    int limit = qsSearchPageSize,
  }) async {
    final result = await _search(keyword, 'track', page);
    return (
      list: dedupeMusic([
        for (final item in result.items)
          if (QsSdk.parseTrack(_map(_map(item['entity'])['track']))
              case final MusicInfo music)
            music,
      ]).take(limit.clamp(1, qsSearchPageSize)).toList(growable: false),
      hasMore: result.hasMore,
    );
  }

  Future<List<String>> tip(String keyword) async {
    if (keyword.trim().isEmpty) return const [];
    final data = await _get(
      '/luna/pc/sug',
      query: {
        'q': keyword.trim(),
        'sug_scene': 'search_sug',
        'sug_search_id': '',
      },
    );
    if (data['sugs'] is! List) throw Exception('汽水音乐搜索建议加载失败');
    return {
      for (final item in _maps(data['sugs']))
        if (_text(item['suggestion']) case final String text) text,
    }.toList(growable: false);
  }

  Future<({List<Map> items, bool hasMore})> _search(
    String keyword,
    String type,
    int page,
  ) async {
    if (keyword.trim().isEmpty) return (items: const <Map>[], hasMore: false);
    final data = await _searchData(keyword.trim(), type, page);
    if (data['result_groups'] is! List) throw Exception('汽水音乐搜索加载失败');
    final group = _maps(
      data['result_groups'],
    ).where((item) => item['id'] == '${type}s').firstOrNull;
    if (group == null) return (items: const <Map>[], hasMore: false);
    final rows = group['data'] ?? group['items'];
    if (rows is! List) throw Exception('汽水音乐搜索返回了无效数据');
    return (
      items: rows.whereType<Map>().toList(),
      hasMore: group['has_more'] == true,
    );
  }

  Future<CatalogResult> search(
    String keyword,
    SearchCategory category,
    int page,
    int limit,
  ) async {
    final type = switch (category) {
      SearchCategory.artists => 'artist',
      SearchCategory.albums => 'album',
      SearchCategory.playlists => 'playlist',
      _ => throw ArgumentError.value(category),
    };
    final result = await _search(keyword, type, page);
    final items = <CatalogItem>[];
    final seen = <String>{};
    for (final row in result.items) {
      final info = _map(_map(row['entity'])[type]);
      final id = _text(info['id']);
      final name = _text(info['title'] ?? info['name']);
      if (id == null || name == null || !seen.add(id)) continue;
      final creator = category == SearchCategory.albums
          ? _artists(info['artists'])
          : _text(_map(info['owner'])['nickname']);
      final count = _int(info['count_tracks']);
      items.add(
        CatalogItem(
          category: category,
          summary: PlaylistSummary(
            id: id,
            name: name,
            source: MusicSource.qs,
            coverUrl: QsSdk.imageUrl(
              info[type == 'artist' ? 'url_avatar' : 'url_cover'],
            ),
            creator: creator,
            description: _text(info['desc']),
            trackCount: count,
          ),
          subtitle: [
            if (creator != null && creator.isNotEmpty) creator,
            if (count != null) '$count 首歌曲',
          ].join(' · '),
        ),
      );
    }
    return CatalogResult(
      items: items
          .take(limit.clamp(1, qsSearchPageSize))
          .toList(growable: false),
      total: items.length,
      hasMore: result.hasMore,
    );
  }

  Future<PlaylistInfo> detail(
    String id, {
    required bool artist,
    int? maxTracks,
  }) async {
    final limit = maxTracks == null || maxTracks <= 0
        ? 10000
        : maxTracks.clamp(1, 10000);
    final data = await _get('/luna/pc/${artist ? 'artists' : 'albums'}/$id');
    final info = data[artist ? 'artist_info' : 'album_info'];
    if (info is! Map) throw Exception('汽水音乐${artist ? '艺人' : '专辑'}详情加载失败');
    final tracks = <MusicInfo>[];
    var exhausted = false;
    if (artist) {
      var cursor = '0';
      final cursors = <String>{};
      final expected = _int(info['count_tracks']);
      final seen = <String>{};
      while (tracks.length < limit && cursors.add(cursor)) {
        final page = await _get(
          '/luna/pc/artists/$id/tracks',
          query: {
            'cursor': cursor,
            'count': '${(limit - tracks.length).clamp(1, 100)}',
          },
        );
        if (page['tracks'] is! List) throw Exception('汽水音乐艺人歌曲加载失败');
        final rows = _maps(page['tracks']).toList();
        for (final raw in rows) {
          final music = QsSdk.parseTrack(raw);
          if (music != null && seen.add(music.id)) tracks.add(music);
        }
        if (rows.isEmpty ||
            (expected != null && tracks.length >= expected) ||
            page['has_more'] == false) {
          exhausted = true;
          break;
        }
        if (tracks.length >= limit) break;
        final next = _text(page['next_cursor']);
        if (next == null || cursors.contains(next)) {
          throw Exception('汽水音乐艺人歌曲分页异常，请稍后重试');
        }
        cursor = next;
      }
    } else {
      if (data['tracks'] is! List) throw Exception('汽水音乐专辑歌曲加载失败');
      tracks.addAll(
        dedupeMusic([
          for (final raw in _maps(data['tracks']))
            if (QsSdk.parseTrack(raw) case final MusicInfo music) music,
        ]),
      );
      exhausted = true;
    }
    return PlaylistInfo(
      id: id,
      name: _text(info['name']) ?? '汽水音乐',
      source: MusicSource.qs,
      tracks: tracks.take(limit).toList(growable: false),
      trackCount: exhausted ? tracks.length : _int(info['count_tracks']),
      coverUrl: QsSdk.imageUrl(info[artist ? 'url_avatar' : 'url_cover']),
      creator: artist ? '热门歌曲' : _artists(info['artists']),
      description: _text(
        artist ? _map(info['artist_profile'])['description'] : info['desc'],
      ),
    );
  }

  static Map _map(Object? value) => value is Map ? value : const {};
  static String _uuid() {
    final random = Random.secure();
    final bytes = List.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final hex = bytes.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  static Iterable<Map> _maps(Object? value) =>
      value is List ? value.whereType<Map>() : const <Map>[];
  static String? _text(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  static int? _int(Object? value) =>
      value is num ? value.toInt() : int.tryParse('$value');
  static String _artists(Object? value) => _maps(
    value,
  ).map((artist) => _text(artist['name'])).whereType<String>().join('、');
}
