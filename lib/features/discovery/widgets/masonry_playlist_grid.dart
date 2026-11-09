import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/playlist_summary.dart';
import '../../../core/storage/settings_store.dart';
import '../../../core/ui/container_transform.dart';
import '../../../core/ui/car_display_layout.dart';
import '../../../theme/app_motion.dart';
import '../../shell/shell_bottom_area.dart';
import '../discovery_controller.dart';
import 'discovery_helpers.dart';
import 'discovery_playlist_cover.dart';
import 'discovery_prism_surface.dart';
import 'playlist_preview_dialog.dart';

/// 发现页瀑布流，按列懒加载：每列是一个 [SliverList]，并排放在
/// [SliverCrossAxisGroup] 里，只构建视口附近的卡片。分页追加时不会重建、
/// 重排已经加载的全部卡片，刷得越深也不会越卡。
///
/// 卡片分到哪一列只取决于卡片顺序与估算高度，追加分页不会让已有卡片换列。
class SliverMasonryPlaylistGrid extends ConsumerStatefulWidget {
  const SliverMasonryPlaylistGrid({
    super.key,
    required this.items,
    this.maxWidth = double.infinity,
  });

  final List<PlaylistSummary> items;

  /// 网格最大宽度，超出时居中。
  final double maxWidth;

  @override
  ConsumerState<SliverMasonryPlaylistGrid> createState() =>
      _SliverMasonryPlaylistGridState();
}

class _SliverMasonryPlaylistGridState
    extends ConsumerState<SliverMasonryPlaylistGrid> {
  static const _gap = 10.0;

  /// 每张卡片到达（首屏或分页追加）的时刻。只有刚到达的卡片播放入场动画；
  /// 滚出视口被回收、再滚回来的卡片直接出现，不会边滚边闪。
  final _clock = Stopwatch()..start();
  final _arrivals = <String, Duration>{};

  @override
  void initState() {
    super.initState();
    _recordArrivals();
  }

  @override
  void didUpdateWidget(covariant SliverMasonryPlaylistGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.items, widget.items) ||
        oldWidget.items.length != widget.items.length) {
      _recordArrivals();
    }
  }

  void _recordArrivals() {
    final now = _clock.elapsed;
    for (final item in widget.items) {
      _arrivals.putIfAbsent(item.key, () => now);
    }
  }

  bool _justArrived(PlaylistSummary item) {
    final arrival = _arrivals[item.key];
    return arrival != null && _clock.elapsed - arrival < AppMotion.medium;
  }

  @override
  Widget build(BuildContext context) {
    final carPadModeEnabled = ref.watch(
      settingsProvider.select((settings) => settings.carPadModeEnabled),
    );
    final carDisplay = CarDisplayLayout.enabledOf(context);
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.crossAxisExtent;
        final gridWidth = math.min(available, widget.maxWidth);
        final inset = (available - gridWidth) / 2;
        final columnCount = carDisplay
            ? (gridWidth / 240).floor().clamp(2, 6)
            : carPadModeEnabled || gridWidth >= 700
            ? 3
            : 2;
        final width = (gridWidth - _gap * (columnCount - 1)) / columnCount;
        final columns = List.generate(columnCount, (_) => <_MasonryEntry>[]);
        final heights = List<double>.filled(columnCount, 0);
        for (final item in widget.items) {
          final ratio = _coverRatio(item);
          var target = 0;
          for (var index = 1; index < heights.length; index++) {
            if (heights[index] < heights[target]) target = index;
          }
          columns[target].add(_MasonryEntry(item, ratio));
          heights[target] += width / ratio + 82 + _gap;
        }
        return SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: inset),
          sliver: SliverCrossAxisGroup(
            slivers: [
              for (var index = 0; index < columnCount; index++)
                SliverCrossAxisExpanded(
                  flex: 1,
                  sliver: SliverPadding(
                    padding: EdgeInsets.only(
                      left: index == 0 ? 0 : _gap / 2,
                      right: index == columnCount - 1 ? 0 : _gap / 2,
                    ),
                    sliver: _buildColumn(columns[index]),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildColumn(List<_MasonryEntry> entries) {
    return SliverList.builder(
      itemCount: entries.length,
      findChildIndexCallback: (key) {
        final index = entries.indexWhere(
          (entry) => key == ValueKey(entry.summary.key),
        );
        return index < 0 ? null : index;
      },
      itemBuilder: (context, index) {
        final entry = entries[index];
        return Padding(
          key: ValueKey(entry.summary.key),
          padding: const EdgeInsets.only(bottom: _gap),
          child: _PlaylistDiscoveryCard(
            summary: entry.summary,
            coverRatio: entry.coverRatio,
            reveal: _justArrived(entry.summary),
          ),
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
    required this.reveal,
  });

  final PlaylistSummary summary;
  final double coverRatio;
  final bool reveal;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final path = discoveryPlaylistDetailPath(summary);
    const radius = BorderRadius.all(Radius.circular(18));
    // 详情页从这张卡片的矩形展开（容器变换），封面 Hero 沿同一条曲线飞到
    // 头图；起点必须在 push 之前、卡片还在屏幕上时采集。
    ContainerTransformOrigin? captureOrigin() =>
        ContainerTransformOrigin.capture(
          context,
          borderRadius: radius,
          color: scheme.surfaceContainer,
          revealPadding: ShellBottomArea.revealPaddingOf(context),
        );
    return DiscoveryReveal(
      enabled: reveal,
      child: DiscoveryPrismSurface(
        key: ValueKey('discovery-card-${summary.key}'),
        borderRadius: radius,
        shadows: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.10),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
        child: Material(
          color: Colors.transparent,
          clipBehavior: Clip.antiAlias,
          borderRadius: radius,
          child: InkWell(
            onTap: () => context.push(
              path,
              extra: ContainerTransformExtra(summary, origin: captureOrigin()),
            ),
            onLongPress: () {
              final origin = captureOrigin();
              showDialog<void>(
                context: context,
                builder: (_) =>
                    PlaylistPreviewDialog(summary: summary, origin: origin),
              );
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AspectRatio(
                  aspectRatio: coverRatio,
                  child: Hero(
                    tag: onlinePlaylistArtworkHeroTag(
                      summary.source,
                      summary.id,
                    ),
                    transitionOnUserGestures: true,
                    createRectTween: containerTransformHeroRectTween,
                    child: HeroArtworkShape(
                      // 封面贴着卡片顶部，只有上方两角跟随卡片圆角。
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(18),
                      ),
                      child: DiscoveryPlaylistCover(
                        url: summary.coverUrl,
                        size: 36,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(13, 12, 13, 13),
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
