import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/music_api.dart';
import '../../core/models/enums.dart';
import '../../core/models/leaderboard_info.dart';
import '../../core/models/music_info.dart';
import '../../core/models/online_collection_kind.dart';
import '../../core/models/playlist_category.dart';
import '../../core/models/playlist_info.dart';
import '../../core/models/playlist_summary.dart';
import '../../core/ui/cover_image_source.dart';

const int discoveryPlaylistArtworkSize = 640;
const int discoveryPlaylistPageSize = 30;
const int onlinePlaylistDetailInitialTrackLimit = 40;
const int onlinePlaylistDetailTrackPageSize = 40;
const List<MusicSource> kDiscoverySources = <MusicSource>[
  MusicSource.kw,
  MusicSource.kg,
  MusicSource.tx,
  MusicSource.wy,
  MusicSource.mg,
];

typedef OnlinePlaylistIdentity = ({
  MusicSource source,
  String id,
  OnlineCollectionKind kind,
});

typedef LeaderboardIdentity = ({MusicSource source, String boardId});

final onlinePlaylistSummaryCacheProvider =
    Provider<Map<OnlinePlaylistIdentity, PlaylistSummary>>((ref) => {});

String onlinePlaylistArtworkHeroTag(
  MusicSource source,
  String playlistId, {
  OnlineCollectionKind kind = OnlineCollectionKind.playlist,
}) {
  return 'online-${kind.name}-artwork:${source.code}:$playlistId';
}

final selectedDiscoverySourceProvider = StateProvider<MusicSource>(
  (ref) => MusicSource.kw,
);

final selectedDiscoveryCategoryProvider =
    StateProvider.family<String, MusicSource>(
      (ref, source) => defaultPlaylistCatalogCategoryFor(source).id,
    );

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
      return switch (key.kind) {
        OnlineCollectionKind.playlist => api.parsePlaylist(
          input: key.id,
          source: key.source,
          maxTracks: key.maxTracks,
        ),
        OnlineCollectionKind.leaderboard => api.getLeaderboard(
          source: key.source,
          boardId: key.id,
          maxTracks: key.maxTracks,
        ),
      };
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
