import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/enums.dart';
import '../../core/models/music_info.dart';
import '../../core/models/playlist_info.dart';
import '../../core/models/playlist_summary.dart';
import '../../core/ui/app_toast.dart';
import '../../core/ui/cover_placeholder.dart';
import '../downloads/download_history_store.dart';
import '../downloads/download_progress.dart';
import '../music_sources/music_source_action_guard.dart';
import '../player/player_controller.dart';
import '../playlists/playlist_models.dart';
import '../playlists/playlist_store.dart';
import '../playlists/widgets/immersive_playlist_chrome.dart';
import '../playlists/widgets/playlist_detail_actions.dart';
import '../playlists/widgets/playlist_wide_layout.dart';
import '../search/widgets/quality_picker_sheet.dart';
import '../search/widgets/search_result_tile.dart';
import 'discovery_controller.dart';

class OnlinePlaylistDetailPage extends ConsumerStatefulWidget {
  const OnlinePlaylistDetailPage({
    super.key,
    required this.source,
    required this.playlistId,
    this.summary,
  });

  final MusicSource source;
  final String playlistId;
  final PlaylistSummary? summary;

  @override
  ConsumerState<OnlinePlaylistDetailPage> createState() =>
      _OnlinePlaylistDetailPageState();
}

class _OnlinePlaylistDetailPageState
    extends ConsumerState<OnlinePlaylistDetailPage> {
  bool _saving = false;
  bool _removingFavorite = false;

  OnlinePlaylistKey get _key =>
      OnlinePlaylistKey(source: widget.source, id: widget.playlistId);

  String get _returnLocation =>
      '/discover/playlists/${widget.source.code}/${widget.playlistId}';

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(onlinePlaylistDetailProvider(_key));
    return detail.when(
      loading: () => _DetailLoading(
        summary: widget.summary,
        source: widget.source,
        playlistId: widget.playlistId,
      ),
      error: (error, _) => _DetailError(
        summary: widget.summary,
        source: widget.source,
        playlistId: widget.playlistId,
        message: _friendlyError(error),
        onRetry: () => ref.invalidate(onlinePlaylistDetailProvider(_key)),
      ),
      data: (playlist) =>
          _buildPlaylist(context, _withDiscoveryArtwork(playlist)),
    );
  }

  PlaylistInfo _withDiscoveryArtwork(PlaylistInfo playlist) {
    final summary = widget.summary;
    if (summary == null) return playlist;
    return PlaylistInfo(
      id: playlist.id,
      name: playlist.name,
      source: playlist.source,
      tracks: playlist.tracks,
      coverUrl: summary.coverUrl,
      creator: playlist.creator,
      description: playlist.description,
      playCount: playlist.playCount,
      trackCount: playlist.trackCount,
    );
  }

  Widget _buildPlaylist(BuildContext context, PlaylistInfo playlist) {
    final local = _findSavedPlaylist(
      ref.watch(localPlaylistsProvider),
      playlist,
    );
    final queueId = 'online:${playlist.source.code}:${playlist.id}';
    final queue = <DownloadHistoryEntry>[];
    for (final music in playlist.tracks) {
      final entry = PlaylistTrack.fromMusicInfo(
        music,
      ).toQueueEntry(playlistId: queueId);
      if (entry != null) queue.add(entry);
    }

    final artworkProvider = networkPlaylistArtworkProvider(
      playlist.coverUrl,
      size: widget.summary == null ? 1200 : discoveryPlaylistArtworkSize,
    );
    final wide = playlistDetailUsesWideLayout(context);
    final metadata = [
      playlist.source.label,
      if (playlist.creator?.trim().isNotEmpty == true) playlist.creator!.trim(),
      '${playlist.totalTracks} 首',
      if (playlist.playCount != null)
        '${_compactCount(playlist.playCount!)} 次播放',
    ].join(' · ');
    return PlaylistArtworkTheme(
      artworkProvider: artworkProvider,
      cacheKey: _onlineArtworkCacheKey(
        playlist.source,
        playlist.id,
        playlist.coverUrl,
      ),
      immersiveStatusBar: !wide,
      child: Builder(
        builder: (context) {
          final scheme = Theme.of(context).colorScheme;
          Future<void> refresh() async {
            ref.invalidate(onlinePlaylistDetailProvider(_key));
            await ref.read(onlinePlaylistDetailProvider(_key).future);
          }

          PlaylistDetailActions actionsWith(EdgeInsetsGeometry padding) {
            return PlaylistDetailActions(
              onPlay: queue.isEmpty
                  ? null
                  : () => _playQueue(queue.first, queue),
              onFavorite: _saving
                  ? null
                  : () => _toggleFavorite(playlist, local),
              saving: _saving,
              removingFavorite: _removingFavorite,
              saved: local != null,
              padding: padding,
            );
          }

          final trackSlivers = <Widget>[
            SliverToBoxAdapter(
              child: _PlaylistTracksHeading(count: playlist.tracks.length),
            ),
            if (playlist.tracks.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: Text('这个歌单暂时没有可用歌曲')),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 156),
                sliver: SliverList.separated(
                  itemCount: playlist.tracks.length,
                  separatorBuilder: (_, _) => _trackListDivider(scheme),
                  itemBuilder: (context, index) {
                    final music = playlist.tracks[index];
                    final entry = queue.where((item) {
                      final json = item.musicJson;
                      return json != null && json['id'] == music.id;
                    }).firstOrNull;
                    return Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 900),
                        child: _OnlinePlaylistTrackTile(
                          music: music,
                          onPlay: entry == null
                              ? null
                              : () => _playQueue(entry, queue),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ];

          return Scaffold(
            backgroundColor: scheme.surface,
            body: wide
                ? PlaylistWideBody(
                    topBar: const ImmersivePlaylistTopBar(
                      title: '歌单详情',
                      onImage: false,
                    ),
                    infoPane: PlaylistWideInfoPane(
                      artworkProvider: artworkProvider,
                      artworkHeroTag: onlinePlaylistArtworkHeroTag(
                        playlist.source,
                        playlist.id,
                      ),
                      title: playlist.name,
                      metadata: metadata,
                      description: playlist.description,
                      actions: actionsWith(const EdgeInsets.only(top: 4)),
                    ),
                    right: RefreshIndicator(
                      onRefresh: refresh,
                      child: CustomScrollView(
                        key: PageStorageKey(
                          'online-playlist-wide-${playlist.source.code}-${playlist.id}',
                        ),
                        physics: const AlwaysScrollableScrollPhysics(
                          parent: BouncingScrollPhysics(),
                        ),
                        slivers: trackSlivers,
                      ),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: refresh,
                    child: CustomScrollView(
                      key: PageStorageKey(
                        'online-playlist-${playlist.source.code}-${playlist.id}',
                      ),
                      physics: const AlwaysScrollableScrollPhysics(
                        parent: BouncingScrollPhysics(),
                      ),
                      slivers: [
                        SliverToBoxAdapter(
                          child: ImmersivePlaylistHeader(
                            artworkProvider: artworkProvider,
                            artworkHeroTag: onlinePlaylistArtworkHeroTag(
                              playlist.source,
                              playlist.id,
                            ),
                            topBar: const ImmersivePlaylistTopBar(
                              title: '歌单详情',
                            ),
                          ),
                        ),
                        SliverToBoxAdapter(
                          child: PlaylistDetailInfo(
                            title: playlist.name,
                            metadata: metadata,
                            description: playlist.description,
                          ),
                        ),
                        SliverToBoxAdapter(
                          child: actionsWith(
                            const EdgeInsets.fromLTRB(16, 4, 16, 8),
                          ),
                        ),
                        ...trackSlivers,
                      ],
                    ),
                  ),
          );
        },
      ),
    );
  }

  Future<void> _playQueue(
    DownloadHistoryEntry entry,
    List<DownloadHistoryEntry> queue,
  ) async {
    final available = await ensureQueueEntryMusicSourceAvailable(
      context,
      entry,
    );
    if (!available || !mounted) return;
    context.go('/player', extra: _returnLocation);
    await ref
        .read(playerControllerProvider.notifier)
        .playFromPlaylistQueue(entry, queue);
  }

  Future<void> _toggleFavorite(
    PlaylistInfo playlist,
    LocalPlaylist? savedPlaylist,
  ) async {
    if (_saving) return;
    final removing = savedPlaylist != null;
    setState(() {
      _saving = true;
      _removingFavorite = removing;
    });
    try {
      final notifier = ref.read(localPlaylistsProvider.notifier);
      if (savedPlaylist == null) {
        await notifier.importOnline(playlist);
      } else {
        await notifier.delete(savedPlaylist.id);
      }
      if (!mounted) return;
      showAppToast(
        context,
        removing ? '已取消收藏' : '已收藏到我的歌单',
        type: AppToastType.success,
      );
    } catch (error) {
      if (!mounted) return;
      showAppToast(
        context,
        '${removing ? '取消收藏' : '收藏'}失败：$error',
        type: AppToastType.error,
      );
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
          _removingFavorite = false;
        });
      }
    }
  }
}

class _OnlinePlaylistTrackTile extends ConsumerStatefulWidget {
  const _OnlinePlaylistTrackTile({required this.music, required this.onPlay});

  final MusicInfo music;
  final VoidCallback? onPlay;

  @override
  ConsumerState<_OnlinePlaylistTrackTile> createState() =>
      _OnlinePlaylistTrackTileState();
}

class _OnlinePlaylistTrackTileState
    extends ConsumerState<_OnlinePlaylistTrackTile> {
  late bool _fallbackRequested = _embeddedCover.isEmpty;

  String get _embeddedCover => widget.music.meta.picUrl?.trim() ?? '';

  @override
  void didUpdateWidget(covariant _OnlinePlaylistTrackTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.music.id != widget.music.id) {
      _fallbackRequested = _embeddedCover.isEmpty;
    }
  }

  void _requestFallbackCover() {
    if (_fallbackRequested || !mounted) return;
    setState(() => _fallbackRequested = true);
  }

  @override
  Widget build(BuildContext context) {
    final task = ref.watch(
      downloadProgressProvider.select(
        (value) => value.latestTaskForMusic(widget.music.id),
      ),
    );
    final fallback = _fallbackRequested
        ? ref.watch(onlineTrackCoverProvider(OnlineTrackCoverKey(widget.music)))
        : null;
    final resolved = fallback?.asData?.value?.trim() ?? '';
    final coverUrl = resolved.isNotEmpty ? resolved : _embeddedCover;
    return SearchResultTile(
      music: widget.music,
      coverUrl: coverUrl,
      coverLoading: fallback?.isLoading ?? false,
      onCoverError: _requestFallbackCover,
      downloadTask: task,
      onDownload: () => showQualityPickerSheet(context, widget.music),
      onPlay: widget.onPlay ?? () {},
    );
  }
}

class _DetailLoading extends StatelessWidget {
  const _DetailLoading({
    required this.summary,
    required this.source,
    required this.playlistId,
  });

  final PlaylistSummary? summary;
  final MusicSource source;
  final String playlistId;

  @override
  Widget build(BuildContext context) {
    final item = summary;
    final artworkProvider = networkPlaylistArtworkProvider(
      item?.coverUrl,
      size: discoveryPlaylistArtworkSize,
    );
    final wide = playlistDetailUsesWideLayout(context);
    final title = item?.name ?? '歌单详情';
    final metadata = item == null ? '正在读取歌单信息' : _summaryMetadata(item);
    final descriptionLoading = item?.description?.trim().isEmpty ?? true;
    return PlaylistArtworkTheme(
      artworkProvider: artworkProvider,
      cacheKey: _onlineArtworkCacheKey(source, playlistId, item?.coverUrl),
      immersiveStatusBar: !wide,
      child: Builder(
        builder: (context) {
          final scheme = Theme.of(context).colorScheme;
          final skeletonSliver = SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 150),
            sliver: SliverList.separated(
              itemCount: wide ? 8 : 5,
              separatorBuilder: (_, _) => _trackListDivider(scheme),
              itemBuilder: (_, _) => const _DetailTrackSkeleton(),
            ),
          );
          return Scaffold(
            backgroundColor: scheme.surface,
            body: wide
                ? PlaylistWideBody(
                    topBar: const ImmersivePlaylistTopBar(
                      title: '歌单详情',
                      onImage: false,
                    ),
                    infoPane: PlaylistWideInfoPane(
                      artworkProvider: artworkProvider,
                      artworkLoading: artworkProvider == null,
                      artworkHeroTag: onlinePlaylistArtworkHeroTag(
                        source,
                        playlistId,
                      ),
                      title: title,
                      metadata: metadata,
                      description: item?.description,
                      descriptionLoading: descriptionLoading,
                      actions: const PlaylistDetailActions(
                        loading: true,
                        padding: EdgeInsets.only(top: 4),
                      ),
                    ),
                    right: CustomScrollView(
                      physics: const AlwaysScrollableScrollPhysics(
                        parent: BouncingScrollPhysics(),
                      ),
                      slivers: [
                        SliverToBoxAdapter(
                          child: _PlaylistTracksHeading(
                            count: item?.trackCount,
                          ),
                        ),
                        skeletonSliver,
                      ],
                    ),
                  )
                : CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(
                      parent: BouncingScrollPhysics(),
                    ),
                    slivers: [
                      SliverToBoxAdapter(
                        child: ImmersivePlaylistHeader(
                          artworkProvider: artworkProvider,
                          artworkLoading: artworkProvider == null,
                          artworkHeroTag: onlinePlaylistArtworkHeroTag(
                            source,
                            playlistId,
                          ),
                          topBar: const ImmersivePlaylistTopBar(title: '歌单详情'),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: PlaylistDetailInfo(
                          title: title,
                          metadata: metadata,
                          description: item?.description,
                          descriptionLoading: descriptionLoading,
                        ),
                      ),
                      const SliverToBoxAdapter(
                        child: PlaylistDetailActions(loading: true),
                      ),
                      SliverToBoxAdapter(
                        child: _PlaylistTracksHeading(count: item?.trackCount),
                      ),
                      skeletonSliver,
                    ],
                  ),
          );
        },
      ),
    );
  }
}

class _DetailError extends StatelessWidget {
  const _DetailError({
    required this.summary,
    required this.source,
    required this.playlistId,
    required this.message,
    required this.onRetry,
  });

  final PlaylistSummary? summary;
  final MusicSource source;
  final String playlistId;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final item = summary;
    final artworkProvider = networkPlaylistArtworkProvider(
      item?.coverUrl,
      size: discoveryPlaylistArtworkSize,
    );
    final wide = playlistDetailUsesWideLayout(context);
    final title = item?.name ?? '歌单详情';
    final metadata = item == null ? source.label : _summaryMetadata(item);
    final errorContent = Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 24, 28, 140),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 44),
            const SizedBox(height: 14),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 14),
            IconButton.filledTonal(
              tooltip: '重试',
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
      ),
    );
    return PlaylistArtworkTheme(
      artworkProvider: artworkProvider,
      cacheKey: _onlineArtworkCacheKey(
        source,
        item?.id ?? 'unknown',
        item?.coverUrl,
      ),
      immersiveStatusBar: !wide,
      child: Builder(
        builder: (context) {
          final scheme = Theme.of(context).colorScheme;
          return Scaffold(
            backgroundColor: scheme.surface,
            body: wide
                ? PlaylistWideBody(
                    topBar: const ImmersivePlaylistTopBar(
                      title: '歌单详情',
                      onImage: false,
                    ),
                    infoPane: PlaylistWideInfoPane(
                      artworkProvider: artworkProvider,
                      artworkHeroTag: onlinePlaylistArtworkHeroTag(
                        source,
                        playlistId,
                      ),
                      title: title,
                      metadata: metadata,
                      description: item?.description,
                    ),
                    right: errorContent,
                  )
                : CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(
                      parent: BouncingScrollPhysics(),
                    ),
                    slivers: [
                      SliverToBoxAdapter(
                        child: ImmersivePlaylistHeader(
                          artworkProvider: artworkProvider,
                          artworkHeroTag: onlinePlaylistArtworkHeroTag(
                            source,
                            playlistId,
                          ),
                          topBar: const ImmersivePlaylistTopBar(title: '歌单详情'),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: PlaylistDetailInfo(
                          title: title,
                          metadata: metadata,
                          description: item?.description,
                        ),
                      ),
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: errorContent,
                      ),
                    ],
                  ),
          );
        },
      ),
    );
  }
}

class _PlaylistTracksHeading extends StatelessWidget {
  const _PlaylistTracksHeading({this.count});

  final int? count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: SizedBox(
            height: 24,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                count == null ? '歌曲' : '歌曲  $count',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DetailTrackSkeleton extends StatelessWidget {
  const _DetailTrackSkeleton();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 与数据态的 SearchResultTile 行保持同宽同高（900 限宽居中、行高 62、
    // 封面 44），loading → data 切换不跳动。
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: SizedBox(
          key: const ValueKey('detail-track-skeleton'),
          height: 62,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 2, 2, 2),
            child: Row(
              children: [
                const ClipRRect(
                  borderRadius: BorderRadius.all(Radius.circular(8)),
                  child: SizedBox.square(
                    dimension: 44,
                    child: CoverLoadingSkeleton(),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FractionallySizedBox(
                        widthFactor: 0.58,
                        child: Container(
                          height: 12,
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                      ),
                      const SizedBox(height: 9),
                      FractionallySizedBox(
                        widthFactor: 0.36,
                        child: Container(
                          height: 9,
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(5),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 44),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Widget _trackListDivider(ColorScheme scheme) {
  return Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 900),
      child: Divider(
        height: 1,
        indent: 56,
        color: scheme.outlineVariant.withValues(alpha: 0.35),
      ),
    ),
  );
}

String _summaryMetadata(PlaylistSummary summary) {
  return [
    summary.source.label,
    if (summary.creator?.trim().isNotEmpty == true) summary.creator!.trim(),
    if (summary.trackCount != null) '${summary.trackCount} 首',
    if (summary.playCount != null) '${_compactCount(summary.playCount!)} 次播放',
  ].join(' · ');
}

String _onlineArtworkCacheKey(
  MusicSource source,
  String playlistId,
  String? coverUrl,
) {
  return 'online:${source.code}:$playlistId:${coverUrl?.trim() ?? ''}';
}

LocalPlaylist? _findSavedPlaylist(
  List<LocalPlaylist> playlists,
  PlaylistInfo online,
) {
  for (final playlist in playlists) {
    if (playlist.originSourceCode == online.source.code &&
        playlist.originPlaylistId == online.id) {
      return playlist;
    }
  }
  return null;
}

String _compactCount(int count) {
  if (count >= 100000000) {
    return '${(count / 100000000).toStringAsFixed(count >= 1000000000 ? 0 : 1)}亿';
  }
  if (count >= 10000) {
    return '${(count / 10000).toStringAsFixed(count >= 100000 ? 0 : 1)}万';
  }
  return '$count';
}

String _friendlyError(Object error) {
  final value = error.toString().replaceFirst('Exception: ', '').trim();
  return value.isEmpty ? '歌单加载失败，请稍后重试' : value;
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
