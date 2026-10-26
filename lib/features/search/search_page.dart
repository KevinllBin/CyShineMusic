import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart' hide SearchController;
import 'package:flutter/material.dart' as material show SearchController;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/music_api.dart';
import '../../core/debug/debug_paint_guard.dart';
import '../../core/models/enums.dart';
import '../../core/models/music_info.dart';
import '../../core/storage/settings_store.dart';
import '../../core/ui/app_toast.dart';
import '../discovery/discovery_content.dart';
import '../discovery/discovery_controller.dart';
import '../music_sources/music_source_action_guard.dart';
import '../player/player_controller.dart';
import '../playlists/playlist_browser_sheet.dart';
import '../playlists/playlist_models.dart';
import '../playlists/playlist_store.dart';
import '../shell/widgets/shell_header.dart';
import 'search_controller.dart';
import 'search_history_store.dart';
import 'search_toolbar_state.dart';
import 'widgets/quality_picker_sheet.dart';
import 'widgets/search_history_suggestions.dart';
import '../../core/models/search_category.dart';
import 'widgets/catalog_results.dart';
import 'widgets/search_field.dart';
import 'widgets/search_filters.dart';

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  late final material.SearchController _controller;
  late final ScrollController _resultsScrollController;
  Object? _tipRequest;
  Iterable<Widget> _lastSuggestionWidgets = const <Widget>[];
  AppToastHandle? _searchErrorToast;

  @override
  void initState() {
    super.initState();
    _controller = material.SearchController();
    // Loading replaces the list. Each new result starts at the top instead of
    // restoring the previous list's PageStorage offset when it reattaches.
    _resultsScrollController = ScrollController(keepScrollOffset: false);
    _controller.text = ref.read(searchControllerProvider).keyword;
  }

  @override
  void dispose() {
    _tipRequest = null;
    _dismissSearchErrorToast();
    _controller.dispose();
    _resultsScrollController.dispose();
    super.dispose();
  }

  Future<Iterable<Widget>> _buildSuggestionTiles(
    BuildContext context,
    material.SearchController controller,
  ) async {
    final query = controller.text.trim();
    if (query.isEmpty) {
      _tipRequest = null;
      _lastSuggestionWidgets = [
        SearchHistorySuggestions(
          onSelected: (keyword) => _runSearch(keyword: keyword),
        ),
      ];
      return _lastSuggestionWidgets;
    }

    // Identity-only marker — the SDK fan-out can't really cancel, so we just
    // ignore the result if a newer keystroke has started another tip lookup.
    final request = Object();
    _tipRequest = request;
    try {
      final api = ref.read(musicApiProvider);
      final tips = await api.searchTip(
        keyword: query,
        source: _sourceForSearchRequest(ref.read(searchControllerProvider)),
      );
      if (!identical(request, _tipRequest) || query != controller.text.trim()) {
        return _lastSuggestionWidgets;
      }
      final seen = <String>{};
      final items = tips
          .map((tip) => tip.trim())
          .where((tip) => tip.isNotEmpty && seen.add(tip))
          .take(8)
          .map(
            (tip) => SearchSuggestionTile(
              text: tip,
              onTap: () {
                controller.closeView(tip);
                _runSearch(keyword: tip);
              },
              onComplete: () {
                controller.text = tip;
                controller.selection = TextSelection.collapsed(
                  offset: controller.text.length,
                );
              },
            ),
          )
          .toList(growable: false);
      _lastSuggestionWidgets = items;
      return items;
    } on DioException {
      return _lastSuggestionWidgets;
    }
  }

  Future<void> _runSearch({
    String? keyword,
    int page = 1,
    bool scrollToTopOnSuccess = true,
    bool recordHistory = true,
  }) async {
    DebugPaintGuard.disableNow();
    final query = (keyword ?? _controller.text).trim();
    if (query.isEmpty) {
      showAppToast(context, '请输入歌曲、艺人、歌单或专辑', type: AppToastType.warning);
      return;
    }
    _controller.text = query;
    _controller.selection = TextSelection.collapsed(offset: query.length);
    if (_controller.isAttached && _controller.isOpen) {
      _controller.closeView(query);
    }
    _dismissTransientRoutes();
    _releaseSearchFocus();

    if (recordHistory) {
      ref.read(searchHistoryProvider.notifier).add(query);
    }

    final requestedSource = _sourceForSearchRequest(
      ref.read(searchControllerProvider),
    );
    await ref
        .read(searchControllerProvider.notifier)
        .search(keyword: query, source: requestedSource, page: page);
    if (!scrollToTopOnSuccess || !mounted) return;

    final completedState = ref.read(searchControllerProvider);
    final response = completedState.response;
    final requestStillMatches =
        !completedState.loading &&
        completedState.error == null &&
        completedState.keyword == query &&
        completedState.source == requestedSource &&
        completedState.page == page &&
        response?.page == page;
    if (!requestStillMatches) return;

    _resetResultsScroll();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(searchControllerProvider);

    ref.listen<Set<MusicSource>>(
      settingsProvider.select((settings) => settings.enabledSearchSources),
      (previous, next) {
        _tipRequest = null;
        _lastSuggestionWidgets = const <Widget>[];
      },
    );

    ref.listen<SearchState>(
      searchControllerProvider,
      _handleSearchStateChanged,
    );

    _syncToolbarState(state);

    return Scaffold(
      body: RepaintBoundary(
        child: Column(
          children: [
            // 首页自绘「发现」标题（AppShell 对发现区路由不占顶栏空间），
            // 打开歌单/榜单详情时导航器高度不变，容器变换才不会跳动。
            ShellSectionHeader(
              title: state.isSearchActive ? '搜索' : '发现',
              compact: true,
              fontSize: 22,
              trailing: state.isSearchActive
                  ? const SearchPlatformMenu()
                  : null,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 2, 12, 4),
              child: NativeSearchField(
                controller: _controller,
                onSubmitted: (v) => _runSearch(keyword: v),
                loading: state.loading,
                suggestionsBuilder: _buildSuggestionTiles,
                onClear: _returnToDiscovery,
              ),
            ),
            if (state.isSearchActive) ...[
              const SearchCategoryTabs(),
              const SizedBox(height: 4),
              Expanded(
                child: CatalogResults(
                  state: state,
                  scrollController: _resultsScrollController,
                  onDownload: _openPicker,
                  onPlay: _play,
                  onAddToPlaylist: _selectPlaylistForMusic,
                ),
              ),
            ] else
              const Expanded(child: DiscoveryContent()),
          ],
        ),
      ),
    );
  }

  Future<void> _openPicker(MusicInfo music) async {
    await showQualityPickerSheet(context, music);
  }

  Future<void> _play(MusicInfo music) async {
    final replaceQueue = ref.read(settingsProvider).replaceQueueOnSearchPlay;
    // Capture the visible page before awaiting the source check, since a new
    // search or page change may replace the results while it is pending.
    final results = List<MusicInfo>.of(
      ref.read(searchControllerProvider).response?.list ?? [music],
    );
    final available = await ensureOnlineMusicSourcesAvailable(context, [
      music.source,
    ]);
    if (!available || !mounted) return;
    final entry = PlaylistTrack.fromMusicInfo(
      music,
    ).toQueueEntry(playlistId: 'search');
    if (entry == null) return;
    final player = ref.read(playerControllerProvider.notifier);
    if (!replaceQueue) {
      await player.playSingleQueueEntry(entry);
      return;
    }
    // Queue only metadata. The player resolves the selected song now and
    // fetches other playback URLs only when those songs are played.
    final queue = [
      for (final result in results)
        ?PlaylistTrack.fromMusicInfo(result).toQueueEntry(playlistId: 'search'),
    ];
    await player.playFromPlaylistQueue(entry, queue);
  }

  Future<void> _selectPlaylistForMusic(MusicInfo music) async {
    final destination = await showPlaylistBrowserSheet(
      context,
      mode: PlaylistBrowserMode.addSongs,
    );
    if (!mounted || destination == null) return;

    const prefix = '/playlists/';
    if (!destination.startsWith(prefix)) return;
    final playlistId = destination.substring(prefix.length);
    final store = ref.read(localPlaylistsProvider.notifier);
    final playlist = store.byId(playlistId);
    if (playlist == null) {
      showAppToast(context, '歌单不存在或已被删除', type: AppToastType.warning);
      return;
    }

    try {
      final added = await store.addMusic(playlistId, music);
      if (!mounted) return;
      showAppToast(
        context,
        added == 0 ? '歌曲已在「${playlist.name}」中' : '已添加到「${playlist.name}」',
        type: added == 0 ? AppToastType.info : AppToastType.success,
      );
    } catch (error) {
      if (!mounted) return;
      showAppToast(context, '添加到歌单失败：$error', type: AppToastType.error);
    }
  }

  void _returnToDiscovery() {
    _controller.clear();
    if (_controller.isAttached && _controller.isOpen) {
      _controller.closeView('');
    }
    _tipRequest = null;
    _lastSuggestionWidgets = const <Widget>[];
    _dismissSearchErrorToast();
    ref.read(searchControllerProvider.notifier).resetToDiscovery();
    _releaseSearchFocus();
  }

  void _syncToolbarState(SearchState state) {
    if (!TickerMode.valuesOf(context).enabled ||
        ModalRoute.of(context)?.isCurrent == false) {
      return;
    }
    final response = state.response;
    final hasResults =
        state.category != SearchCategory.all &&
        response != null &&
        response.hasResults;
    final allPage = response?.allPage ?? state.page;
    final canNext =
        hasResults && state.page < (allPage > 0 ? allPage : state.page + 1);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !TickerMode.valuesOf(context).enabled ||
          ModalRoute.of(context)?.isCurrent == false) {
        return;
      }
      final next = SearchToolbarState(
        visible:
            state.category != SearchCategory.all &&
            (hasResults || state.page > 1),
        page: state.page,
        loading: state.loading,
        canPrev: state.page > 1,
        canNext: canNext,
        onPrev: () => _runSearch(
          page: state.page - 1,
          scrollToTopOnSuccess: true,
          recordHistory: false,
        ),
        onNext: () => _runSearch(
          page: state.page + 1,
          scrollToTopOnSuccess: true,
          recordHistory: false,
        ),
        onCloseSearch: state.isSearchActive ? _returnToDiscovery : null,
      );
      // Always refresh the callbacks as well as the visible paging values.
      // They close over the current SearchState page; keeping an older state
      // object here makes the FAB look correct while invoking a stale page.
      ref.read(searchToolbarStateProvider.notifier).state = next;
    });
  }

  void _dismissTransientRoutes() {
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.of(
      context,
      rootNavigator: true,
    ).popUntil((route) => route.isFirst);
  }

  void _releaseSearchFocus() {
    FocusManager.instance.primaryFocus?.unfocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      FocusManager.instance.primaryFocus?.unfocus();
    });
  }

  void _handleSearchStateChanged(SearchState? previous, SearchState next) {
    if (!mounted) return;
    if (previous != null &&
        (previous.category != next.category ||
            previous.source != next.source ||
            previous.keyword != next.keyword ||
            previous.page != next.page ||
            (next.response != null &&
                !identical(previous.response, next.response)))) {
      _resetResultsScroll();
    }
    if (next.error != null && next.error != previous?.error) {
      _dismissSearchErrorToast();
      _searchErrorToast = showAppToast(
        context,
        next.error!,
        type: AppToastType.error,
      );
    } else if (next.error == null && previous?.error != null) {
      _dismissSearchErrorToast();
    }
  }

  void _resetResultsScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_resultsScrollController.hasClients) return;
      _resultsScrollController.jumpTo(
        _resultsScrollController.position.minScrollExtent,
      );
    });
  }

  void _dismissSearchErrorToast() {
    final toast = _searchErrorToast;
    _searchErrorToast = null;
    dismissAppToast(toast, showRemoveAnimation: false);
  }

  MusicSource _sourceForSearchRequest(SearchState state) {
    if (state.isSearchActive) return state.source;
    final discoverySource = ref.read(selectedDiscoverySourceProvider);
    final enabled = ref.read(settingsProvider).enabledSearchSources;
    if (enabled.contains(discoverySource)) return discoverySource;
    return state.source == MusicSource.all || !enabled.contains(state.source)
        ? MusicSource.all
        : state.source;
  }
}
