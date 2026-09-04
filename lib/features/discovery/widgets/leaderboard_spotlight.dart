import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/enums.dart';
import '../../../core/models/leaderboard_info.dart';
import '../../../core/models/music_info.dart';
import '../../../core/models/online_collection_kind.dart';
import '../discovery_controller.dart';
import 'leaderboard_artwork.dart';

class LeaderboardSpotlight extends ConsumerWidget {
  const LeaderboardSpotlight({super.key, required this.source});

  final MusicSource source;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boards = ref.watch(leaderboardBoardsProvider(source));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 2, 0, 7),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '官方排行榜',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              TextButton.icon(
                key: ValueKey('leaderboard-all-${source.code}'),
                onPressed: () =>
                    context.push('/discover/leaderboards/${source.code}'),
                label: const Text('查看全部'),
                icon: const Icon(Icons.arrow_forward_rounded, size: 17),
                iconAlignment: IconAlignment.end,
              ),
            ],
          ),
        ),
        SizedBox(
          height: 154,
          child: boards.when(
            loading: () => const _SpotlightLoading(),
            error: (_, _) => _SpotlightError(
              onRetry: () => ref.invalidate(leaderboardBoardsProvider(source)),
            ),
            data: (items) {
              final featured = items.take(4).toList(growable: false);
              return LayoutBuilder(
                builder: (context, constraints) {
                  final cardWidth = math.min(
                    336.0,
                    math.max(286.0, constraints.maxWidth - 28),
                  );
                  return ListView.separated(
                    key: PageStorageKey('leaderboard-spotlight-${source.code}'),
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    itemCount: featured.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 10),
                    itemBuilder: (context, index) => SizedBox(
                      width: cardWidth,
                      child: _LeaderboardPreviewCard(
                        board: featured[index],
                        index: index,
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _LeaderboardPreviewCard extends ConsumerWidget {
  const _LeaderboardPreviewCard({required this.board, required this.index});

  final LeaderboardSummary board;
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final preview = ref.watch(
      leaderboardPreviewProvider((
        source: board.source,
        boardId: board.boardId,
      )),
    );
    final resolved = preview.asData?.value;
    final tracks = resolved?.previewTracks ?? const <MusicInfo>[];
    final failed = preview.hasError;
    final path = '/discover/leaderboards/${board.source.code}/${board.boardId}';
    return Card(
      key: ValueKey('leaderboard-preview-${board.key}'),
      margin: EdgeInsets.zero,
      elevation: 0,
      color: scheme.surfaceContainer,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.24)),
      ),
      child: InkWell(
        onTap: () => context.push(path, extra: resolved ?? board),
        child: Row(
          children: [
            SizedBox(
              width: 118,
              height: double.infinity,
              child: Hero(
                tag: onlinePlaylistArtworkHeroTag(
                  board.source,
                  board.boardId,
                  kind: OnlineCollectionKind.leaderboard,
                ),
                transitionOnUserGestures: true,
                child: LeaderboardArtwork(
                  name: board.name,
                  index: index,
                  coverUrl: resolved?.coverUrl ?? board.coverUrl,
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(13, 11, 11, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            board.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: scheme.onSurface,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 19,
                          color: scheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    if (tracks.isNotEmpty)
                      for (var rank = 0; rank < 3; rank++)
                        _PreviewTrackRow(
                          rank: rank,
                          track: rank < tracks.length ? tracks[rank] : null,
                        )
                    else if (failed)
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '预览加载失败，轻触查看榜单',
                            maxLines: 2,
                            style: TextStyle(
                              color: scheme.onSurfaceVariant,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      )
                    else
                      for (var rank = 0; rank < 3; rank++)
                        const _PreviewTrackSkeleton(),
                    const Spacer(),
                    Text(
                      resolved?.updateFrequency ??
                          '${board.source.label} · 实时更新',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewTrackRow extends StatelessWidget {
  const _PreviewTrackRow({required this.rank, required this.track});

  final int rank;
  final MusicInfo? track;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final item = track;
    final text = item == null
        ? '—'
        : '${item.name}${item.singer.trim().isEmpty ? '' : ' · ${item.singer}'}';
    final rankColor = switch (rank) {
      0 => scheme.primary,
      1 => scheme.tertiary,
      _ => scheme.secondary,
    };
    return SizedBox(
      height: 22,
      child: Row(
        children: [
          SizedBox(
            width: 18,
            child: Text(
              '${rank + 1}',
              style: TextStyle(
                color: rankColor,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: scheme.onSurface,
                fontSize: 11.5,
                height: 1.1,
                fontWeight: rank == 0 ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewTrackSkeleton extends StatelessWidget {
  const _PreviewTrackSkeleton();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(
      context,
    ).colorScheme.onSurfaceVariant.withValues(alpha: 0.12);
    return SizedBox(
      height: 22,
      child: Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: 0.78,
          child: Container(
            height: 8,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
        ),
      ),
    );
  }
}

class _SpotlightLoading extends StatelessWidget {
  const _SpotlightLoading();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 2,
      separatorBuilder: (_, _) => const SizedBox(width: 10),
      itemBuilder: (_, _) => Container(
        width: 310,
        decoration: BoxDecoration(
          color: scheme.surfaceContainer,
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    );
  }
}

class _SpotlightError extends StatelessWidget {
  const _SpotlightError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FilledButton.tonalIcon(
        onPressed: onRetry,
        icon: const Icon(Icons.refresh_rounded),
        label: const Text('重新加载排行榜'),
      ),
    );
  }
}
