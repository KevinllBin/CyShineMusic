import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/catalog_result.dart';
import '../../../core/models/music_info.dart';
import '../../../core/models/search_category.dart';
import '../../../core/ui/expressive_loading_status.dart';
import '../../../core/ui/container_transform.dart';
import '../../../core/ui/cover_image_source.dart';
import '../../downloads/download_progress.dart';
import '../../shell/shell_bottom_area.dart';
import '../search_controller.dart';
import 'search_result_tile.dart';

class CatalogResults extends ConsumerWidget {
  const CatalogResults({
    super.key,
    required this.state,
    required this.scrollController,
    required this.onDownload,
    required this.onPlay,
    required this.onAddToPlaylist,
  });
  final SearchState state;
  final ScrollController scrollController;
  final ValueChanged<MusicInfo> onDownload;
  final ValueChanged<MusicInfo> onPlay;
  final ValueChanged<MusicInfo> onAddToPlaylist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final response = state.response;
    if (state.loading) {
      return const ExpressiveLoadingStatus(
        title: '正在搜索',
        subtitle: '正在寻找与你有关的音乐',
      );
    }
    if (response == null || !response.hasResults) {
      return _SearchEmpty(
        message: state.error ?? response?.notices.firstOrNull ?? '试试更换关键词或音乐平台',
        title: state.error != null || response?.notices.isNotEmpty == true
            ? '暂时无法显示结果'
            : '没有找到结果',
        onRetry: () => ref.read(searchControllerProvider.notifier).retry(),
      );
    }
    final overview = state.category == SearchCategory.all;
    final scheme = Theme.of(context).colorScheme;
    final children = <Widget>[
      if (response.notices.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 18,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      response.notices.join('；'),
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () =>
                        ref.read(searchControllerProvider.notifier).retry(),
                    child: const Text('重试'),
                  ),
                ],
              ),
            ),
          ),
        ),
      if (!overview)
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 2, 4, 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${state.category.label} · 本页 ${response.visibleCount} 项',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ),
              Text(
                '第 ${state.page} 页',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
              ),
            ],
          ),
        ),
    ];
    for (final category
        in overview ? SearchCategory.values.skip(1) : [state.category]) {
      final entries = response.catalog[category] ?? const <CatalogItem>[];
      final isSongs = category == SearchCategory.songs;
      if (isSongs ? response.list.isEmpty : entries.isEmpty) continue;
      if (overview) {
        children.add(
          _SectionHeading(
            title: category.label,
            onMore: () => ref
                .read(searchControllerProvider.notifier)
                .setCategory(category),
          ),
        );
      }
      if (isSongs) {
        for (final song in response.list.take(
          overview ? 5 : response.list.length,
        )) {
          children.add(
            _SongResult(
              music: song,
              onDownload: onDownload,
              onPlay: onPlay,
              onAdd: onAddToPlaylist,
            ),
          );
        }
      } else {
        for (final item in entries.take(overview ? 3 : entries.length)) {
          children.add(CatalogResultTile(item: item));
        }
      }
      if (overview) children.add(const SizedBox(height: 14));
    }
    return ListView.builder(
      key: const PageStorageKey('search-results-scroll'),
      controller: scrollController,
      padding: EdgeInsets.fromLTRB(
        12,
        0,
        12,
        ShellBottomArea.contentPadding(context, 156),
      ),
      itemCount: children.length,
      itemBuilder: (_, index) => children[index],
    );
  }
}

class CatalogResultTile extends StatelessWidget {
  const CatalogResultTile({super.key, required this.item});
  final CatalogItem item;

  @override
  Widget build(BuildContext context) {
    final summary = item.summary;
    final artist = item.category == SearchCategory.artists;
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(artist ? 30 : 12);
    final image = CoverImageSource.normalizeUrl(summary.coverUrl, size: 180);
    final fallback = ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          artist
              ? Icons.person_rounded
              : item.category == SearchCategory.albums
              ? Icons.album_rounded
              : Icons.queue_music_rounded,
          color: scheme.onSurfaceVariant,
          size: 25,
        ),
      ),
    );
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          final segment = item.category == SearchCategory.artists
              ? 'artists'
              : item.category == SearchCategory.albums
              ? 'albums'
              : 'playlists';
          context.push(
            '/discover/$segment/${summary.source.code}/${Uri.encodeComponent(summary.id)}',
            extra: ContainerTransformExtra(
              summary,
              origin: ContainerTransformOrigin.capture(
                context,
                borderRadius: BorderRadius.circular(16),
                color: scheme.surface,
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: radius,
                child: SizedBox.square(
                  dimension: 58,
                  child: image == null || image.isEmpty
                      ? fallback
                      // NetworkImage appends User-Agent to Dart's default,
                      // which NetEase rejects. Match the song/detail loader.
                      : CachedNetworkImage(
                          imageUrl: image,
                          httpHeaders: CoverImageSource.headersFor(image),
                          fit: BoxFit.cover,
                          memCacheWidth: 180,
                          placeholder: (_, _) => fallback,
                          errorWidget: (_, _, _) => fallback,
                        ),
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      summary.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: scheme.onSurface,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      [
                        summary.source.label,
                        item.subtitle,
                      ].where((s) => s.isNotEmpty).join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 11.5,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: scheme.outline,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, required this.onMore});
  final String title;
  final VoidCallback onMore;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 4),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        TextButton(
          onPressed: onMore,
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('查看更多', style: TextStyle(fontSize: 12)),
              Icon(Icons.chevron_right_rounded, size: 18),
            ],
          ),
        ),
      ],
    ),
  );
}

class _SongResult extends ConsumerWidget {
  const _SongResult({
    required this.music,
    required this.onDownload,
    required this.onPlay,
    required this.onAdd,
  });
  final MusicInfo music;
  final ValueChanged<MusicInfo> onDownload, onPlay, onAdd;
  @override
  Widget build(BuildContext context, WidgetRef ref) => SearchResultTile(
    music: music,
    onDownload: () => onDownload(music),
    onPlay: () => onPlay(music),
    onAddToPlaylist: () => onAdd(music),
    downloadTask: ref.watch(
      downloadProgressProvider.select((p) => p.latestTaskForMusic(music.id)),
    ),
  );
}

class _SearchEmpty extends StatelessWidget {
  const _SearchEmpty({
    required this.title,
    required this.message,
    required this.onRetry,
  });
  final String title, message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.manage_search_rounded,
            size: 56,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('重新搜索'),
          ),
        ],
      ),
    ),
  );
}
