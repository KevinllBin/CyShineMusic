import '../../models/catalog_result.dart';
import '../../models/enums.dart';
import '../../models/music_info.dart';
import '../../models/playlist_info.dart';
import '../../models/playlist_summary.dart';
import '../../models/search_category.dart';
import '../internal/sdk_http.dart';
import '../playlist_adapters/kw_playlist_adapter.dart';
import 'catalog_helpers.dart';

class KwCatalog {
  // mobi=1 asks Kuwo for JSON instead of its legacy single-quoted JS object.
  static const base =
      'https://search.kuwo.cn/r.s?encoding=utf8&rformat=json&mobi=1';

  static Future<CatalogResult> search(
    String keyword,
    SearchCategory category,
    int page,
    int limit, {
    SdkJsonLoader? loader,
  }) async {
    final type = switch (category) {
      SearchCategory.artists => 'artist',
      SearchCategory.albums => 'album',
      SearchCategory.playlists => 'playlist',
      _ => throw ArgumentError.value(category),
    };
    final body = await catalogJson(
      '$base&client=kt&all=${Uri.encodeComponent(keyword)}&ft=$type&pn=${page - 1}&rn=$limit',
      loader: loader,
    );
    final raw =
        body[category == SearchCategory.albums ? 'albumlist' : 'abslist'];
    if (raw is! List) throw Exception('酷我搜索暂时不可用');
    final items = catalogMaps(raw)
        .map((i) {
          final isArtist = category == SearchCategory.artists;
          final id =
              i[isArtist
                  ? 'ARTISTID'
                  : category == SearchCategory.albums
                  ? 'albumid'
                  : 'playlistid'];
          final count = catalogInt(
            i[isArtist
                ? 'SONGNUM'
                : category == SearchCategory.albums
                ? 'musiccnt'
                : 'songnum'],
          );
          final creator = catalogText(i['artist'] ?? i['nickname']);
          return CatalogItem(
            category: category,
            summary: PlaylistSummary(
              id: id?.toString() ?? '',
              name: catalogText(i[isArtist ? 'ARTIST' : 'name']),
              source: MusicSource.kw,
              coverUrl: isArtist
                  ? catalogImage(
                      '${body['BASEPICPATH'] ?? 'https://img1.kuwo.cn/star/starheads/'}${i['PICPATH'] ?? ''}',
                    )
                  : catalogImage(
                      i['hts_img'] ?? i['hts_pic'] ?? i['img'] ?? i['pic'],
                    ),
              creator: creator,
              description: catalogText(i['desc'] ?? i['info'] ?? i['intro']),
              trackCount: count,
              playCount: category == SearchCategory.playlists
                  ? catalogInt(i['playcnt'])
                  : null,
            ),
            subtitle: isArtist
                ? '$count 首歌曲 · ${catalogInt(i['ALBUMNUM'])} 张专辑'
                : [
                    creator,
                    category == SearchCategory.albums
                        ? catalogText(i['pub'])
                        : '$count 首',
                  ].where((s) => s.isNotEmpty).join(' · '),
          );
        })
        .where((i) => i.summary.id.isNotEmpty)
        .toList();
    final total = catalogInt(body['TOTAL'] ?? body['total']);
    return CatalogResult(
      items: items,
      total: total,
      hasMore: items.isNotEmpty && page * limit < total,
    );
  }

  static Future<PlaylistInfo> detail(
    String id, {
    required bool artist,
    int? maxTracks,
    SdkJsonLoader? loader,
  }) async {
    final songs = <MusicInfo>[];
    Map info = const {};
    final target = maxTracks ?? 10000;
    var total = 0;
    for (var page = 0; songs.length < target; page++) {
      final body = await catalogJson(
        '$base&stype=${artist ? 'artist2music' : 'albuminfo'}&${artist ? 'artistid' : 'albumid'}=${Uri.encodeComponent(id)}&pn=$page&rn=${target < 100 ? target : 100}',
        loader: loader,
      );
      if (body['musiclist'] is! List) throw Exception('酷我详情暂时不可用');
      if (page == 0) info = body;
      final raw = catalogMaps(body['musiclist']);
      total = catalogInt(body['total'] ?? body['songnum']);
      final batch = raw
          .map(
            (i) => KwPlaylistAdapter.parseTrack({
              ...i,
              'id': i['id'] ?? i['musicrid'],
            }),
          )
          .whereType<MusicInfo>()
          .toList();
      final previousCount = songs.length;
      final seen = songs.map((s) => s.id).toSet();
      songs.addAll(batch.where((s) => seen.add(s.id)));
      if (!artist ||
          batch.isEmpty ||
          songs.length >= total ||
          songs.length == previousCount) {
        break;
      }
    }
    return PlaylistInfo(
      id: id,
      name: catalogText(info[artist ? 'artist' : 'name']),
      source: MusicSource.kw,
      coverUrl: catalogImage(info['hts_img'] ?? info['img']),
      creator: artist ? '热门歌曲' : catalogText(info['artist']),
      description: catalogText(info['info']),
      trackCount: total > 0 ? total : songs.length,
      tracks: songs.take(target).toList(),
    );
  }
}
