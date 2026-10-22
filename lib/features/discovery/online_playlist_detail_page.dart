import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/music_api.dart';
import '../shell/shell_bottom_area.dart';
import '../../core/models/enums.dart';
import '../../core/models/music_info.dart';
import '../../core/models/music_query.dart';
import 'widgets/collection_search_status.dart';
import '../playlists/widgets/expanding_header_search.dart';
import '../../core/models/online_collection_kind.dart';
import '../../core/models/playlist_info.dart';
import '../../core/models/playlist_summary.dart';
import '../../core/services/app_logger.dart';
import '../../core/storage/settings_store.dart';
import '../../core/ui/app_toast.dart';
import '../../core/ui/app_refresh_indicator.dart';
import '../../core/ui/app_scrollbar.dart';
import '../../core/ui/cover_placeholder.dart';
import '../../core/ui/car_display_layout.dart';
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
    this.kind = OnlineCollectionKind.playlist,
    this.summary,
  });

  final MusicSource source;
  final String playlistId;
  final OnlineCollectionKind kind;
  final PlaylistSummary? summary;

  @override
  ConsumerState<OnlinePlaylistDetailPage> createState() =>
      _OnlinePlaylistDetailPageState();
}

class _OnlinePlaylistDetailPageState
    extends ConsumerState<OnlinePlaylistDetailPage> {
  static const _summaryCacheLimit = 48;

  int _trackLimit = onlinePlaylistDetailInitialTrackLimit;
  PlaylistInfo? _lastPlaylist;
  PlaylistSummary? _summary;
  bool _saving = false;
  bool _removingFavorite = false;
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode(
    debugLabel: 'online-collection-search',
  );
  bool _searchMode = false;
  LocalHistoryEntry? _searchHistory;

  OnlinePlaylistIdentity get _identity =>
      (source: widget.source, id: widget.playlistId, kind: widget.kind);

  int get _savedTrackLimit =>
      ref.read(onlinePlaylistTrackLimitCacheProvider)[_identity] ??
      onlinePlaylistDetailInitialTrackLimit;

  OnlinePlaylistKey get _key => OnlinePlaylistKey(
    source: widget.source,
    id: widget.playlistId,
    kind: widget.kind,
    maxTracks: _trackLimit,
  );

  @override
  void initState() {
    super.initState();
    _trackLimit = _savedTrackLimit;
    _summary =
        widget.summary ??
        ref.read(onlinePlaylistSummaryCacheProvider)[_identity];
    _cacheSummary(_summary);
  }

  @override
  void didUpdateWidget(covariant OnlinePlaylistDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final identityChanged =
        oldWidget.source != widget.source ||
        oldWidget.playlistId != widget.playlistId ||
        oldWidget.kind != widget.kind;
    if (identityChanged) {
      _trackLimit = _savedTrackLimit;
      _lastPlaylist = null;
      _closeSearch();
      _summary =
          widget.summary ??
          ref.read(onlinePlaylistSummaryCacheProvider)[_identity];
      _saving = false;
      _removingFavorite = false;
    } else if (widget.summary != null) {
      _summary = widget.summary;
    }
    _cacheSummary(_summary);
  }

  void _cacheSummary(PlaylistSummary? summary) {
    if (summary == null) return;
    final cache = ref.read(onlinePlaylistSummaryCacheProvider);
    if (cache.length >= _summaryCacheLimit && !cache.containsKey(_identity)) {
      cache.remove(cache.keys.first);
    }
    cache[_identity] = summary;
  }

  @override
  void dispose() {
    _searchMode = false;
    _searchHistory?.remove();
    _searchFocusNode.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _openSearch() {
    if (_searchMode) return;
    setState(() => _searchMode = true);
    _searchHistory = LocalHistoryEntry(
      onRemove: () {
        _searchHistory = null;
        if (mounted && _searchMode) _closeSearch();
      },
    );
    ModalRoute.of(context)?.addLocalHistoryEntry(_searchHistory!);
  }

  void _closeSearch() {
    if (_searchHistory != null) {
      _searchHistory!.remove();
      return;
    }
    _searchFocusNode.unfocus();
    _searchController.clear();
    if (mounted) setState(() => _searchMode = false);
  }

  Widget _buildSearchTopBar(
    PlaylistInfo playlist,
    LocalPlaylist? saved, {
    bool onImage = false,
    bool? statusBarOnImage,
    double progress = 1,
  }) {
    return ImmersivePlaylistTopBar(
      title: playlist.name,
      onImage: onImage,
      statusBarOnImage: statusBarOnImage,
      titleOpacity: progress,
      showGradient: progress > 0,
      backdropOpacity: progress,
      blurSigma: 24 * progress,
      onBack: _searchMode ? _closeSearch : null,
      titleContent: ExpandingHeaderSearch(
        title: playlist.name,
        titleOpacity: progress,
        onImage: onImage,
        controller: _searchController,
        focusNode: _searchFocusNode,
        expanded: _searchMode,
        onOpen: _openSearch,
        onClose: _closeSearch,
        onChanged: (_) => setState(() {}),
        hint: widget.kind == OnlineCollectionKind.artist
            ? '搜索这位艺人的热门歌曲'
            : '搜索${widget.kind.label}中的歌曲',
        tooltip: '搜索${widget.kind.label}歌曲',
        actions: [
          if (saved != null && widget.kind == OnlineCollectionKind.playlist)
            ImmersiveTopIconButton(
              tooltip: '随机播放',
              icon: Icons.shuffle_rounded,
              onImage: onImage,
              onPressed: saved.tracks.length < 2
                  ? null
                  : () => _shuffleSavedPlaylist(saved),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final carPadModeEnabled =
        ref.watch(
          settingsProvider.select((settings) => settings.carPadModeEnabled),
        ) ||
        CarDisplayLayout.wideOf(context);
    final detail = ref.watch(onlinePlaylistDetailProvider(_key));
    final loaded = detail.asData?.value;
    if (loaded != null) {
      _lastPlaylist = _withDiscoveryArtwork(loaded);
      // Restore the same cached range before PageStorage restores its offset.
      ref.read(onlinePlaylistTrackLimitCacheProvider)[_identity] = _trackLimit;
    }
    final cached = _lastPlaylist;
    if (cached != null && loaded == null) {
      final loadMoreError = detail.whenOrNull(
        error: (error, _) => _friendlyError(error),
      );
      return _buildPlaylist(
        context,
        cached,
        carPadModeEnabled: carPadModeEnabled,
        loadingMore: detail.isLoading,
        loadMoreError: loadMoreError,
      );
    }
    return detail.when(
      loading: () => _DetailLoading(
        summary: _summary,
        source: widget.source,
        playlistId: widget.playlistId,
        kind: widget.kind,
        carPadModeEnabled: carPadModeEnabled,
      ),
      error: (error, _) => _DetailError(
        summary: _summary,
        source: widget.source,
        playlistId: widget.playlistId,
        kind: widget.kind,
        message: _friendlyError(error),
        onRetry: () => ref.invalidate(onlinePlaylistDetailProvider(_key)),
        carPadModeEnabled: carPadModeEnabled,
      ),
      data: (playlist) => _buildPlaylist(
        context,
        _withDiscoveryArtwork(playlist),
        carPadModeEnabled: carPadModeEnabled,
      ),
    );
  }

  PlaylistInfo _withDiscoveryArtwork(PlaylistInfo playlist) {
    final summary = _summary;
    if (summary == null) return playlist;
    return PlaylistInfo(
      id: playlist.id,
      name: playlist.name.isEmpty ? summary.name : playlist.name,
      source: playlist.source,
      tracks: playlist.tracks,
      coverUrl: summary.coverUrl?.trim().isNotEmpty == true
          ? summary.coverUrl
          : playlist.coverUrl,
      creator: playlist.creator,
      description: playlist.description?.trim().isNotEmpty == true
          ? playlist.description
          : summary.description,
      playCount: playlist.playCount,
      trackCount: playlist.trackCount,
    );
  }

  Widget _buildPlaylist(
    BuildContext context,
    PlaylistInfo playlist, {
    required bool carPadModeEnabled,
    bool loadingMore = false,
    String? loadMoreError,
  }) {
    final local = _findSavedPlaylist(
      ref.watch(localPlaylistsProvider),
      playlist,
      kind: widget.kind,
    );
    final searching = _searchController.text.trim().isNotEmpty;
    final visibleTracks = filterMusicByQuery(
      playlist.tracks,
      _searchController.text,
    );
    final playbackPlaylist = searching
        ? PlaylistInfo(
            id: playlist.id,
            name: playlist.name,
            source: playlist.source,
            tracks: visibleTracks,
            coverUrl: playlist.coverUrl,
            trackCount: visibleTracks.length,
          )
        : playlist;
    final queue = _onlinePlaylistQueue(playbackPlaylist, kind: widget.kind);

    final artworkProvider = networkPlaylistArtworkProvider(
      playlist.coverUrl,
      size: _summary == null ? 1200 : discoveryPlaylistArtworkSize,
    );
    final wide = playlistDetailUsesWideLayout(
      context,
      carPadModeEnabled: carPadModeEnabled,
    );
    final metadata = [
      playlist.source.label,
      if (widget.kind.isCatalog) widget.kind.label,
      if (playlist.creator?.trim().isNotEmpty == true) playlist.creator!.trim(),
      '${playlist.totalTracks} 首',
      if (playlist.playCount != null)
        '${_compactCount(playlist.playCount!)} 次播放',
    ].join(' · ');
    return PlaylistArtworkTheme(
      artworkProvider: artworkProvider,
      cacheKey: _onlineArtworkCacheKey(
        widget.source,
        widget.playlistId,
        playlist.coverUrl,
        kind: widget.kind,
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
              playLabel: searching ? '播放结果' : '播放全部',
              onPlay: queue.isEmpty
                  ? null
                  : () => _playQueue(playbackPlaylist, queue.first),
              onFavorite: _saving
                  ? null
                  : () => _toggleFavorite(playlist, local),
              saving: _saving,
              removingFavorite: _removingFavorite,
              saved: local != null,
              favoriteLabel: local != null
                  ? '已收藏'
                  : widget.kind == OnlineCollectionKind.artist
                  ? '收藏歌曲'
                  : '收藏${widget.kind.label}',
              padding: padding,
            );
          }

          final hasTrackFooter =
              loadingMore ||
              (loadMoreError != null &&
                  playlist.tracks.length < playlist.totalTracks);
          final trackSlivers = <Widget>[
            if (searching)
              SliverToBoxAdapter(
                child: CollectionSearchStatus(
                  caption:
                      '找到 ${visibleTracks.length} 首${playlist.tracks.length < playlist.totalTracks ? ' · 已搜索 ${playlist.tracks.length} / ${playlist.totalTracks} 首' : ''}',
                  loading: loadingMore,
                  onSearchAll: playlist.tracks.length < playlist.totalTracks
                      ? () {
                          if (_trackLimit == playlist.totalTracks) {
                            ref.invalidate(onlinePlaylistDetailProvider(_key));
                          } else {
                            setState(() => _trackLimit = playlist.totalTracks);
                          }
                        }
                      : null,
                ),
              ),
            SliverToBoxAdapter(
              child: _PlaylistTracksHeading(
                count: visibleTracks.length,
                total: searching ? visibleTracks.length : playlist.totalTracks,
                title: widget.kind == OnlineCollectionKind.artist
                    ? '热门歌曲'
                    : '歌曲',
              ),
            ),
            if (visibleTracks.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Text(
                    searching ? '没有匹配的歌曲' : '这个${widget.kind.label}暂时没有可用歌曲',
                  ),
                ),
              )
            else
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  12,
                  0,
                  12,
                  hasTrackFooter ? 0 : 156,
                ),
                sliver: SliverList.separated(
                  itemCount: visibleTracks.length,
                  separatorBuilder: (_, _) =>
                      _trackListDivider(context, scheme),
                  itemBuilder: (context, index) {
                    if (!searching) _requestMoreTracksIfNeeded(playlist, index);
                    final music = visibleTracks[index];
                    final entry = queue.where((item) {
                      final json = item.musicJson;
                      return json != null && json['id'] == music.id;
                    }).firstOrNull;
                    return Center(
                      child: ConstrainedBox(
                        constraints: CarDisplayLayout.contentConstraints(
                          context,
                          maxWidth: 900,
                        ),
                        child: _OnlinePlaylistTrackTile(
                          music: music,
                          onPlay: entry == null
                              ? null
                              : () => _playQueue(playbackPlaylist, entry),
                        ),
                      ),
                    );
                  },
                ),
              ),
            if (loadingMore)
              const SliverToBoxAdapter(child: _LoadMoreTracksIndicator())
            else if (loadMoreError != null &&
                playlist.tracks.length < playlist.totalTracks)
              SliverToBoxAdapter(
                child: _LoadMoreTracksError(
                  message: loadMoreError,
                  onRetry: () =>
                      ref.invalidate(onlinePlaylistDetailProvider(_key)),
                ),
              ),
          ];

          return Scaffold(
            backgroundColor: scheme.surface,
            body: wide
                ? PlaylistWideBody(
                    topBar: _buildSearchTopBar(playbackPlaylist, local),
                    infoPane: PlaylistWideInfoPane(
                      artworkProvider: artworkProvider,
                      artworkHeroTag: onlinePlaylistArtworkHeroTag(
                        playlist.source,
                        playlist.id,
                        kind: widget.kind,
                      ),
                      title: playlist.name,
                      metadata: metadata,
                      description: playlist.description,
                      actions: actionsWith(const EdgeInsets.only(top: 4)),
                    ),
                    right: AppScrollbar(
                      controller: _scrollController,
                      child: AppRefreshIndicator(
                        onRefresh: refresh,
                        child: CustomScrollView(
                          controller: _scrollController,
                          key: PageStorageKey(
                            'online-playlist-wide-${playlist.source.code}-${playlist.id}',
                          ),
                          physics: const AlwaysScrollableScrollPhysics(
                            parent: BouncingScrollPhysics(),
                          ),
                          slivers: trackSlivers,
                        ),
                      ),
                    ),
                  )
                : ScrollingImmersivePlaylistBody(
                    title: playlist.name,
                    topBarBuilder:
                        (context, onImage, statusBarOnImage, progress) =>
                            _buildSearchTopBar(
                              playbackPlaylist,
                              local,
                              onImage: onImage,
                              statusBarOnImage: statusBarOnImage,
                              progress: progress,
                            ),
                    child: AppScrollbar(
                      controller: _scrollController,
                      child: AppRefreshIndicator(
                        onRefresh: refresh,
                        child: CustomScrollView(
                          controller: _scrollController,
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
                                  kind: widget.kind,
                                ),
                                topBar: const ImmersivePlaylistTopBar(
                                  title: '',
                                ),
                                showTopBar: false,
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
                    ),
                  ),
          );
        },
      ),
    );
  }

  Future<void> _shuffleSavedPlaylist(LocalPlaylist playlist) async {
    final queue = [
      for (final track in playlist.tracks)
        ?track.toQueueEntry(playlistId: playlist.id),
    ];
    if (queue.length < 2) return;
    final entry = queue[math.Random().nextInt(queue.length)];
    if (!await ensureQueueEntryMusicSourceAvailable(context, entry) || !mounted) {
      return;
    }
    final player = ref.read(playerControllerProvider.notifier);
    player.setPlaybackMode(PlayerPlaybackMode.shuffle);
    await player.playFromPlaylistQueue(entry, queue, playlistId: playlist.id);
  }

  Future<void> _playQueue(
    PlaylistInfo playlist,
    DownloadHistoryEntry selectedEntry,
  ) async {
    final available = await ensureQueueEntryMusicSourceAvailable(
      context,
      selectedEntry,
    );
    if (!available || !mounted) return;

    final queue = _onlinePlaylistQueue(playlist, kind: widget.kind);
    final entry = _matchingQueueEntry(queue, selectedEntry);
    if (entry == null) return;
    final player = ref.read(playerControllerProvider.notifier);
    final api = ref.read(musicApiProvider);

    final playback = player.playFromPlaylistQueue(entry, queue);
    if (playlist.tracks.length < playlist.totalTracks) {
      unawaited(
        _expandOnlinePlaylistQueue(
          api: api,
          player: player,
          playlist: playlist,
          kind: widget.kind,
          initialQueue: queue,
        ),
      );
    }
    await playback;
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
        final api = ref.read(musicApiProvider);
        final loaded = await api.getCollection(
          source: playlist.source,
          id: playlist.id,
          kind: widget.kind,
        );
        final fullPlaylist = _withDiscoveryArtwork(loaded);
        await notifier.importOnline(
          widget.kind.isCatalog
              ? PlaylistInfo(
                  id: '${widget.kind.name}:${fullPlaylist.id}',
                  name: fullPlaylist.name,
                  source: fullPlaylist.source,
                  tracks: fullPlaylist.tracks,
                  coverUrl: fullPlaylist.coverUrl,
                  creator: fullPlaylist.creator,
                  description: fullPlaylist.description,
                  trackCount: fullPlaylist.trackCount,
                )
              : fullPlaylist,
        );
      } else {
        await notifier.delete(savedPlaylist.id);
      }
      if (!mounted) return;
      showAppToast(
        context,
        removing ? '已取消收藏' : '已完整收藏到我的歌单',
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

  void _requestMoreTracksIfNeeded(PlaylistInfo playlist, int index) {
    if (index < playlist.tracks.length - 6) return;
    _loadMoreTracks(playlist);
  }

  void _loadMoreTracks(PlaylistInfo playlist) {
    if (!TickerMode.valuesOf(context).enabled) return;
    if (playlist.tracks.length >= playlist.totalTracks) return;
    if (_trackLimit >= playlist.totalTracks) return;
    final next = _trackLimit + onlinePlaylistDetailTrackPageSize;
    final target = next > playlist.totalTracks ? playlist.totalTracks : next;
    if (target <= _trackLimit) return;
    final identity = _identity;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          _identity != identity ||
          !TickerMode.valuesOf(context).enabled ||
          _trackLimit >= target) {
        return;
      }
      setState(() => _trackLimit = target);
    });
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
    required this.kind,
    required this.carPadModeEnabled,
  });

  final PlaylistSummary? summary;
  final MusicSource source;
  final String playlistId;
  final OnlineCollectionKind kind;
  final bool carPadModeEnabled;

  @override
  Widget build(BuildContext context) {
    final item = summary;
    final artworkProvider = networkPlaylistArtworkProvider(
      item?.coverUrl,
      size: discoveryPlaylistArtworkSize,
    );
    final wide = playlistDetailUsesWideLayout(
      context,
      carPadModeEnabled: carPadModeEnabled,
    );
    final detailLabel = '${kind.label}详情';
    final title = item?.name ?? detailLabel;
    final metadata = item == null
        ? '正在读取${kind.label}信息'
        : _summaryMetadata(item);
    final descriptionLoading = item?.description?.trim().isEmpty ?? true;
    return PlaylistArtworkTheme(
      artworkProvider: artworkProvider,
      cacheKey: _onlineArtworkCacheKey(
        source,
        playlistId,
        item?.coverUrl,
        kind: kind,
      ),
      immersiveStatusBar: !wide,
      child: Builder(
        builder: (context) {
          final scheme = Theme.of(context).colorScheme;
          final skeletonSliver = SliverPadding(
            padding: EdgeInsets.fromLTRB(
              12,
              0,
              12,
              ShellBottomArea.contentPadding(context, 150),
            ),
            sliver: SliverList.separated(
              itemCount: wide ? 8 : 5,
              separatorBuilder: (_, _) => _trackListDivider(context, scheme),
              itemBuilder: (_, _) => const _DetailTrackSkeleton(),
            ),
          );
          return Scaffold(
            backgroundColor: scheme.surface,
            body: wide
                ? PlaylistWideBody(
                    topBar: ImmersivePlaylistTopBar(
                      title: title,
                      onImage: false,
                    ),
                    infoPane: PlaylistWideInfoPane(
                      artworkProvider: artworkProvider,
                      artworkLoading: artworkProvider == null,
                      artworkHeroTag: onlinePlaylistArtworkHeroTag(
                        source,
                        playlistId,
                        kind: kind,
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
                : ScrollingImmersivePlaylistBody(
                    title: item?.name.trim() ?? '',
                    child: CustomScrollView(
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
                              kind: kind,
                            ),
                            topBar: const ImmersivePlaylistTopBar(title: ''),
                            showTopBar: false,
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
                          child: _PlaylistTracksHeading(
                            count: item?.trackCount,
                          ),
                        ),
                        skeletonSliver,
                      ],
                    ),
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
    required this.kind,
    required this.message,
    required this.onRetry,
    required this.carPadModeEnabled,
  });

  final PlaylistSummary? summary;
  final MusicSource source;
  final String playlistId;
  final OnlineCollectionKind kind;
  final String message;
  final VoidCallback onRetry;
  final bool carPadModeEnabled;

  @override
  Widget build(BuildContext context) {
    final item = summary;
    final artworkProvider = networkPlaylistArtworkProvider(
      item?.coverUrl,
      size: discoveryPlaylistArtworkSize,
    );
    final wide = playlistDetailUsesWideLayout(
      context,
      carPadModeEnabled: carPadModeEnabled,
    );
    final detailLabel = '${kind.label}详情';
    final title = item?.name ?? detailLabel;
    final metadata = item == null ? source.label : _summaryMetadata(item);
    final errorContent = Center(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          28,
          24,
          28,
          ShellBottomArea.contentPadding(context, 140),
        ),
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
        playlistId,
        item?.coverUrl,
        kind: kind,
      ),
      immersiveStatusBar: !wide,
      child: Builder(
        builder: (context) {
          final scheme = Theme.of(context).colorScheme;
          return Scaffold(
            backgroundColor: scheme.surface,
            body: wide
                ? PlaylistWideBody(
                    topBar: ImmersivePlaylistTopBar(
                      title: title,
                      onImage: false,
                    ),
                    infoPane: PlaylistWideInfoPane(
                      artworkProvider: artworkProvider,
                      artworkHeroTag: onlinePlaylistArtworkHeroTag(
                        source,
                        playlistId,
                        kind: kind,
                      ),
                      title: title,
                      metadata: metadata,
                      description: item?.description,
                    ),
                    right: errorContent,
                  )
                : ScrollingImmersivePlaylistBody(
                    title: item?.name.trim() ?? '',
                    child: CustomScrollView(
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
                              kind: kind,
                            ),
                            topBar: const ImmersivePlaylistTopBar(title: ''),
                            showTopBar: false,
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
                  ),
          );
        },
      ),
    );
  }
}

class _PlaylistTracksHeading extends StatelessWidget {
  const _PlaylistTracksHeading({this.count, this.total, this.title = '歌曲'});

  final String title;
  final int? count;
  final int? total;

  String get _label {
    final loaded = count;
    final all = total;
    if (loaded == null) return title;
    if (all != null && all > loaded) return '$title  $loaded/$all';
    return '$title  $loaded';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Center(
        child: ConstrainedBox(
          constraints: CarDisplayLayout.contentConstraints(
            context,
            maxWidth: 900,
          ),
          child: SizedBox(
            height: 24,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _label,
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

class _LoadMoreTracksIndicator extends StatelessWidget {
  const _LoadMoreTracksIndicator();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        ShellBottomArea.contentPadding(context, 156),
      ),
      child: const Center(
        child: SizedBox.square(
          dimension: 22,
          child: CircularProgressIndicator(strokeWidth: 2.4),
        ),
      ),
    );
  }
}

class _LoadMoreTracksError extends StatelessWidget {
  const _LoadMoreTracksError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        ShellBottomArea.contentPadding(context, 156),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: CarDisplayLayout.contentConstraints(
            context,
            maxWidth: 900,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  message,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: '重试',
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
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
        constraints: CarDisplayLayout.contentConstraints(
          context,
          maxWidth: 900,
        ),
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

Widget _trackListDivider(BuildContext context, ColorScheme scheme) {
  return Center(
    child: ConstrainedBox(
      constraints: CarDisplayLayout.contentConstraints(context, maxWidth: 900),
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
  String? coverUrl, {
  OnlineCollectionKind kind = OnlineCollectionKind.playlist,
}) {
  return 'online:${kind.name}:${source.code}:$playlistId:'
      '${coverUrl?.trim() ?? ''}';
}

List<DownloadHistoryEntry> _onlinePlaylistQueue(
  PlaylistInfo playlist, {
  OnlineCollectionKind kind = OnlineCollectionKind.playlist,
}) {
  final queueId = 'online:${kind.name}:${playlist.source.code}:${playlist.id}';
  final queue = <DownloadHistoryEntry>[];
  for (final music in playlist.tracks) {
    final entry = PlaylistTrack.fromMusicInfo(
      music,
    ).toQueueEntry(playlistId: queueId);
    if (entry != null) queue.add(entry);
  }
  return queue;
}

DownloadHistoryEntry? _matchingQueueEntry(
  Iterable<DownloadHistoryEntry> queue,
  DownloadHistoryEntry selected,
) {
  for (final entry in queue) {
    if (entry.id == selected.id ||
        (entry.sourceCode == selected.sourceCode &&
            entry.musicId == selected.musicId)) {
      return entry;
    }
  }
  return null;
}

Future<void> _expandOnlinePlaylistQueue({
  required MusicApi api,
  required PlayerController player,
  required PlaylistInfo playlist,
  required OnlineCollectionKind kind,
  required List<DownloadHistoryEntry> initialQueue,
}) async {
  try {
    final fullPlaylist = await api.getCollection(
      source: playlist.source,
      id: playlist.id,
      kind: kind,
    );
    final fullQueue = _onlinePlaylistQueue(fullPlaylist, kind: kind);
    player.expandPlaylistQueue(
      expectedQueue: initialQueue,
      expandedQueue: fullQueue,
    );
  } catch (error) {
    await AppLogger.write(
      'player',
      'expand online playlist queue failed: $error',
    );
  }
}

LocalPlaylist? _findSavedPlaylist(
  List<LocalPlaylist> playlists,
  PlaylistInfo online, {
  OnlineCollectionKind kind = OnlineCollectionKind.playlist,
}) {
  for (final playlist in playlists) {
    if (playlist.originSourceCode == online.source.code &&
        playlist.originPlaylistId ==
            (kind.isCatalog ? '${kind.name}:${online.id}' : online.id)) {
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
