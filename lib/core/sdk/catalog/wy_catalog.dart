import '../../models/catalog_result.dart';
import '../../models/enums.dart';
import '../../models/playlist_info.dart';
import '../../models/playlist_summary.dart';
import '../../models/search_category.dart';
import '../../models/music_info.dart';
import '../internal/sdk_http.dart';
import '../playlist_sdk.dart';
import 'catalog_helpers.dart';

class WyCatalog {
  static const headers = {'Referer': 'https://music.163.com/'};

  static Future<CatalogResult> search(
    String keyword,
    SearchCategory category,
    int page,
    int limit, {
    SdkJsonLoader? loader,
  }) async {
    final (type, field, count) = switch (category) {
      SearchCategory.artists => (100, 'artists', 'artistCount'),
      SearchCategory.albums => (10, 'albums', 'albumCount'),
      SearchCategory.playlists => (1000, 'playlists', 'playlistCount'),
      _ => throw ArgumentError.value(category),
    };
    final body = await catalogJson(
      'https://music.163.com/api/search/get/web?s=${Uri.encodeComponent(keyword)}&type=$type&offset=${(page - 1) * limit}&limit=$limit',
      loader: loader,
      headers: headers,
    );
    if (body['code'] != 200) throw Exception('网易云搜索暂时不可用');
    final result = catalogMap(body['result']);
    final items = catalogMaps(result[field]).where((i) => i['id'] != null).map((
      i,
    ) {
      final artist = catalogMap(i['artist']);
      final creator = catalogText(catalogMap(i['creator'])['nickname']);
      final songs = catalogInt(i['musicSize'] ?? i['trackCount'] ?? i['size']);
      final name = catalogText(i['name']);
      return CatalogItem(
        category: category,
        summary: PlaylistSummary(
          id: '${i['id']}',
          name: name,
          source: MusicSource.wy,
          coverUrl: catalogImage(i['picUrl'] ?? i['coverImgUrl']),
          creator: category == SearchCategory.albums
              ? catalogText(artist['name'])
              : creator,
          description: catalogText(i['description']),
          trackCount: songs,
          playCount: category == SearchCategory.playlists
              ? catalogInt(i['playCount'])
              : null,
        ),
        subtitle: switch (category) {
          SearchCategory.artists =>
            '$songs 首歌曲 · ${catalogInt(i['albumSize'])} 张专辑',
          SearchCategory.albums => [
            catalogText(artist['name']),
            catalogDate(i['publishTime']),
          ].where((s) => s.isNotEmpty).join(' · '),
          _ => [creator, '$songs 首'].where((s) => s.isNotEmpty).join(' · '),
        },
      );
    }).toList();
    final total = catalogInt(result[count]);
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
    final body = await catalogJson(
      'https://music.163.com/api/${artist ? 'artist' : 'album'}/${Uri.encodeComponent(id)}',
      loader: loader,
      headers: headers,
    );
    if (body['code'] != 200) {
      throw Exception(
        body['code'] == -462 || body['code'] == -460
            ? '网易云暂时限制了此内容的访问，请稍后重试或切换音乐平台'
            : '网易云详情暂时不可用',
      );
    }
    final info = catalogMap(body[artist ? 'artist' : 'album']);
    // The public artist endpoint supplies the curated hot-song list, not every
    // released song. Report that range honestly instead of advertising musicSize.
    final raw = catalogMaps(
      artist ? body['hotSongs'] : (body['songs'] ?? info['songs']),
    );
    final tracks = raw
        .map(PlaylistSdk.parseWySong)
        .whereType<MusicInfo>()
        .toList();
    return PlaylistInfo(
      id: id,
      name: catalogText(info['name']),
      source: MusicSource.wy,
      coverUrl: catalogImage(info['picUrl']),
      creator: artist
          ? '热门歌曲'
          : catalogText(catalogMap(info['artist'])['name']),
      description: catalogText(info[artist ? 'briefDesc' : 'description']),
      trackCount: tracks.length,
      tracks: tracks.take(maxTracks ?? tracks.length).toList(),
    );
  }
}
