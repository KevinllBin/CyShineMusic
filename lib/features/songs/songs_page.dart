import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/services/saf_storage.dart';
import '../../core/services/local_audio_source.dart';
import '../../core/models/enums.dart';
import '../../core/services/embedded_artwork_cache.dart';
import '../../core/services/embedded_audio_tags.dart';
import '../../core/storage/settings_store.dart';
import '../../core/ui/app_scrollbar.dart';
import '../../core/ui/app_toast.dart';
import '../../core/ui/app_refresh_indicator.dart';
import '../../theme/app_motion.dart';
import '../downloads/download_history_store.dart';
import '../music_sources/music_source_action_guard.dart';
import '../player/player_controller.dart';
import '../search/widgets/quality_picker_sheet.dart';
import '../playlists/playlist_browser_sheet.dart';
import '../playlists/playlist_models.dart';
import '../playlists/online_playlist_updater.dart';
import '../playlists/resolved_playlist_track.dart';
import '../playlists/playlist_store.dart';
import '../shell/shell_toolbar_visibility.dart';
import '../shell/shell_bottom_area.dart';
import '../shell/widgets/scrolling_page_header.dart';
import 'local_song_scan_cache.dart';
import 'scanned_song_file.dart';
import 'song_search.dart';
import 'songs_toolbar_state.dart';
import 'songs_playback_location.dart';
import 'widgets/song_row.dart';
import 'widgets/songs_batch_action_bar.dart';
import 'widgets/songs_placeholders.dart';
import 'widgets/songs_sort_sheet.dart';

const _songSortModeKey = 'songs_sort_mode_v1';
const _songSortAscendingKey = 'songs_sort_ascending_v1';

class SongsPage extends ConsumerStatefulWidget {
  const SongsPage({super.key, this.searchMode = false});

  /// Initial state for restored /songs/search routes. Header searches open in place.
  final bool searchMode;

  @override
  ConsumerState<SongsPage> createState() => _SongsPageState();
}

class _SongsPageState extends ConsumerState<SongsPage> {
  SongSortMode _sortMode = SongSortMode.title;
  bool _ascending = true;
  bool _batchMode = false;
  String _searchQuery = '';
  bool _searchMode = false;
  double? _preSearchScrollOffset;
  final Object _toolbarOwner = Object();
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _songsListKey = GlobalKey(debugLabel: 'songs-list');
  int _locateGeneration = 0;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode(debugLabel: 'songs-search');
  bool? _toolbarVisibilityBeforeSearchFocus;
  List<DownloadHistoryEntry> _visibleSongs = const [];
  Map<String, PlaylistTrack> _visiblePlaylistTracks = const {};
  final Set<String> _selectedIds = <String>{};
  final Set<String> _updatingPlaylistIds = <String>{};
  List<ScannedSongFile>? _scannedFiles;
  String? _scanError;
  ProviderSubscription<List<String>>? _localMusicDirSubscription;
  late final StateController<SongsToolbarState> _toolbarStateController;
  late final StateController<bool> _shellToolbarController;
  late final LocalSongScanCache _scanCache;

  @override
  void initState() {
    super.initState();
    _searchMode = widget.searchMode;
    final prefs = ref.read(sharedPreferencesProvider);
    _sortMode = SongSortMode.fromCode(prefs.getString(_songSortModeKey));
    _ascending = prefs.getBool(_songSortAscendingKey) ?? true;
    _toolbarStateController = ref.read(songsToolbarStateProvider.notifier);
    _shellToolbarController = ref.read(shellToolbarVisibleProvider.notifier);
    _scanCache = ref.read(localSongScanCacheProvider);
    _seedFromScanCache();
    _scanCache.addListener(_handleScanCacheChanged);
    if (_searchMode) _enableSearchFocusHandling();
    _localMusicDirSubscription = ref.listenManual(
      settingsProvider.select((settings) => settings.localMusicDirs),
      (previous, next) {
        if (previous == null || previous == next) return;
        // Keep the currently rendered library in place while the new folders are
        // scanned, then swap the result in one frame. This avoids a loading
        // flash when the local music folder changes from Settings.
        unawaited(_scanCache.ensureScan(directories: next));
      },
    );
    unawaited(_initializeScan());
  }

  void _seedFromScanCache() {
    // Restore against the real list on the first frame; an empty loading frame
    // would clamp PageStorage's saved scroll offset back to zero.
    final snapshot = _scanCache.snapshot;
    if (snapshot == null ||
        !snapshot.matchesDirectories(
          ref.read(settingsProvider).localMusicDirs,
        )) {
      return;
    }
    _scannedFiles = [
      for (final file in snapshot.files) ScannedSongFile.fromSnapshot(file),
    ];
    _scanError = snapshot.error;
  }

  @override
  void didUpdateWidget(covariant SongsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.searchMode == widget.searchMode) return;
    _searchMode = widget.searchMode;
    if (_searchMode) {
      _enableSearchFocusHandling();
    } else {
      _disableSearchFocusHandling();
    }
  }

  Future<void> _initializeScan() async {
    await _scanCache.ensureScan(
      directories: ref.read(settingsProvider).localMusicDirs,
    );
    if (mounted) _handleScanCacheChanged();
  }

  @override
  void dispose() {
    _disableSearchFocusHandling(deferRestore: true);
    _scanCache.removeListener(_handleScanCacheChanged);
    _localMusicDirSubscription?.close();
    _scrollController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    final toolbarStateController = _toolbarStateController;
    final toolbarOwner = _toolbarOwner;
    scheduleMicrotask(() {
      if (!toolbarStateController.mounted) return;
      final toolbarState = toolbarStateController.state;
      if (identical(toolbarState.owner, toolbarOwner)) {
        toolbarStateController.state = const SongsToolbarState();
      }
    });
    super.dispose();
  }

  void _enableSearchFocusHandling() {
    _searchFocusNode.addListener(_handleSearchFocusChanged);
    // The shared header requests focus after its opening animation completes.
  }

  void _disableSearchFocusHandling({bool deferRestore = false}) {
    _searchFocusNode.removeListener(_handleSearchFocusChanged);
    _restoreToolbarAfterSearchFocus(deferRestore: deferRestore);
  }

  void _handleSearchFocusChanged() {
    if (!mounted || !_searchMode) return;
    if (!_searchFocusNode.hasFocus) {
      _restoreToolbarAfterSearchFocus();
      return;
    }

    _toolbarVisibilityBeforeSearchFocus ??= ref.read(
      shellToolbarVisibleProvider,
    );
    final toolbar = ref.read(shellToolbarVisibleProvider.notifier);
    if (toolbar.mounted) toolbar.state = false;
  }

  void _restoreToolbarAfterSearchFocus({bool deferRestore = false}) {
    final previous = _toolbarVisibilityBeforeSearchFocus;
    if (previous == null) return;
    _toolbarVisibilityBeforeSearchFocus = null;
    final toolbar = _shellToolbarController;
    void restore() {
      if (toolbar.mounted) toolbar.state = previous;
    }

    if (deferRestore) {
      // Disposal cannot read WidgetRef or update other widgets during unmount.
      scheduleMicrotask(restore);
    } else {
      restore();
    }
  }

  void _handleScanCacheChanged() {
    if (!mounted) return;
    final snapshot = _scanCache.snapshot;
    if (snapshot == null) return;
    final currentDirectories = ref.read(settingsProvider).localMusicDirs;
    if (!snapshot.matchesDirectories(currentDirectories)) return;

    final files = [
      for (final file in snapshot.files) ScannedSongFile.fromSnapshot(file),
    ];
    setState(() {
      _scannedFiles = files;
      _scanError = snapshot.error;
    });
  }

  Future<void> _scanLocalMusicFolder() {
    return _scanCache.refresh(
      directories: ref.read(settingsProvider).localMusicDirs,
    );
  }

  List<DownloadHistoryEntry> _songs(List<DownloadHistoryEntry> history) {
    final scannedFiles = _scannedFiles;
    if (scannedFiles == null) return const [];
    final historyByPath = <String, DownloadHistoryEntry>{};
    for (final entry in history) {
      final path = entry.savedPath;
      if (path == null || path.isEmpty) continue;
      historyByPath[_pathKey(path)] = entry;
    }

    final out = <DownloadHistoryEntry>[];
    final seen = <String>{};
    for (final file in scannedFiles) {
      final key = _pathKey(file.path);
      final tags = file.tags;
      final historyEntry = historyByPath[key];
      final entry = historyEntry == null
          ? _syntheticEntryFor(file, tags)
          : _entryWithScannedFile(historyEntry, file, tags);
      if (seen.add(key)) out.add(entry);
    }

    int compare(DownloadHistoryEntry a, DownloadHistoryEntry b) {
      switch (_sortMode) {
        case SongSortMode.title:
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        case SongSortMode.artist:
          return a.singer.toLowerCase().compareTo(b.singer.toLowerCase());
        case SongSortMode.added:
          return a.createdAt.compareTo(b.createdAt);
      }
    }

    out.sort(_ascending ? compare : (a, b) => compare(b, a));
    return out;
  }

  ({
    List<DownloadHistoryEntry> songs,
    Map<String, PlaylistTrack> tracksByEntryId,
  })
  _songsForPlaylist(
    LocalPlaylist playlist,
    List<DownloadHistoryEntry> history,
  ) {
    final localIndex = LocalHistoryIndex(history);
    final songs = <DownloadHistoryEntry>[];
    final tracksByEntryId = <String, PlaylistTrack>{};
    for (final track in playlist.tracks) {
      final localEntry = localIndex.resolve(track, playlist.id);
      final entry =
          localEntry ??
          track.toQueueEntry(playlistId: playlist.id) ??
          DownloadHistoryEntry(
            id: 'playlist:${playlist.id}:${track.identityKey}',
            musicId: track.musicId,
            name: track.name,
            singer: track.singer,
            albumName: track.albumName,
            sourceCode: track.sourceCode,
            qualityCode: track.qualityCode,
            status: DownloadHistoryStatus.completed,
            createdAt: DateTime.fromMillisecondsSinceEpoch(0),
            savedPath: track.localPath,
            picUrl: track.picUrl,
            musicJson: track.musicJson,
          );
      songs.add(entry);
      tracksByEntryId[entry.id] = track;
    }
    return (
      songs: List<DownloadHistoryEntry>.unmodifiable(songs),
      tracksByEntryId: Map<String, PlaylistTrack>.unmodifiable(tracksByEntryId),
    );
  }

  DownloadHistoryEntry _entryWithScannedFile(
    DownloadHistoryEntry entry,
    ScannedSongFile file,
    EmbeddedAudioTags? tags,
  ) {
    return DownloadHistoryEntry(
      id: entry.id,
      musicId: entry.musicId,
      name: _preferTag(
        tags?.title,
        entry.name.isEmpty ? file.title : entry.name,
      ),
      singer: _preferTag(tags?.artist, entry.singer),
      albumName: _preferTag(tags?.album, entry.albumName),
      sourceCode: entry.sourceCode,
      qualityCode: entry.qualityCode,
      status: entry.status,
      createdAt: file.createdAt,
      savedPath: file.path,
      message: entry.message,
      picUrl: entry.picUrl,
      sizeBytes: file.sizeBytes,
      musicJson: entry.musicJson,
    );
  }

  DownloadHistoryEntry _syntheticEntryFor(
    ScannedSongFile file,
    EmbeddedAudioTags? tags,
  ) {
    return DownloadHistoryEntry(
      id: 'file:${file.identityPath}',
      musicId: file.identityPath,
      name: _preferTag(tags?.title, file.title),
      singer: _preferTag(tags?.artist, file.artist),
      albumName: _preferTag(tags?.album, ''),
      sourceCode: MusicSource.all.code,
      qualityCode: file.extension.toLowerCase(),
      status: DownloadHistoryStatus.completed,
      createdAt: file.createdAt,
      savedPath: file.path,
      sizeBytes: file.sizeBytes,
    );
  }

  Future<void> _play(
    DownloadHistoryEntry entry,
    List<DownloadHistoryEntry> queue, {
    bool replaceQueue = true,
  }) async {
    final path = entry.savedPath;
    final hasLocalFile =
        path != null && path.isNotEmpty && isLocalAudioSourceAvailable(path);
    final playlistId = ref.read(songsLibraryPlaylistIdProvider);
    final playlistMode = playlistId != null;
    if (!hasLocalFile && (!playlistMode || entry.musicInfo == null)) {
      showAppToast(
        context,
        playlistMode ? '这首歌曲暂时无法播放' : '文件不存在，可能已被移动或删除',
        type: AppToastType.warning,
      );
      return;
    }
    final available = await ensureQueueEntryMusicSourceAvailable(
      context,
      entry,
    );
    if (!available || !mounted) return;
    if (_searchMode) {
      ref.read(songsSearchAutoFocusProvider.notifier).state = false;
      _searchFocusNode.unfocus();
      _restoreToolbarAfterSearchFocus();
    }
    final player = ref.read(playerControllerProvider.notifier);
    if (!replaceQueue) {
      await player.playSingleQueueEntry(entry);
    } else if (playlistMode) {
      await player.playFromPlaylistQueue(entry, queue, playlistId: playlistId);
    } else {
      await player.playFromHistoryQueue(entry, queue);
    }
  }

  Future<void> _locateCurrentSong() async {
    final generation = ++_locateGeneration;
    final initialPlayer = ref.read(playerControllerProvider);
    final trackId = initialPlayer.track?.id;
    if (trackId == null) return;
    final destination = findPlayingLibrary(
      player: initialPlayer,
      sourcePlaylistId: ref
          .read(playerControllerProvider.notifier)
          .queuePlaylistId,
      selectedPlaylistId: ref.read(songsLibraryPlaylistIdProvider),
      playlists: ref.read(localPlaylistsProvider),
      localSongs: _songs(ref.read(downloadHistoryProvider)),
    );
    if (destination == null) {
      showAppToast(context, '当前歌曲不在本地歌曲或已收藏歌单中');
      return;
    }
    final playlistId = destination.playlistId;
    _selectLibraryPlaylist(playlistId);
    if (_searchMode) _clearSearch();
    // Selecting a library replaces the keyed list. Wait until its rows and
    // scroll dimensions are ready before finding the playing song.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || generation != _locateGeneration) return;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : AppMotion.medium;

    // SliverList only builds nearby rows. Use a measured row to reach the
    // target's neighborhood, then align the actual target after layout.
    for (var attempt = 0; attempt < 3; attempt++) {
      if (!mounted || generation != _locateGeneration) return;
      final player = ref.read(playerControllerProvider);
      if (player.track?.id != trackId ||
          ref.read(songsLibraryPlaylistIdProvider) != playlistId ||
          !_scrollController.hasClients) {
        return;
      }
      final queueEntry =
          player.queueIndex >= 0 && player.queueIndex < player.queue.length
          ? player.queue[player.queueIndex]
          : null;
      final index = _visibleSongs.indexWhere(
        (entry) => matchesPlayingEntry(
          entry,
          queueEntry,
          player.track?.localPath,
          trackId,
        ),
      );
      if (index < 0) {
        showAppToast(context, '当前歌曲不在这个列表中');
        return;
      }
      final sliver = _songsListKey.currentContext?.findRenderObject();
      if (sliver is! RenderSliverMultiBoxAdaptor) return;
      RenderBox? anchor;
      RenderBox? target;
      var child = sliver.firstChild;
      while (child != null) {
        final data = child.parentData! as SliverMultiBoxAdaptorParentData;
        // The separated list alternates song rows and 1dp dividers.
        if (data.index!.isEven) anchor ??= child;
        if (data.index == index * 2) {
          target = child;
          break;
        }
        child = sliver.childAfter(child);
      }
      final position = _scrollController.position;
      if (target != null) {
        await position.ensureVisible(
          target,
          alignment: 0.45,
          duration: duration,
          curve: AppMotion.emphasized,
        );
        return;
      }
      if (anchor == null) return;
      final data = anchor.parentData! as SliverMultiBoxAdaptorParentData;
      final anchorOffset = RenderAbstractViewport.of(
        anchor,
      ).getOffsetToReveal(anchor, 0.45).offset;
      final offset =
          (anchorOffset + (index - data.index! ~/ 2) * (anchor.size.height + 1))
              .clamp(position.minScrollExtent, position.maxScrollExtent)
              .toDouble();
      // Skip a long scroll animation when the target is far away.
      if (duration == Duration.zero ||
          (offset - position.pixels).abs() > position.viewportDimension * 2) {
        _scrollController.jumpTo(offset);
      } else {
        await _scrollController.animateTo(
          offset,
          duration: duration,
          curve: AppMotion.emphasized,
        );
      }
      await WidgetsBinding.instance.endOfFrame;
    }
  }

  Future<void> _playRandom(List<DownloadHistoryEntry> songs) async {
    final playable = songs
        .where((entry) {
          final path = entry.savedPath;
          return (path != null &&
                  path.isNotEmpty &&
                  isLocalAudioSourceAvailable(path)) ||
              entry.musicInfo != null;
        })
        .toList(growable: false);
    if (playable.isEmpty) {
      showAppToast(context, '没有可播放的本地歌曲', type: AppToastType.warning);
      return;
    }
    final shuffled = [...playable]..shuffle(math.Random());
    await _play(shuffled.first, shuffled);
  }

  void _shuffleVisibleSongs() {
    unawaited(_playRandom(_visibleSongs));
  }

  Future<void> _playSelected(List<DownloadHistoryEntry> songs) async {
    final selected = songs
        .where((entry) => _selectedIds.contains(entry.id))
        .where((entry) {
          final path = entry.savedPath;
          return (path != null &&
                  path.isNotEmpty &&
                  isLocalAudioSourceAvailable(path)) ||
              entry.musicInfo != null;
        })
        .toList(growable: false);
    if (selected.isEmpty) {
      showAppToast(context, '请先选择可播放的歌曲', type: AppToastType.warning);
      return;
    }
    setState(() {
      _selectedIds.clear();
      _batchMode = false;
    });
    await _play(selected.first, selected);
  }

  Future<void> _addNext(DownloadHistoryEntry entry) async {
    final path = entry.savedPath;
    final hasLocalFile =
        path != null && path.isNotEmpty && isLocalAudioSourceAvailable(path);
    if (!hasLocalFile && entry.musicInfo == null) {
      showAppToast(context, '文件不存在，无法加入队列', type: AppToastType.warning);
      return;
    }
    final available = await ensureQueueEntryMusicSourceAvailable(
      context,
      entry,
    );
    if (!available || !mounted) return;
    await ref.read(playerControllerProvider.notifier).enqueueNext(entry);
    if (!mounted) return;
    showAppToast(context, '已添加到下一首播放', type: AppToastType.success);
  }

  Future<void> _addSongToPlaylist(
    DownloadHistoryEntry entry,
    LocalPlaylist playlist,
  ) async {
    try {
      final added = await ref.read(localPlaylistsProvider.notifier).addEntries(
        playlist.id,
        [entry],
      );
      if (!mounted) return;
      if (added == 0) {
        showAppToast(
          context,
          '歌曲已在「${playlist.name}」中',
          type: AppToastType.info,
        );
        return;
      }
      showAppToast(
        context,
        '已添加到「${playlist.name}」',
        type: AppToastType.success,
      );
    } catch (error) {
      if (!mounted) return;
      showAppToast(context, '添加到歌单失败：$error', type: AppToastType.error);
    }
  }

  Future<void> _selectPlaylistForSong(DownloadHistoryEntry entry) async {
    final destination = await showPlaylistBrowserSheet(
      context,
      mode: PlaylistBrowserMode.addSongs,
    );
    if (!mounted || destination == null) return;

    const prefix = '/playlists/';
    if (!destination.startsWith(prefix)) return;
    final playlistId = destination.substring(prefix.length);
    LocalPlaylist? playlist;
    for (final candidate in ref.read(localPlaylistsProvider)) {
      if (candidate.id == playlistId) {
        playlist = candidate;
        break;
      }
    }
    if (playlist == null) {
      showAppToast(context, '歌单不存在或已被删除', type: AppToastType.warning);
      return;
    }
    await _addSongToPlaylist(entry, playlist);
  }

  bool _deletingFiles = false;

  Future<void> _deleteSong(DownloadHistoryEntry entry) => _deleteSongs([entry]);

  Future<void> _deleteSongs(List<DownloadHistoryEntry> entries) async {
    if (_deletingFiles) return;
    final paths = entries
        .map((e) => e.savedPath)
        .whereType<String>()
        .where((p) => p.isNotEmpty)
        .toSet();
    if (paths.isEmpty) return;
    _deletingFiles = true;
    final history = ref.read(downloadHistoryProvider);
    final historyNotifier = ref.read(downloadHistoryProvider.notifier);
    final playlists = ref.read(localPlaylistsProvider.notifier);
    final scanCache = _scanCache;
    final wasBatch = _batchMode;
    try {
      final result = await SafStorage.deleteFiles(paths);
      final deletedKeys = result.deletedPaths.map(_pathKey).toSet();
      if (deletedKeys.isNotEmpty) {
        for (final path in result.deletedPaths) {
          await playlists.removeLocalPathFromAll(
            path,
            pathKey: scanCache.pathKey,
          );
          _forgetTagCache(path);
        }
        await historyNotifier.removeMany([
          for (final item in history)
            if (item.savedPath != null &&
                deletedKeys.contains(_pathKey(item.savedPath!)))
              item.id,
        ]);
        await scanCache.flush();
        if (mounted && wasBatch) {
          setState(() {
            _selectedIds
              ..clear()
              ..addAll(
                entries
                    .where(
                      (entry) =>
                          entry.savedPath != null &&
                          !deletedKeys.contains(_pathKey(entry.savedPath!)),
                    )
                    .map((e) => e.id),
              );
            _batchMode = _selectedIds.isNotEmpty;
          });
        }
      }
      if (!mounted) return;
      if (result.failed.isNotEmpty) {
        showAppToast(
          context,
          '已删除 ${deletedKeys.length} 个文件，${result.failed.length} 个失败：${result.failed.values.first}',
          type: deletedKeys.isEmpty ? AppToastType.error : AppToastType.warning,
        );
      } else if (result.cancelled) {
        showAppToast(
          context,
          deletedKeys.isEmpty ? '已取消删除' : '已删除 ${deletedKeys.length} 个文件，其余已取消',
        );
      } else {
        showAppToast(
          context,
          '已删除 ${deletedKeys.length} 个文件',
          type: AppToastType.success,
        );
      }
    } catch (error) {
      if (mounted) {
        showAppToast(context, '删除失败：$error', type: AppToastType.error);
      }
    } finally {
      _deletingFiles = false;
    }
  }

  Future<void> _removePlaylistTrack(
    LocalPlaylist playlist,
    PlaylistTrack track,
  ) async {
    final removed = await ref
        .read(localPlaylistsProvider.notifier)
        .removeTrack(playlist.id, track.id);
    if (!mounted || !removed) return;
    setState(
      () => _selectedIds.removeWhere(
        (entryId) => _visiblePlaylistTracks[entryId]?.id == track.id,
      ),
    );
    showAppToast(context, '已从歌单移除', type: AppToastType.success);
  }

  Future<void> _removeSelectedFromPlaylist(
    LocalPlaylist playlist,
    List<DownloadHistoryEntry> songs,
  ) async {
    final selectedEntries = songs
        .where((entry) => _selectedIds.contains(entry.id))
        .toList(growable: false);
    final trackIds = <String>{};
    for (final entry in selectedEntries) {
      final track = _visiblePlaylistTracks[entry.id];
      if (track != null) trackIds.add(track.id);
    }
    if (trackIds.isEmpty) {
      showAppToast(context, '请先选择要移出的歌曲', type: AppToastType.warning);
      return;
    }
    final removed = await ref
        .read(localPlaylistsProvider.notifier)
        .removeTracks(playlist.id, trackIds);
    if (!mounted || removed == 0) return;
    setState(() {
      _selectedIds.clear();
      _batchMode = false;
    });
    showAppToast(context, '已从歌单移出 $removed 首歌曲', type: AppToastType.success);
  }

  Future<void> _openPlaylists() async {
    final destination = await showPlaylistBrowserSheet(context);
    if (!mounted || destination == null) return;
    context.go(destination);
  }

  void _openHistory() {
    context.go('/downloads');
  }

  void _openSearch() {
    if (_searchMode) return;
    _preSearchScrollOffset = _scrollController.hasClients
        ? _scrollController.offset
        : null;
    ref.read(songsSearchAutoFocusProvider.notifier).state = true;
    _enableSearchFocusHandling();
    setState(() {
      _searchMode = true;
      _batchMode = false;
      _selectedIds.clear();
    });
  }

  void _closeSearch() {
    if (!_searchMode) return;
    _disableSearchFocusHandling();
    _searchFocusNode.unfocus();
    _searchController.clear();
    setState(() {
      _searchMode = false;
      _searchQuery = '';
      _selectedIds.clear();
    });
    final previousOffset = _preSearchScrollOffset;
    _preSearchScrollOffset = null;
    if (previousOffset != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_searchMode && _scrollController.hasClients) {
          _scrollController.jumpTo(
            previousOffset.clamp(0, _scrollController.position.maxScrollExtent),
          );
        }
      });
    }
    // Keep old links/restored search routes working; new searches stay in place.
    if (widget.searchMode) context.go('/songs');
  }

  Future<void> _updatePlaylist(LocalPlaylist playlist) async {
    if (_updatingPlaylistIds.contains(playlist.id)) return;
    setState(() => _updatingPlaylistIds.add(playlist.id));
    try {
      final result = await ref
          .read(onlinePlaylistUpdaterProvider)
          .update(
            playlist: playlist,
            store: ref.read(localPlaylistsProvider.notifier),
          );
      if (!mounted) return;
      showAppToast(
        context,
        onlinePlaylistUpdateMessage(result),
        type: AppToastType.success,
      );
    } catch (error) {
      if (!mounted) return;
      showAppToast(context, '更新歌单失败：$error', type: AppToastType.error);
    } finally {
      if (mounted) setState(() => _updatingPlaylistIds.remove(playlist.id));
    }
  }

  void _selectLibraryPlaylist(String? playlistId) {
    final normalized = playlistId?.trim();
    final nextId = normalized == null || normalized.isEmpty ? null : normalized;
    if (ref.read(songsLibraryPlaylistIdProvider) == nextId) return;
    ref.read(songsLibraryPlaylistIdProvider.notifier).select(nextId);
    if (_searchMode) _preSearchScrollOffset = 0;
    setState(() {
      _selectedIds.clear();
      _batchMode = false;
    });
  }

  void _setSort(SongSortMode mode, bool ascending) {
    if (!mounted || (_sortMode == mode && _ascending == ascending)) return;
    setState(() {
      _sortMode = mode;
      _ascending = ascending;
    });
    unawaited(_persistSongSortPreferences());
  }

  Future<void> _openSortSheet() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final toolbar = ref.read(shellToolbarVisibleProvider.notifier);
    final wasToolbarVisible = ref.read(shellToolbarVisibleProvider);
    toolbar.state = false;
    try {
      await showSongsSortSheet(
        context: context,
        initialMode: _sortMode,
        initialAscending: _ascending,
        onChanged: _setSort,
      );
    } finally {
      if (toolbar.mounted) toolbar.state = wasToolbarVisible;
    }
  }

  void _updateSearchQuery(String query) {
    if (_searchQuery == query) return;
    setState(() {
      _searchQuery = query;
      if (_batchMode) _selectedIds.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _searchMode && _scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    });
  }

  void _clearSearch() {
    _searchController.clear();
    _updateSearchQuery('');
    FocusManager.instance.primaryFocus?.unfocus();
  }

  Future<void> _persistSongSortPreferences() async {
    final prefs = ref.read(sharedPreferencesProvider);
    await Future.wait([
      prefs.setString(_songSortModeKey, _sortMode.code),
      prefs.setBool(_songSortAscendingKey, _ascending),
    ]);
  }

  void _toggleVisibleSelection() {
    _toggleSelectAll(_visibleSongs);
  }

  Future<void> _addSelectedToPlaylist(List<DownloadHistoryEntry> songs) async {
    final selected = songs
        .where((entry) => _selectedIds.contains(entry.id))
        .toList(growable: false);
    if (selected.isEmpty) {
      showAppToast(context, '请先选择歌曲', type: AppToastType.warning);
      return;
    }
    final destination = await showPlaylistBrowserSheet(
      context,
      mode: PlaylistBrowserMode.addSongs,
    );
    if (!mounted || destination == null) return;
    const prefix = '/playlists/';
    if (!destination.startsWith(prefix)) return;
    final playlistId = destination.substring(prefix.length);
    final added = await ref
        .read(localPlaylistsProvider.notifier)
        .addEntries(playlistId, selected);
    if (!mounted) return;
    if (added == 0) {
      showAppToast(context, '所选歌曲已在这个歌单中', type: AppToastType.info);
      return;
    }
    setState(() {
      _selectedIds.clear();
      _batchMode = false;
    });
    showAppToast(context, '已加入 $added 首歌曲', type: AppToastType.success);
  }

  String _pathKey(String path) => _scanCache.pathKey(path);

  void _forgetTagCache(String path) {
    EmbeddedArtworkCache.evictPath(path);
  }

  void _toggleBatchMode() {
    _setBatchMode(!_batchMode);
  }

  void _setBatchMode(bool enabled) {
    if (_batchMode == enabled) return;
    _searchFocusNode.unfocus();
    setState(() {
      _batchMode = enabled;
      if (!enabled) _selectedIds.clear();
    });
  }

  void _toggleSelection(DownloadHistoryEntry entry) {
    setState(() {
      if (!_selectedIds.add(entry.id)) _selectedIds.remove(entry.id);
    });
  }

  void _toggleSelectAll(List<DownloadHistoryEntry> songs) {
    if (songs.isEmpty) return;
    final ids = {for (final entry in songs) entry.id};
    setState(() {
      final selectedCount = _selectedIds.where(ids.contains).length;
      if (selectedCount == ids.length) {
        _selectedIds.clear();
      } else {
        _selectedIds
          ..clear()
          ..addAll(ids);
      }
    });
  }

  Future<void> _confirmDeleteSelected(List<DownloadHistoryEntry> songs) async {
    final selected = songs
        .where((entry) => _selectedIds.contains(entry.id))
        .toList(growable: false);
    if (selected.isEmpty) {
      showAppToast(context, '请先选择要删除的歌曲', type: AppToastType.warning);
      return;
    }

    await _deleteSongs(selected);
  }

  void _syncToolbarState({
    required String libraryTitle,
    required String? activePlaylistId,
    required int songCount,
    required int selectedCount,
    required LocalPlaylist? activePlaylist,
    required bool searchAutoFocus,
  }) {
    if (!TickerMode.valuesOf(context).enabled ||
        ModalRoute.of(context)?.isCurrent == false) {
      return;
    }
    final allSelected = songCount > 0 && selectedCount == songCount;
    final canUpdatePlaylist = activePlaylist?.isOnlineImport == true;
    final updatingPlaylist =
        activePlaylist != null &&
        _updatingPlaylistIds.contains(activePlaylist.id);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !TickerMode.valuesOf(context).enabled ||
          ModalRoute.of(context)?.isCurrent == false) {
        return;
      }
      final current = ref.read(songsToolbarStateProvider);
      if (current.matchesView(
        owner: _toolbarOwner,
        libraryTitle: libraryTitle,
        activePlaylistId: activePlaylistId,
        songCount: songCount,
        selectedCount: selectedCount,
        allSelected: allSelected,
        batchMode: _batchMode,
        searchMode: _searchMode,
        searchAutoFocus: searchAutoFocus,
        canUpdatePlaylist: canUpdatePlaylist,
        updatingPlaylist: updatingPlaylist,
      )) {
        return;
      }
      ref.read(songsToolbarStateProvider.notifier).state = SongsToolbarState(
        owner: _toolbarOwner,
        libraryTitle: libraryTitle,
        activePlaylistId: activePlaylistId,
        songCount: songCount,
        selectedCount: selectedCount,
        allSelected: allSelected,
        batchMode: _batchMode,
        searchMode: _searchMode,
        searchAutoFocus: searchAutoFocus,
        onSelectLibraryPlaylist: _selectLibraryPlaylist,
        onOpenPlaylists: _openPlaylists,
        onSearch: _openSearch,
        onCloseSearch: _closeSearch,
        onSearchChanged: _updateSearchQuery,
        searchController: _searchController,
        searchFocusNode: _searchFocusNode,
        onShuffle: _shuffleVisibleSongs,
        onOpenHistory: _openHistory,
        onUpdatePlaylist: canUpdatePlaylist
            ? () => _updatePlaylist(activePlaylist!)
            : null,
        updatingPlaylist: updatingPlaylist,
        onToggleBatch: _toggleBatchMode,
        onToggleSelectAll: _toggleVisibleSelection,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final playlists = ref.watch(localPlaylistsProvider);
    final selectedPlaylistId = ref.watch(songsLibraryPlaylistIdProvider);
    LocalPlaylist? selectedPlaylist;
    if (selectedPlaylistId != null) {
      for (final playlist in playlists) {
        if (playlist.id == selectedPlaylistId) {
          selectedPlaylist = playlist;
          break;
        }
      }
      if (selectedPlaylist == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted ||
              ref.read(songsLibraryPlaylistIdProvider) != selectedPlaylistId) {
            return;
          }
          ref.read(songsLibraryPlaylistIdProvider.notifier).select(null);
        });
      }
    }
    final playlistMode = selectedPlaylist != null;
    final history = ref.watch(downloadHistoryProvider);
    final playlistSongs = selectedPlaylist == null
        ? null
        : _songsForPlaylist(selectedPlaylist, history);
    final allSongs = playlistSongs?.songs ?? _songs(history);
    _visiblePlaylistTracks = playlistSongs?.tracksByEntryId ?? const {};
    final songs = _searchMode
        ? filterSongsByQuery(allSongs, _searchQuery)
        : allSongs;
    final scanning = !playlistMode && _scannedFiles == null;
    final playbackIdentity = ref.watch(
      playerControllerProvider.select((state) {
        final queueIndex = state.queueIndex;
        final queueEntry = queueIndex >= 0 && queueIndex < state.queue.length
            ? state.queue[queueIndex]
            : null;
        return (
          queueEntry: queueEntry,
          localPath: state.track?.localPath,
          trackId: state.track?.id,
          playing: state.playing,
        );
      }),
    );
    final artworkVersionByPath = <String, String>{
      for (final file in _scannedFiles ?? const <ScannedSongFile>[])
        _pathKey(file.path): file.fingerprint,
    };
    final selectedCount = songs
        .where((entry) => _selectedIds.contains(entry.id))
        .length;
    _visibleSongs = songs;
    _syncToolbarState(
      libraryTitle: selectedPlaylist?.name ?? '歌曲',
      activePlaylistId: selectedPlaylist?.id,
      songCount: songs.length,
      selectedCount: selectedCount,
      activePlaylist: selectedPlaylist,
      searchAutoFocus: ref.watch(songsSearchAutoFocusProvider),
    );

    final libraryView = AppScrollbar(
      controller: _scrollController,
      child: CustomScrollView(
        controller: _scrollController,
        key: PageStorageKey(
          '${widget.searchMode ? 'songs-search' : 'songs'}-'
          '${selectedPlaylist?.id ?? 'local'}-scroll',
        ),
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        slivers: [
          const SliverToBoxAdapter(child: ScrollHeaderSpacer()),
          if (allSongs.isNotEmpty)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 2),
              sliver: SliverToBoxAdapter(
                child: SongsListSummary(
                  count: songs.length,
                  totalCount: allSongs.length,
                  searching: _searchMode && _searchQuery.trim().isNotEmpty,
                  sortMode: _sortMode,
                  ascending: _ascending,
                  batchMode: _batchMode,
                  onOpenSort: () => unawaited(_openSortSheet()),
                  onToggleBatch: songs.isEmpty ? null : _toggleBatchMode,
                  showSort: !playlistMode,
                  collectionLabel: playlistMode ? '歌单歌曲' : '本地歌曲',
                ),
              ),
            ),
          if (allSongs.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: scanning
                  ? const SongsLoading()
                  : EmptySongs(
                      error: playlistMode ? null : _scanError,
                      playlistMode: playlistMode,
                    ),
            )
          else if (songs.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: EmptySongSearch(),
            )
          else
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                12,
                0,
                12,
                _batchMode ? 12 : ShellBottomArea.contentPadding(context, 104),
              ),
              sliver: SliverList.separated(
                key: _songsListKey,
                itemCount: songs.length,
                separatorBuilder: (_, _) => const SongListDivider(),
                itemBuilder: (context, index) {
                  final entry = songs[index];
                  final path = entry.savedPath;
                  final playing = matchesPlayingEntry(
                    entry,
                    playbackIdentity.queueEntry,
                    playbackIdentity.localPath,
                    playbackIdentity.trackId,
                  );
                  return SongRow(
                    key: ValueKey(entry.id),
                    entry: entry,
                    artworkVersion: path == null
                        ? null
                        : artworkVersionByPath[_pathKey(path)],
                    playing: playing,
                    playingActive: playing && playbackIdentity.playing,
                    batchMode: _batchMode,
                    selected: _selectedIds.contains(entry.id),
                    onToggleSelected: () => _toggleSelection(entry),
                    onAddNext: () => _addNext(entry),
                    onAddToPlaylist: () =>
                        unawaited(_selectPlaylistForSong(entry)),
                    onDownload: entry.musicInfo == null
                        ? null
                        : () =>
                              showQualityPickerSheet(context, entry.musicInfo!),
                    onPlay: () => _play(
                      entry,
                      songs,
                      replaceQueue:
                          !_searchMode ||
                          _searchQuery.trim().isEmpty ||
                          ref.read(settingsProvider).replaceQueueOnSearchPlay,
                    ),
                    onDelete: playlistMode
                        ? () {
                            final track = _visiblePlaylistTracks[entry.id];
                            if (track != null) {
                              unawaited(
                                _removePlaylistTrack(selectedPlaylist!, track),
                              );
                            }
                          }
                        : () => _deleteSong(entry),
                    playlistMode: playlistMode,
                  );
                },
              ),
            ),
        ],
      ),
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      bottomNavigationBar: _batchMode
          ? SongsBatchActionBar(
              selectedCount: selectedCount,
              onDelete: selectedCount == 0
                  ? null
                  : playlistMode
                  ? () => unawaited(
                      _removeSelectedFromPlaylist(selectedPlaylist!, songs),
                    )
                  : () => unawaited(_confirmDeleteSelected(songs)),
              onAddToPlaylist: playlistMode || selectedCount == 0
                  ? null
                  : () => unawaited(_addSelectedToPlaylist(songs)),
              onPlaySelected: selectedCount == 0
                  ? null
                  : () => unawaited(_playSelected(songs)),
              playlistMode: playlistMode,
            )
          : null,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _batchMode || playlistMode
              ? libraryView
              : AppRefreshIndicator(
                  onRefresh: _scanLocalMusicFolder,
                  child: libraryView,
                ),
          if (!_batchMode && playbackIdentity.trackId != null)
            Positioned(
              right: 18,
              bottom: ShellBottomArea.contentPadding(context, 88),
              child: FloatingActionButton.small(
                key: const ValueKey('songs-locate-current'),
                heroTag: null,
                tooltip: '定位当前歌曲',
                elevation: 3,
                onPressed: () => unawaited(_locateCurrentSong()),
                child: const Icon(Icons.my_location_rounded, size: 22),
              ),
            ),
        ],
      ),
    );
  }
}

String _preferTag(String? value, String fallback) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? fallback : trimmed;
}
