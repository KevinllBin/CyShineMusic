import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/enums.dart';
import '../../core/models/leaderboard_info.dart';
import '../../core/models/online_collection_kind.dart';
import '../../core/storage/settings_store.dart';
import '../../core/ui/app_refresh_indicator.dart';
import '../../core/ui/container_transform.dart';
import '../../core/ui/car_display_layout.dart';
import '../shell/widgets/scrolling_page_header.dart';
import '../playlists/widgets/immersive_playlist_chrome.dart';
import '../playlists/widgets/expanding_header_search.dart';
import '../shell/shell_bottom_area.dart';
import 'discovery_controller.dart';
import 'widgets/discovery_placeholders.dart';
import 'widgets/leaderboard_artwork.dart';

class LeaderboardsPage extends ConsumerStatefulWidget {
  const LeaderboardsPage({super.key, required this.source});

  final MusicSource source;

  @override
  ConsumerState<LeaderboardsPage> createState() => _LeaderboardsPageState();
}

class _LeaderboardsPageState extends ConsumerState<LeaderboardsPage> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode(debugLabel: 'leaderboards-search');
  bool _searchMode = false;
  LocalHistoryEntry? _searchHistory;
  MusicSource get source => widget.source;

  @override
  void dispose() {
    _searchMode = false;
    _searchHistory?.remove();
    _searchFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _openSearch() {
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

  @override
  Widget build(BuildContext context) {
    final boards = ref.watch(leaderboardBoardsProvider(source));
    final carPadModeEnabled = ref.watch(
      settingsProvider.select((settings) => settings.carPadModeEnabled),
    );
    return Scaffold(
      body: ScrollingPageHeader(
        topInset: MediaQuery.viewPaddingOf(context).top + 72,
        headerBuilder: (context, scrollOffset) => ImmersivePlaylistTopBar(
          title: '排行榜',
          onImage: false,
          onBack: _searchMode ? _closeSearch : null,
          titleContent: ExpandingHeaderSearch(
            title: '排行榜',
            controller: _searchController,
            focusNode: _searchFocusNode,
            expanded: _searchMode,
            onOpen: _openSearch,
            onClose: _closeSearch,
            onChanged: (_) => setState(() {}),
            hint: '搜索排行榜',
            tooltip: '搜索排行榜',
          ),
        ),
        child: Builder(
          builder: (context) => _buildBoards(
            context,
            ref,
            boards,
            carPadModeEnabled: carPadModeEnabled,
          ),
        ),
      ),
    );
  }

  Widget _buildBoards(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<LeaderboardSummary>> boards, {
    required bool carPadModeEnabled,
  }) {
    return boards.when(
      loading: () => const DiscoveryLoading(),
      error: (error, _) => DiscoveryError(
        message: error.toString().replaceFirst('Exception: ', ''),
        onRetry: () => ref.invalidate(leaderboardBoardsProvider(source)),
      ),
      data: (allItems) {
        final terms = _searchController.text
            .trim()
            .toLowerCase()
            .split(RegExp(r'\s+'))
            .where((s) => s.isNotEmpty);
        final items = allItems
            .where((board) => terms.every(board.name.toLowerCase().contains))
            .toList();
        return AppRefreshIndicator(
          onRefresh: () async {
            ref.invalidate(leaderboardBoardsProvider(source));
            await ref.read(leaderboardBoardsProvider(source).future);
          },
          child: CustomScrollView(
            key: PageStorageKey('leaderboards-${source.code}-scroll'),
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
              const SliverToBoxAdapter(child: ScrollHeaderSpacer()),
              SliverToBoxAdapter(
                child: Center(
                  child: ConstrainedBox(
                    constraints: CarDisplayLayout.contentConstraints(
                      context,
                      maxWidth: 1040,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 6, 14, 16),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: Theme.of(
                                context,
                              ).colorScheme.secondaryContainer,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              Icons.leaderboard_rounded,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSecondaryContainer,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${source.label}排行榜',
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '收录 ${items.length} 个榜单 · 实时掌握流行趋势',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (items.isEmpty)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: Text('没有找到匹配的排行榜')),
                  ),
                ),
              SliverLayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.crossAxisExtent;
                  final columns = carPadModeEnabled
                      ? (width >= 1000
                            ? 5
                            : width >= 720
                            ? 4
                            : 3)
                      : switch (width) {
                          >= 1000 => 5,
                          >= 720 => 4,
                          >= 500 => 3,
                          _ => 2,
                        };
                  return SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      12,
                      0,
                      12,
                      ShellBottomArea.contentPadding(context, 156),
                    ),
                    sliver: SliverGrid.builder(
                      itemCount: items.length,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: 0.82,
                      ),
                      itemBuilder: (context, index) => _LeaderboardGridCard(
                        board: items[index],
                        index: index,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LeaderboardGridCard extends ConsumerWidget {
  const _LeaderboardGridCard({required this.board, required this.index});

  final LeaderboardSummary board;
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final identity = (source: board.source, boardId: board.boardId);
    final preview = ref
        .watch(leaderboardPreviewProvider(identity))
        .asData
        ?.value;
    final coverUrl =
        ref.watch(leaderboardArtworkProvider(identity)) ?? board.coverUrl;
    final resolved = (preview ?? board).copyWith(coverUrl: coverUrl);
    const radius = BorderRadius.all(Radius.circular(14));
    return Card(
      key: ValueKey('leaderboard-card-${board.key}'),
      margin: EdgeInsets.zero,
      elevation: 0,
      color: scheme.surfaceContainer,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.22)),
      ),
      child: InkWell(
        onTap: () => context.push(
          '/discover/leaderboards/${board.source.code}/${board.boardId}',
          extra: ContainerTransformExtra(
            resolved,
            // 详情页从这张卡片展开，封面 Hero 沿同一条曲线飞到头图。
            origin: ContainerTransformOrigin.capture(
              context,
              borderRadius: radius,
              color: scheme.surfaceContainer,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Hero(
                tag: onlinePlaylistArtworkHeroTag(
                  board.source,
                  board.boardId,
                  kind: OnlineCollectionKind.leaderboard,
                ),
                transitionOnUserGestures: true,
                createRectTween: containerTransformHeroRectTween,
                child: HeroArtworkShape(
                  // 封面贴着卡片顶部，只有上方两角跟随卡片圆角。
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(14),
                  ),
                  child: LeaderboardArtwork(
                    name: board.name,
                    index: index,
                    coverUrl: coverUrl,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(11, 9, 9, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          board.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: scheme.onSurface,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          board.updateFrequency ?? '实时更新',
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 19,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
