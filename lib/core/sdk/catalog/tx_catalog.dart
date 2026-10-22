import 'dart:convert';

import '../../models/catalog_result.dart';
import '../../models/enums.dart';
import '../../models/music_info.dart';
import '../../models/playlist_info.dart';
import '../../models/playlist_summary.dart';
import '../../models/search_category.dart';
import '../internal/sdk_http.dart';
import '../playlist_sdk.dart';
import '../tx_sdk.dart';
import 'catalog_helpers.dart';

class TxCatalog {
  static const headers = {'Referer': 'https://y.qq.com/'};

  static Future<CatalogResult> search(
    String keyword,
    SearchCategory category,
    int page,
    int limit, {
    SdkJsonLoader? loader,
  }) async {
    if (category == SearchCategory.playlists) {
      final data = await TxSdk.searchCatalog(keyword, 3, page, limit);
      final body = catalogMap(data['body'] ?? data);
      final raw = body['item_songlist'] ?? catalogMap(body['songlist'])['list'];
      if (raw is! List) throw Exception('QQ 歌单搜索暂时不可用');
      final items = catalogMaps(raw)
          .map((i) {
            final creator = catalogText(
              catalogMap(i['creator'])['name'] ?? i['nickname'],
            );
            return CatalogItem(
              category: category,
              summary: PlaylistSummary(
                id: '${i['dissid'] ?? i['diss_id'] ?? i['tid'] ?? ''}',
                name: catalogText(
                  i['dissname'] ?? i['diss_name'] ?? i['title'],
                ),
                source: MusicSource.tx,
                coverUrl: catalogImage(i['imgurl'] ?? i['logo'] ?? i['pic']),
                creator: creator,
                trackCount: catalogInt(i['song_count'] ?? i['songnum']),
                playCount: catalogInt(i['listennum'] ?? i['listen_num']),
              ),
              subtitle: creator,
            );
          })
          .where((i) => i.summary.id.isNotEmpty)
          .toList();
      final total = catalogInt(catalogMap(data['meta'])['sum']);
      return CatalogResult(
        items: items,
        total: total,
        hasMore: items.isNotEmpty && page * limit < total,
      );
    }
    final artist = category == SearchCategory.artists;
    final body = await catalogJson(
      'https://c.y.qq.com/soso/fcgi-bin/client_search_cp?p=$page&n=$limit&w=${Uri.encodeComponent(keyword)}&format=json&t=${artist ? 9 : 8}',
      loader: loader,
      headers: headers,
    );
    if (body['code'] != 0) throw Exception('QQ 搜索暂时不可用');
    final data = catalogMap(
      catalogMap(body['data'])[artist ? 'singer' : 'album'],
    );
    if (data['list'] is! List) throw Exception('QQ 搜索暂时不可用');
    final items = catalogMaps(data['list'])
        .map((i) {
          final id = (i[artist ? 'singerMID' : 'albumMID'] ?? '').toString();
          final creator = catalogText(i['singerName']);
          final count = catalogInt(i[artist ? 'songNum' : 'song_count']);
          return CatalogItem(
            category: category,
            summary: PlaylistSummary(
              id: id,
              name: catalogText(i[artist ? 'singerName' : 'albumName']),
              source: MusicSource.tx,
              coverUrl: catalogImage(i[artist ? 'singerPic' : 'albumPic']),
              creator: artist ? null : creator,
              trackCount: count,
            ),
            subtitle: artist
                ? '$count 首歌曲 · ${catalogInt(i['albumNum'])} 张专辑'
                : [
                    creator,
                    catalogText(i['publicTime']),
                  ].where((s) => s.isNotEmpty).join(' · '),
          );
        })
        .where((i) => i.summary.id.isNotEmpty)
        .toList();
    final total = catalogInt(data['totalnum']);
    return CatalogResult(
      items: items,
      total: total,
      hasMore: items.isNotEmpty && page * limit < total,
    );
  }

  static Future<Map> _musicu(
    String module,
    String method,
    Map param,
    SdkJsonLoader? loader,
  ) async {
    final data = jsonEncode({
      'comm': {'ct': 24, 'cv': 0},
      'req': {'module': module, 'method': method, 'param': param},
    });
    final body = await catalogJson(
      'https://u.y.qq.com/cgi-bin/musicu.fcg?data=${Uri.encodeComponent(data)}',
      loader: loader,
      headers: headers,
    );
    final req = catalogMap(body['req']);
    if (body['code'] != 0 || req['code'] != 0) throw Exception('QQ 详情暂时不可用');
    return catalogMap(req['data']);
  }

  static Future<PlaylistInfo> detail(
    String id, {
    required bool artist,
    int? maxTracks,
    SdkJsonLoader? loader,
  }) async {
    if (!artist) {
      final body = await catalogJson(
        'https://c.y.qq.com/v8/fcg-bin/fcg_v8_album_info_cp.fcg?albummid=${Uri.encodeComponent(id)}&format=json',
        loader: loader,
        headers: headers,
      );
      if (body['code'] != 0) throw Exception('QQ 专辑暂时不可用');
      final data = catalogMap(body['data']);
      final tracks = catalogMaps(
        data['list'],
      ).map(PlaylistSdk.parseTxSong).whereType<MusicInfo>().toList();
      return PlaylistInfo(
        id: id,
        name: catalogText(data['name']),
        source: MusicSource.tx,
        coverUrl: 'https://y.gtimg.cn/music/photo_new/T002R500x500M000$id.jpg',
        creator: catalogText(data['singername']),
        description: catalogText(data['desc']),
        trackCount: tracks.length,
        tracks: tracks.take(maxTracks ?? tracks.length).toList(),
      );
    }
    final info = await _musicu(
      'music.musichallSinger.SingerInfoInter',
      'GetSingerDetail',
      {
        'singer_mids': [id],
        'ex_singer': 1,
      },
      loader,
    );
    final singer = catalogMaps(info['singer_list']).firstOrNull ?? const {};
    final songs = <MusicInfo>[];
    final target = maxTracks ?? 10000;
    var total = 0;
    for (var offset = 0; songs.length < target; offset += 100) {
      final data =
          await _musicu('musichall.song_list_server', 'GetSingerSongList', {
            'singerMid': id,
            'begin': offset,
            'num': target - songs.length < 100 ? target - songs.length : 100,
            'order': 1,
          }, loader);
      total = catalogInt(data['totalNum']);
      final batch = catalogMaps(data['songList'])
          .map((i) => PlaylistSdk.parseTxSong(catalogMap(i['songInfo'])))
          .whereType<MusicInfo>()
          .toList();
      final before = songs.length;
      final seen = songs.map((s) => s.id).toSet();
      songs.addAll(batch.where((s) => seen.add(s.id)));
      if (songs.length >= total || songs.length == before || batch.isEmpty) {
        break;
      }
    }
    return PlaylistInfo(
      id: id,
      name: catalogText(catalogMap(singer['basic_info'])['name']),
      source: MusicSource.tx,
      coverUrl: 'https://y.gtimg.cn/music/photo_new/T001R500x500M000$id.jpg',
      creator: '热门歌曲',
      description: catalogText(catalogMap(singer['ex_info'])['desc']),
      trackCount: total,
      tracks: songs.take(target).toList(),
    );
  }
}
