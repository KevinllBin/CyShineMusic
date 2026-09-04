import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/playlist_summary.dart';
import '../discovery_controller.dart';
import 'discovery_helpers.dart';
import 'discovery_playlist_cover.dart';
import 'playlist_preview_dialog.dart';

class MasonryPlaylistGrid extends StatelessWidget {
  const MasonryPlaylistGrid({super.key, required this.items});

  final List<PlaylistSummary> items;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columnCount = constraints.maxWidth >= 700 ? 3 : 2;
        const gap = 10.0;
        final width =
            (constraints.maxWidth - gap * (columnCount - 1)) / columnCount;
        final columns = List.generate(columnCount, (_) => <_MasonryEntry>[]);
        final heights = List<double>.filled(columnCount, 0);
        for (final item in items) {
          final ratio = _coverRatio(item);
          var target = 0;
          for (var index = 1; index < heights.length; index++) {
            if (heights[index] < heights[target]) target = index;
          }
          columns[target].add(_MasonryEntry(item, ratio));
          heights[target] += width / ratio + 82 + gap;
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var index = 0; index < columns.length; index++) ...[
              if (index > 0) const SizedBox(width: gap),
              Expanded(
                child: Column(
                  children: [
                    for (final entry in columns[index]) ...[
                      _PlaylistDiscoveryCard(
                        summary: entry.summary,
                        coverRatio: entry.coverRatio,
                      ),
                      const SizedBox(height: gap),
                    ],
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  double _coverRatio(PlaylistSummary item) {
    const ratios = <double>[0.76, 0.88, 1, 1.12, 1.24];
    var hash = 17;
    for (final codeUnit in item.key.codeUnits) {
      hash = 37 * hash + codeUnit;
    }
    return ratios[hash.abs() % ratios.length];
  }
}

class _MasonryEntry {
  const _MasonryEntry(this.summary, this.coverRatio);

  final PlaylistSummary summary;
  final double coverRatio;
}

class _PlaylistDiscoveryCard extends StatelessWidget {
  const _PlaylistDiscoveryCard({
    required this.summary,
    required this.coverRatio,
  });

  final PlaylistSummary summary;
  final double coverRatio;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final path = discoveryPlaylistDetailPath(summary);
    return Card(
      key: ValueKey('discovery-card-${summary.key}'),
      margin: EdgeInsets.zero,
      elevation: 0,
      color: scheme.surfaceContainer,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.24)),
      ),
      child: InkWell(
        onTap: () => context.push(path, extra: summary),
        onLongPress: () => showDialog<void>(
          context: context,
          builder: (_) => PlaylistPreviewDialog(summary: summary),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: coverRatio,
              child: Hero(
                tag: onlinePlaylistArtworkHeroTag(summary.source, summary.id),
                transitionOnUserGestures: true,
                createRectTween: (begin, end) =>
                    RectTween(begin: begin, end: end),
                child: DiscoveryPlaylistCover(url: summary.coverUrl, size: 36),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: 38,
                    child: Text(
                      summary.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: scheme.onSurface,
                        fontSize: 13.5,
                        height: 1.28,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    _summaryMeta(summary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 11,
                      height: 1.1,
                      fontWeight: FontWeight.w500,
                    ),
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

String _summaryMeta(PlaylistSummary summary) {
  if (summary.creator?.trim().isNotEmpty == true) {
    return summary.creator!.trim();
  }
  if (summary.trackCount != null) return '${summary.trackCount} 首';
  if (summary.playCount != null) {
    return '${_compactCount(summary.playCount!)} 次播放';
  }
  return '${summary.source.label}精选';
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
