import 'package:flutter/material.dart';

import '../../../core/ui/animated_empty_state.dart';
import '../../../core/ui/expressive_loading_status.dart';
import 'package:prism_ui/prism_ui.dart' as prism;
import '../../shell/shell_bottom_area.dart';
import '../songs_toolbar_state.dart';

class SongsListSummary extends StatelessWidget {
  const SongsListSummary({
    super.key,
    required this.count,
    required this.totalCount,
    required this.searching,
    required this.sortMode,
    required this.ascending,
    required this.batchMode,
    required this.onOpenSort,
    required this.onToggleBatch,
    this.showSort = true,
    this.collectionLabel = '本地歌曲',
  });

  final int count;
  final int totalCount;
  final bool searching;
  final SongSortMode sortMode;
  final bool ascending;
  final bool batchMode;
  final VoidCallback onOpenSort;
  final VoidCallback? onToggleBatch;
  final bool showSort;
  final String collectionLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 52,
      child: Row(
        children: [
          Expanded(
            child: Text(
              searching ? '找到 $count 首歌曲' : '$totalCount 首$collectionLabel',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (showSort)
            _SummaryIconButton(
              key: const ValueKey('songs-sort-button'),
              tooltip: '排序：${sortMode.label}（${ascending ? '升序' : '降序'}）',
              onPressed: onOpenSort,
              icon: const Icon(Icons.sort_rounded, size: 21),
            ),
          if (!batchMode)
            _SummaryIconButton(
              key: const ValueKey('songs-batch-button'),
              tooltip: '批量操作',
              onPressed: onToggleBatch,
              icon: const Icon(Icons.checklist_rounded, size: 21),
            ),
        ],
      ),
    );
  }
}

class _SummaryIconButton extends StatelessWidget {
  const _SummaryIconButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final Widget icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox.square(
      dimension: 48,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        style: IconButton.styleFrom(
          minimumSize: const Size.square(48),
          foregroundColor: scheme.onSurfaceVariant,
          disabledForegroundColor: scheme.onSurface.withValues(alpha: 0.34),
        ),
        icon: icon,
      ),
    );
  }
}

class SongsSearchBar extends StatelessWidget {
  const SongsSearchBar({
    super.key,
    required this.controller,
    this.focusNode,
    required this.query,
    this.autofocus = false,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final String query;
  final bool autofocus;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return prism.SearchField(
      key: const ValueKey('songs-search-bar'),
      controller: controller,
      focusNode: focusNode,
      autofocus: autofocus,
      hintText: '搜索歌曲、歌手或专辑',
      onChanged: onChanged,
      onSubmitted: () => FocusManager.instance.primaryFocus?.unfocus(),
      height: 50,
      fill: Theme.of(context).colorScheme.surfaceContainerLow,
    );
  }
}

class SongListDivider extends StatelessWidget {
  const SongListDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Divider(
      height: 1,
      thickness: 0.7,
      indent: 66,
      endIndent: 4,
      color: scheme.outlineVariant.withValues(alpha: 0.3),
    );
  }
}

class SongsLoading extends StatelessWidget {
  const SongsLoading({super.key});

  @override
  Widget build(BuildContext context) {
    return ExpressiveLoadingStatus(
      title: '正在整理本地音乐',
      subtitle: '正在读取本地音乐文件夹与歌曲信息，请稍候',
      bottomPadding: ShellBottomArea.contentPadding(context, 108),
    );
  }
}

class EmptySongs extends StatelessWidget {
  const EmptySongs({super.key, this.error, this.playlistMode = false});

  final String? error;
  final bool playlistMode;

  @override
  Widget build(BuildContext context) {
    final normalizedError = error?.trim();
    final hasError = normalizedError != null && normalizedError.isNotEmpty;
    return AnimatedEmptyState(
      kind: hasError
          ? EmptyStateKind.cloud
          : playlistMode
          ? EmptyStateKind.playlist
          : EmptyStateKind.library,
      title: hasError
          ? '暂时无法读取歌曲'
          : playlistMode
          ? '歌单还是空的'
          : '还没有本地歌曲',
      message: hasError
          ? normalizedError
          : playlistMode
          ? '把喜欢的歌收进来'
          : '音乐文件夹中的歌曲会显示在这里\n下拉即可重新扫描',
      bottomPadding: ShellBottomArea.contentPadding(context, 108),
    );
  }
}

class EmptySongSearch extends StatelessWidget {
  const EmptySongSearch({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedEmptyState(
      kind: EmptyStateKind.search,
      title: '没有匹配的歌曲',
      message: '换一个歌曲名、歌手或专辑试试',
      bottomPadding: ShellBottomArea.contentPadding(context, 108),
    );
  }
}
