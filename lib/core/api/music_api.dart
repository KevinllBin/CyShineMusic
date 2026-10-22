import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/enums.dart';
import '../models/leaderboard_info.dart';
import '../models/lyric_info.dart';
import '../models/music_info.dart';
import '../models/playlist_info.dart';
import '../models/playlist_summary.dart';
import '../models/search_response.dart';
import '../models/catalog_result.dart';
import '../models/search_category.dart';
import '../models/online_collection_kind.dart';
import '../sdk/catalog_sdk.dart';
import '../sdk/leaderboard_sdk.dart';
import '../sdk/music_sdk.dart' as sdk;
import '../sdk/playlist_catalog_sdk.dart';
import '../sdk/playlist_sdk.dart';
import '../storage/settings_store.dart';

class MusicApi {
  MusicApi({
    Iterable<MusicSource> enabledSearchSources = kDefaultEnabledSearchSources,
    Iterable<MusicSource> searchSourceOrder = kDefaultDiscoverySourceOrder,
  }) : _enabledSearchSources = Set<MusicSource>.unmodifiable(
         enabledSearchSources,
       ),
       _searchSourceOrder = List<MusicSource>.unmodifiable(searchSourceOrder);

  final Set<MusicSource> _enabledSearchSources;
  final List<MusicSource> _searchSourceOrder;

  // Local: hits each music platform directly. There is no CancelToken here —
  // the aggregator and 5 platform SDKs don't thread it through to SdkHttp, so
  // accepting one at this layer would be misleading. Callers that need
  // "discard stale response" semantics should track requests by identity.
  Future<SearchResponse> searchMusic({
    required String keyword,
    required MusicSource source,
    int page = 1,
    int limit = 30,
  }) async {
    final result = await sdk.MusicSdkAggregator.search(
      keyword: keyword,
      source: source,
      enabledSources: _enabledSearchSources,
      sourceOrder: _searchSourceOrder,
      page: page,
      limit: limit,
    );
    return SearchResponse(
      list: result.list,
      page: result.page,
      limit: result.limit,
      allPage: result.allPage,
      total: result.total,
      source: result.source,
    );
  }

  // Local: parallel tip from each platform with round-robin merge.
  Future<List<String>> searchTip({
    required String keyword,
    required MusicSource source,
    int limit = 8,
  }) {
    return sdk.MusicSdkAggregator.tip(
      keyword: keyword,
      source: source,
      enabledSources: _enabledSearchSources,
      sourceOrder: _searchSourceOrder,
      limit: limit,
    );
  }

  Future<SearchResponse> searchContent({
    required String keyword,
    required MusicSource source,
    required SearchCategory category,
    int page = 1,
    int limit = 30,
  }) async {
    if (category == SearchCategory.songs) {
      return searchMusic(
        keyword: keyword,
        source: source,
        page: page,
        limit: limit,
      );
    }
    final categories = category == SearchCategory.all
        ? [
            SearchCategory.artists,
            SearchCategory.songs,
            SearchCategory.playlists,
            SearchCategory.albums,
          ]
        : [category];
    final sources = source == MusicSource.all
        ? {
            ..._searchSourceOrder,
            ..._enabledSearchSources,
          }.where(_enabledSearchSources.contains).toList()
        : _enabledSearchSources.contains(source)
        ? [source]
        : <MusicSource>[];
    final notices = <String>[];
    if (category == SearchCategory.all &&
        !sources.any((s) => CatalogSdk.supports(s, SearchCategory.artists))) {
      notices.add('当前平台仅支持歌曲搜索，可切换平台查找艺人、歌单和专辑');
    }
    final catalog = <SearchCategory, List<CatalogItem>>{};
    SearchResponse? songs;
    var total = 0;
    var hasMore = false;
    final pageSize = category == SearchCategory.all ? 6 : limit;
    await Future.wait(
      categories.map((type) async {
        if (type == SearchCategory.songs) {
          try {
            songs = await searchMusic(
              keyword: keyword,
              source: source,
              page: page,
              limit: pageSize,
            );
          } catch (_) {
            notices.add('歌曲暂时加载失败，请在歌曲分类中重试');
          }
          return;
        }
        final targets = sources
            .where((s) => CatalogSdk.supports(s, type))
            .toList();
        if (targets.isEmpty) {
          if (category == SearchCategory.all) return;
          notices.add(
            '${source == MusicSource.all ? '已启用的平台' : source.label}暂不支持${type.label}搜索',
          );
          return;
        }
        final results = await Future.wait(
          targets.map((s) async {
            try {
              return await CatalogSdk.search(
                keyword,
                s,
                type,
                page,
                pageSize,
              ).timeout(const Duration(seconds: 25));
            } catch (_) {
              notices.add('${s.label}${type.label}加载失败，可切换平台或重试');
              return null;
            }
          }),
        );
        // Interleave sources so that the overview isn't occupied by one platform.
        final merged = <CatalogItem>[];
        final seen = <String>{};
        for (var index = 0; index < pageSize; index++) {
          for (final result in results.whereType<CatalogResult>()) {
            if (index < result.items.length &&
                seen.add(result.items[index].key)) {
              merged.add(result.items[index]);
            }
          }
        }
        catalog[type] = merged;
        for (final result in results.whereType<CatalogResult>()) {
          total += result.total;
          hasMore = hasMore || result.hasMore;
        }
      }),
    );
    return SearchResponse(
      list: songs?.list ?? const [],
      catalog: catalog,
      notices: notices,
      page: page,
      limit: pageSize,
      allPage: hasMore && category != SearchCategory.all ? page + 1 : page,
      total: total,
      source: source,
    );
  }

  Future<PlaylistInfo> getCollection({
    required MusicSource source,
    required String id,
    required OnlineCollectionKind kind,
    int? maxTracks,
  }) => switch (kind) {
    OnlineCollectionKind.playlist => parsePlaylist(
      input: id,
      source: source,
      maxTracks: maxTracks,
    ),
    OnlineCollectionKind.leaderboard => getLeaderboard(
      source: source,
      boardId: id,
      maxTracks: maxTracks,
    ),
    OnlineCollectionKind.artist ||
    OnlineCollectionKind.album => CatalogSdk.detail(
      source,
      id,
      artist: kind == OnlineCollectionKind.artist,
      maxTracks: maxTracks,
    ),
  };

  // Local: parses public playlists from all five platforms on-device.
  // Playback and download URL resolution are handled by MusicUrlResolver.
  Future<PlaylistInfo> parsePlaylist({
    required String input,
    MusicSource source = MusicSource.all,
    int? maxTracks,
  }) async {
    // Saved artist/album collections retain a typed origin, so refresh never
    // treats an album ID as a playlist ID from the same platform.
    if (input.startsWith('artist:') || input.startsWith('album:')) {
      final result = await CatalogSdk.detail(
        source,
        input.substring(input.indexOf(':') + 1),
        artist: input.startsWith('artist:'),
        maxTracks: maxTracks,
      );
      return PlaylistInfo(
        id: input,
        name: result.name,
        source: result.source,
        tracks: result.tracks,
        coverUrl: result.coverUrl,
        creator: result.creator,
        description: result.description,
        trackCount: result.trackCount,
      );
    }
    return PlaylistSdk.parse(
      input: input,
      source: source,
      maxTracks: maxTracks,
    );
  }

  Future<List<PlaylistSummary>> featuredPlaylists({
    required MusicSource source,
    int page = 1,
    int limit = 20,
    String? categoryId,
  }) {
    return PlaylistCatalogSdk.featured(
      source,
      page: page,
      limit: limit,
      categoryId: categoryId,
    );
  }

  Future<List<LeaderboardSummary>> getLeaderboards(MusicSource source) async {
    return LeaderboardSdk.boards(source);
  }

  Future<LeaderboardSummary> getLeaderboardPreview(
    LeaderboardSummary board, {
    int limit = 3,
  }) {
    return LeaderboardSdk.preview(board, limit: limit);
  }

  Future<PlaylistInfo> getLeaderboard({
    required MusicSource source,
    required String boardId,
    int? maxTracks,
  }) {
    return LeaderboardSdk.get(
      source: source,
      boardId: boardId,
      maxTracks: maxTracks,
    );
  }

  // Local: direct call to the platform lyric API for each source.
  Future<LyricInfo> getLyric({required MusicInfo musicInfo}) {
    return sdk.MusicSdkAggregator.getLyric(musicInfo);
  }

  // Local: returns the picUrl already on the MusicInfo (faster path), or
  // hits the source-specific cover endpoint.
  Future<String?> getPicUrl({
    required MusicInfo musicInfo,
    bool preferCached = true,
  }) {
    return sdk.MusicSdkAggregator.getPicUrl(
      musicInfo,
      preferCached: preferCached,
    );
  }
}

final musicApiProvider = Provider<MusicApi>((ref) {
  final enabledSearchSources = ref.watch(
    settingsProvider.select((settings) => settings.enabledSearchSources),
  );
  final searchSourceOrder = ref.watch(
    settingsProvider.select((settings) => settings.discoverySourceOrder),
  );
  return MusicApi(
    enabledSearchSources: enabledSearchSources,
    searchSourceOrder: searchSourceOrder,
  );
});

String describeDioError(Object error) {
  if (error is DioException) {
    final response = error.response?.data;
    if (response is Map && response['message'] is String) {
      return response['message'] as String;
    }
    if (error.type == DioExceptionType.connectionTimeout) return '连接超时';
    if (error.type == DioExceptionType.receiveTimeout) return '接收超时';
    if (error.type == DioExceptionType.sendTimeout) return '发送超时';
    if (error.type == DioExceptionType.connectionError) return '无法连接到服务器';
    if (error.type == DioExceptionType.cancel) return '请求已取消';
    if (error.message != null && error.message!.isNotEmpty) {
      return error.message!;
    }
    return '请求失败';
  }
  return error.toString();
}
