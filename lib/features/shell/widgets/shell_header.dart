import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../theme/app_motion.dart';
import '../../settings/settings_section.dart';
import '../../songs/songs_toolbar_state.dart';
import '../../playlists/widgets/expanding_header_search.dart';
import '../shell_route_utils.dart';
import 'library_view_menu.dart';
import 'scrolling_page_header.dart';

class ShellHeader extends ConsumerWidget {
  const ShellHeader({
    super.key,
    required this.location,
    required this.playlistBackLocation,
    this.scrollOffset = 0,
    this.floating = false,
  });

  final String location;
  final String playlistBackLocation;
  final double scrollOffset;
  final bool floating;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = shellSchemeFor(location, Theme.of(context).colorScheme);
    final top = MediaQuery.viewPaddingOf(context).top;
    final leaderboardDetail =
        location.startsWith('/discover/leaderboards/') &&
        location.split('/').length > 4;
    final onlineCollectionDetail =
        location.startsWith('/discover/playlists/') || leaderboardDetail;
    final compact =
        location == '/' ||
        isSongsLibraryLocation(location) ||
        onlineCollectionDetail;
    final headerTitle =
        location == '/songs/search' &&
            ref.watch(songsLibraryPlaylistIdProvider) != null
        ? '搜索歌单歌曲'
        : _titleFor(location);
    final settingsParent = settingsParentLocation(location);
    final parentLocation =
        settingsParent ??
        switch (location) {
          '/downloads' || '/playlists' || '/songs/search' => '/songs',
          _ => null,
        };

    final songsToolbar = isSongsLibraryLocation(location)
        ? ref.watch(songsToolbarStateProvider)
        : null;
    if (location == '/songs' ||
        (location == '/songs/search' && songsToolbar?.attached == true)) {
      final header = Padding(
        padding: EdgeInsets.fromLTRB(16, top + 10, 16, 8),
        child: SongsHeader(state: songsToolbar!, scheme: scheme),
      );
      if (floating) {
        return _FloatingHeaderBackdrop(
          height: top + (songsToolbar.batchMode ? 112 : 80),
          child: header,
        );
      }
      return header;
    }

    return ShellSectionHeader(
      title: headerTitle,
      scrollOffset: scrollOffset,
      floating: floating,
      compact: compact,
      fontSize: onlineCollectionDetail ? 18 : (compact ? 22 : null),
      leading: parentLocation != null || location == '/playlists/import'
          ? IconButton(
              tooltip: '返回上一页',
              onPressed: () {
                if (parentLocation != null) {
                  context.go(parentLocation);
                } else if (context.canPop()) {
                  context.pop();
                } else {
                  context.go(playlistBackLocation);
                }
              },
              icon: Icon(
                Icons.arrow_back_ios_new_rounded,
                color: scheme.onSurface,
                size: 21,
              ),
            )
          : null,
    );
  }

  String _titleFor(String location) {
    final settingsSection = SettingsSection.fromLocation(location);
    if (settingsSection != null) return settingsSection.title;
    if (location == '/') return '发现';
    if (location.startsWith('/discover/playlists/')) return '歌单详情';
    if (location.startsWith('/discover/leaderboards/')) {
      return location.split('/').length > 4 ? '榜单详情' : '排行榜';
    }
    if (location == '/playlists') return '歌单管理';
    if (location == '/playlists/import') return '导入歌单';
    if (location.startsWith('/playlists/')) return '歌单详情';
    if (location == '/songs/search') return '搜索本地歌曲';
    if (location == '/settings/sources') return '音源管理';
    if (location == '/settings/webdav') return 'WebDAV 同步';
    if (location == '/settings/equalizer') return '均衡器';
    switch (location) {
      case '/history':
      case '/downloads':
        return '下载';
      case '/songs':
        return '歌曲';
      case '/player':
        return '播放';
      case '/settings':
        return '设置';
      case '/debug':
        return '调试日志';
      default:
        return '栖弦';
    }
  }
}

/// 分区标题行：状态栏留白 + 可选 leading + 标题。AppShell 的顶栏与自绘顶栏
/// 的发现区页面（`/` 的「发现」、排行榜列表）共用，保证同一套字号与留白。
///
/// 发现区页面自绘顶栏的原因：AppShell 对发现区全部路由不占顶栏空间，
/// 「发现 ↔ 歌单/榜单详情」之间导航器高度不变，详情页的容器变换才不会
/// 让下层列表跳动。
class ShellSectionHeader extends StatelessWidget {
  const ShellSectionHeader({
    super.key,
    required this.title,
    this.compact = false,
    this.fontSize,
    this.leading,
    this.trailing,
    this.scrollOffset = 0,
    this.floating = false,
  });

  final String title;

  /// 紧凑留白（首页「发现」、歌曲库）。
  final bool compact;

  /// 为 null 时用 headlineSmall 的默认字号。
  final double? fontSize;

  final Widget? leading;
  final Widget? trailing;
  final double scrollOffset;
  final bool floating;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final top = MediaQuery.viewPaddingOf(context).top;
    if (floating) {
      final progress = (scrollOffset / 56).clamp(0.0, 1.0);
      return _FloatingHeaderBackdrop(
        height: top + 88,
        child: Padding(
          padding: EdgeInsets.fromLTRB(18, top + 10, 18, 14),
          child: SizedBox(
            height: 48,
            child: Row(
              children: [
                if (leading case final leading?) ...[
                  FloatingHeaderSurface(
                    child: SizedBox.square(dimension: 48, child: leading),
                  ),
                  const SizedBox(width: 14),
                ],
                Expanded(
                  child: ClipRect(
                    child: IgnorePointer(
                      child: Opacity(
                        opacity: 1 - progress,
                        child: Transform.translate(
                          offset: Offset(0, -scrollOffset.clamp(0.0, 32.0)),
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.headlineSmall?.copyWith(
                              color: scheme.onSurface,
                              fontSize: fontSize,
                              fontWeight: FontWeight.w600,
                              height: 1.05,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(
        18,
        top + (compact ? 10 : 16),
        18,
        compact ? 8 : 12,
      ),
      child: Row(
        children: [
          if (leading case final leading?) ...[
            leading,
            const SizedBox(width: 4),
          ],
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.headlineSmall?.copyWith(
                color: scheme.onSurface,
                fontSize: fontSize,
                fontWeight: FontWeight.w600,
                height: 1.05,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class _FloatingHeaderBackdrop extends StatelessWidget {
  const _FloatingHeaderBackdrop({required this.height, required this.child});

  final double height;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    return SizedBox(
      height: height,
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0, 0.35, 0.7, 1],
                    colors: [
                      surface,
                      surface.withValues(alpha: 0.96),
                      surface.withValues(alpha: 0.62),
                      surface.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class SongsHeader extends StatelessWidget {
  const SongsHeader({super.key, required this.state, required this.scheme});

  final SongsToolbarState state;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final title = Text(
      state.libraryTitle,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
        color: scheme.onSurface,
        fontSize: 22,
        fontWeight: FontWeight.w600,
        height: 1.05,
      ),
    );

    if (state.batchMode) {
      return Column(
        key: const ValueKey('songs-header-batch'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 44,
            child: Align(alignment: Alignment.centerLeft, child: title),
          ),
          Container(
            key: const ValueKey('songs-batch-header'),
            height: 44,
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: scheme.outlineVariant.withValues(alpha: 0.34),
                ),
                bottom: BorderSide(
                  color: scheme.outlineVariant.withValues(alpha: 0.34),
                ),
              ),
            ),
            child: Row(
              children: [
                TextButton(
                  onPressed: state.hasSongs ? state.onToggleSelectAll : null,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(72, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    alignment: Alignment.centerLeft,
                  ),
                  child: Text(state.allSelected ? '取消全选' : '全选'),
                ),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: AppMotion.short,
                    child: Text(
                      '已选中 ${state.selectedCount} 项',
                      key: ValueKey(state.selectedCount),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: scheme.onSurface,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
                SizedBox.square(
                  dimension: 44,
                  child: IconButton(
                    tooltip: '退出批量管理',
                    onPressed: state.onToggleBatch,
                    icon: const Icon(Icons.close_rounded, size: 20),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    final controls = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: FloatingHeaderSurface(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: LibraryViewMenu(
              title: state.libraryTitle,
              activePlaylistId: state.activePlaylistId,
              scheme: scheme,
              onSelected: state.onSelectLibraryPlaylist ?? (_) {},
            ),
          ),
        ),
        const SizedBox(width: 6),
        _SongsHeaderIconButton(
          tooltip: '歌单',
          icon: Icons.queue_music_rounded,
          onPressed: state.onOpenPlaylists,
        ),
      ],
    );
    final controller = state.searchController;
    final focusNode = state.searchFocusNode;
    return SizedBox(
      key: const ValueKey('songs-header-normal'),
      height: 44,
      child: Row(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: controller == null || focusNode == null
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(child: controls),
                        const SizedBox(width: 6),
                        _SongsHeaderIconButton(
                          tooltip: state.searchLabel,
                          icon: Icons.search_rounded,
                          onPressed: state.onSearch,
                        ),
                      ],
                    )
                  : ExpandingHeaderSearch(
                      title: state.libraryTitle,
                      collapsedContent: controls,
                      shrinkWrap: true,
                      controller: controller,
                      focusNode: focusNode,
                      expanded: state.searchMode,
                      autoFocus: state.searchAutoFocus,
                      tooltip: state.searchLabel,
                      onOpen: state.onSearch ?? () {},
                      onClose: state.onCloseSearch ?? () {},
                      onChanged: state.onSearchChanged ?? (_) {},
                    ),
            ),
          ),
          const SizedBox(width: 6),
          FloatingHeaderSurface(
            child: _LibraryOverflowMenu(
              onOpenHistory: state.onOpenHistory,
              onShuffle: state.hasSongs ? state.onShuffle : null,
              onUpdatePlaylist: state.onUpdatePlaylist,
              updatingPlaylist: state.updatingPlaylist,
            ),
          ),
        ],
      ),
    );
  }
}

class _SongsHeaderIconButton extends StatelessWidget {
  const _SongsHeaderIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FloatingHeaderSurface(
      child: SizedBox.square(
        dimension: 44,
        child: IconButton(
          tooltip: tooltip,
          onPressed: onPressed,
          icon: Icon(icon, size: 20),
          visualDensity: VisualDensity.compact,
        ),
      ),
    );
  }
}

class _LibraryOverflowMenu extends StatelessWidget {
  const _LibraryOverflowMenu({
    this.onOpenHistory,
    this.onShuffle,
    this.onUpdatePlaylist,
    this.updatingPlaylist = false,
  });

  final VoidCallback? onOpenHistory;
  final VoidCallback? onShuffle;
  final VoidCallback? onUpdatePlaylist;
  final bool updatingPlaylist;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox.square(
      dimension: 44,
      child: PopupMenuButton<VoidCallback>(
        key: const ValueKey('songs-overflow-menu'),
        tooltip: '更多歌曲操作',
        useRootNavigator: true,
        position: PopupMenuPosition.under,
        popUpAnimationStyle: const AnimationStyle(duration: AppMotion.medium),
        color: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        elevation: 3,
        menuPadding: const EdgeInsets.symmetric(vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        style: IconButton.styleFrom(visualDensity: VisualDensity.compact),
        icon: const Icon(Icons.more_vert_rounded, size: 21),
        onSelected: (action) {
          if (context.mounted) action();
        },
        itemBuilder: (context) => [
          PopupMenuItem<VoidCallback>(
            value: onShuffle,
            enabled: onShuffle != null,
            child: const Row(
              children: [
                Icon(Icons.shuffle_rounded, size: 20),
                SizedBox(width: 12),
                Text('随机播放'),
              ],
            ),
          ),
          if (onUpdatePlaylist != null)
            PopupMenuItem<VoidCallback>(
              value: onUpdatePlaylist,
              enabled: !updatingPlaylist,
              child: Row(
                children: [
                  updatingPlaylist
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.2),
                        )
                      : const Icon(Icons.refresh_rounded, size: 20),
                  const SizedBox(width: 12),
                  Text(updatingPlaylist ? '正在更新' : '更新歌单'),
                ],
              ),
            ),
          PopupMenuItem<VoidCallback>(
            value: onOpenHistory ?? () => context.go('/downloads'),
            child: const Row(
              children: [
                Icon(Icons.history_rounded, size: 20),
                SizedBox(width: 12),
                Text('下载历史'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
