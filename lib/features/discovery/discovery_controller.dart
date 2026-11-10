import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/music_api.dart';
import '../../core/models/enums.dart';
import '../../core/models/leaderboard_info.dart';
import '../../core/models/music_info.dart';
import '../../core/models/online_collection_kind.dart';
import '../../core/models/playlist_category.dart';
import '../../core/models/playlist_info.dart';
import '../../core/models/playlist_summary.dart';
import '../../core/storage/settings_store.dart';
import '../../core/ui/cover_image_source.dart';
import 'discovery_browse_cache.dart';

const int discoveryPlaylistArtworkSize = 640;
const int discoveryPlaylistPageSize = 30;
const int onlinePlaylistDetailInitialTrackLimit = 40;
const int onlinePlaylistDetailTrackPageSize = 40;
final discoveryBrowseCacheProvider = Provider<DiscoveryBrowseCache>(
  (ref) => DiscoveryBrowseCache(),
);

final discoverySourcesProvider = Provider<List<MusicSource>>(
  (ref) => ref.watch(settingsProvider.select((s) => s.discoverySourceOrder)),
);

typedef OnlinePlaylistIdentity = ({
  MusicSource source,
  String id,
  OnlineCollectionKind kind,
});

typedef LeaderboardIdentity = ({MusicSource source, String boardId});

final onlinePlaylistSummaryCacheProvider =
    Provider<Map<OnlinePlaylistIdentity, PlaylistSummary>>((ref) => {});

// Keep the loaded range alongside the shell's saved scroll position.
final onlinePlaylistTrackLimitCacheProvider =
    Provider<Map<OnlinePlaylistIdentity, int>>((ref) => {});

String onlinePlaylistArtworkHeroTag(
  MusicSource source,
  String playlistId, {
  OnlineCollectionKind kind = OnlineCollectionKind.playlist,
}) {
  return 'online-${kind.name}-artwork:${source.code}:$playlistId';
}

final selectedDiscoverySourceProvider = StateProvider<MusicSource>((ref) {
  const storageKey = 'selected_discovery_source_v1';
  final sources = ref.watch(discoverySourcesProvider);
  final prefs = ref.read(sharedPreferencesProvider);
  final saved = MusicSource.tryFromCode(prefs.getString(storageKey) ?? '');
  // Preserve the existing StateController API while persisting every selection,
  // including programmatic changes, in Riverpod 2.x.
  // ignore: deprecated_member_use
  ref.listenSelf((previous, next) {
    if (sources.contains(next) && prefs.getString(storageKey) != next.code) {
      unawaited(prefs.setString(storageKey, next.code));
    }
  });
  return sources.contains(saved) ? saved! : sources.first;
});

final selectedDiscoveryCategoryProvider =
    NotifierProvider.family<
      SelectedDiscoveryCategoryNotifier,
      String,
      MusicSource
    >(SelectedDiscoveryCategoryNotifier.new);

class SelectedDiscoveryCategoryNotifier
    extends FamilyNotifier<String, MusicSource> {
  late final _prefs = ref.read(sharedPreferencesProvider);

  String get _storageKey => 'discovery_category_${arg.code}_v1';

  @override
  String build(MusicSource source) {
    final savedId = _prefs.getString(_storageKey);
    return playlistCatalogCategoriesFor(
          source,
        ).any((category) => category.id == savedId)
        ? savedId!
        : defaultPlaylistCatalogCategoryFor(source).id;
  }

  Future<void> select(String categoryId) async {
    if (state == categoryId ||
        !playlistCatalogCategoriesFor(
          arg,
        ).any((category) => category.id == categoryId)) {
      return;
    }
    state = categoryId;
    await _prefs.setString(_storageKey, categoryId);
  }
}

final featuredPlaylistsProvider =
    FutureProvider.family<List<PlaylistSummary>, MusicSource>((ref, source) {
      final categoryId = ref.watch(selectedDiscoveryCategoryProvider(source));
      return ref
          .watch(musicApiProvider)
          .featuredPlaylists(
            source: source,
            page: 1,
            limit: discoveryPlaylistPageSize,
            categoryId: categoryId,
          );
    });

final leaderboardBoardsProvider =
    FutureProvider.family<List<LeaderboardSummary>, MusicSource>((ref, source) {
      return ref.watch(musicApiProvider).getLeaderboards(source);
    });

final leaderboardPreviewProvider =
    FutureProvider.family<LeaderboardSummary, LeaderboardIdentity>((
      ref,
      key,
    ) async {
      final boards = await ref.watch(
        leaderboardBoardsProvider(key.source).future,
      );
      final board = boards.firstWhere(
        (item) => item.boardId == key.boardId,
        orElse: () => throw StateError('排行榜不存在'),
      );
      return ref.watch(musicApiProvider).getLeaderboardPreview(board);
    });

class OnlinePlaylistKey {
  const OnlinePlaylistKey({
    required this.source,
    required this.id,
    this.kind = OnlineCollectionKind.playlist,
    this.maxTracks = onlinePlaylistDetailInitialTrackLimit,
  });

  final MusicSource source;
  final String id;
  final OnlineCollectionKind kind;
  final int? maxTracks;

  @override
  bool operator ==(Object other) =>
      other is OnlinePlaylistKey &&
      other.source == source &&
      other.id == id &&
      other.kind == kind &&
      other.maxTracks == maxTracks;

  @override
  int get hashCode => Object.hash(source, id, kind, maxTracks);
}

final onlinePlaylistDetailProvider =
    FutureProvider.family<PlaylistInfo, OnlinePlaylistKey>((ref, key) {
      final api = ref.watch(musicApiProvider);
      return api.getCollection(
        source: key.source,
        id: key.id,
        kind: key.kind,
        maxTracks: key.maxTracks,
      );
    });

class OnlineTrackCoverKey {
  const OnlineTrackCoverKey(this.music);

  final MusicInfo music;

  @override
  bool operator ==(Object other) =>
      other is OnlineTrackCoverKey &&
      other.music.source == music.source &&
      other.music.id == music.id;

  @override
  int get hashCode => Object.hash(music.source, music.id);
}

final onlineTrackCoverProvider =
    FutureProvider.family<String?, OnlineTrackCoverKey>((ref, key) {
      return ref
          .watch(musicApiProvider)
          .getPicUrl(musicInfo: key.music, preferCached: false);
    });

final leaderboardArtworkProvider =
    Provider.family<String?, LeaderboardIdentity>((ref, key) {
      final board = ref.watch(leaderboardPreviewProvider(key)).asData?.value;
      if (board == null) return null;
      if (CoverImageSource.isUsableUrl(board.coverUrl)) return board.coverUrl;
      final firstTrack = board.previewTracks.firstOrNull;
      if (firstTrack == null) return null;
      if (CoverImageSource.isUsableUrl(firstTrack.meta.picUrl)) {
        return firstTrack.meta.picUrl;
      }
      final cover = ref
          .watch(onlineTrackCoverProvider(OnlineTrackCoverKey(firstTrack)))
          .asData
          ?.value;
      return CoverImageSource.isUsableUrl(cover) ? cover : null;
    });
