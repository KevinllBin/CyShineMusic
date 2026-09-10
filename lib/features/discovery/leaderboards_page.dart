import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/enums.dart';
import '../../core/models/leaderboard_info.dart';
import '../../core/models/online_collection_kind.dart';
import '../../core/ui/app_refresh_indicator.dart';
import '../../core/ui/container_transform.dart';
import '../shell/widgets/shell_header.dart';
import 'discovery_controller.dart';
import 'widgets/discovery_placeholders.dart';
import 'widgets/leaderboard_artwork.dart';

class LeaderboardsPage extends ConsumerWidget {
  const LeaderboardsPage({super.key, required this.source});

  final MusicSource source;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boards = ref.watch(leaderboardBoardsProvider(source));
    return Scaffold(
      body: Column(
        children: [
          // 发现区页面自绘顶栏，AppShell 对发现区路由不占顶栏空间：这样
          // 打开榜单详情时导航器高度不变，容器变换展开期间列表不会跳动。
          const ShellSectionHeader(title: '排行榜'),
          Expanded(child: _buildBoards(context, ref, boards)),
        ],
      ),
    );
  }

  Widget _buildBoards(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<LeaderboardSummary>> boards,
  ) {
    return boards.when(
      loading: () => const DiscoveryLoading(),
      error: (error, _) => DiscoveryError(
        message: error.toString().replaceFirst('Exception: ', ''),
        onRetry: () => ref.invalidate(leaderboardBoardsProvider(source)),
      ),
      data: (items) => AppRefreshIndicator(
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
            SliverToBoxAdapter(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1040),
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
            SliverLayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.crossAxisExtent;
                final columns = switch (width) {
                  >= 1000 => 5,
                  >= 720 => 4,
                  >= 500 => 3,
                  _ => 2,
                };
                return SliverPadding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 156),
                  sliver: SliverGrid.builder(
                    itemCount: items.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.82,
                    ),
                    itemBuilder: (context, index) =>
                        _LeaderboardGridCard(board: items[index], index: index),
                  ),
                );
              },
            ),
          ],
        ),
      ),
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
