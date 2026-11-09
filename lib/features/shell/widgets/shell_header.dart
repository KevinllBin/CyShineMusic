import 'package:prism_ui/prism_ui.dart' as prism;
import 'package:prism_ui/icons/prism_glyphs.dart' as prism_glyphs;
import 'package:prism_ui/icons/icons.dart' as glyph;
import 'package:prism_ui/icons/icons.dart' as prism_glyph;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/ui/widgets/app_navigation_button.dart';
import '../../../core/ui/widgets/header_control_style.dart';
import '../../../theme/app_motion.dart';
import '../../settings/settings_section.dart';
import '../../songs/songs_toolbar_state.dart';
import '../../playlists/widgets/expanding_header_search.dart';
import '../../playlists/widgets/playlist_management_menu.dart';
import '../shell_route_utils.dart';
import 'library_view_menu.dart';
import 'scrolling_page_header.dart';
import 'settings_header_surface.dart';

const double _songsHeaderActionGap = 12;

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
        return _FloatingHeaderBackdrop(height: top + 80, child: header);
      }
      return header;
    }

    if (location.startsWith('/settings') || location == '/debug') {
      return SizedBox(
        height: top + 72,
        child: SettingsHeaderSurface(
          child: prism.TonalButtonTheme(
            glass: prism.LiquidGlassScope.of(context),
            child: prism.AppBar(
              title: Text(headerTitle),
              titleTextStyle: parentLocation == null
                  ? prism.AppTextStyle.pageTitle.of(context)
                  : prism.AppTextStyle.headline.of(context),
              titleSpacing: parentLocation == null ? null : 0,
              leading: parentLocation == null
                  ? null
                  : Center(
                      child: AppNavigationButton.back(
                        onPressed: () {
                          if (context.canPop()) {
                            context.pop();
                          } else {
                            context.go(parentLocation);
                          }
                        },
                      ),
                    ),
            ),
          ),
        ),
      );
    }

    return ShellSectionHeader(
      title: headerTitle,
      scrollOffset: scrollOffset,
      floating: floating,
      compact: compact,
      trailing: location == '/playlists'
          ? const PlaylistManagementMenu()
          : null,
      fontSize: onlineCollectionDetail ? 18 : (compact ? 22 : null),
      leading: parentLocation != null || location == '/playlists/import'
          ? AppNavigationButton.back(
              onPressed: () {
                if (parentLocation != null) {
                  context.go(parentLocation);
                } else if (context.canPop()) {
                  context.pop();
                } else {
                  context.go(playlistBackLocation);
                }
              },
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
                  SizedBox.square(dimension: 48, child: Center(child: leading)),
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
                ?trailing,
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
      return SizedBox(
        key: const ValueKey('songs-header-batch'),
        height: 44,
        child: Row(
          children: [
            AppNavigationButton.back(
              tooltip: '退出批量管理',
              onPressed: state.onToggleBatch,
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: AppMotion.short,
                child: Text(
                  '已选中 ${state.selectedCount} 项',
                  key: ValueKey(state.selectedCount),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: title.style,
                ),
              ),
            ),
            if (state.hasSongs)
              _SongsHeaderGlyphButton(
                tooltip: state.allSelected ? '取消全选' : '全选',
                glyph: state.allSelected
                    ? prism_glyphs.AppGlyphs.deselect
                    : prism_glyphs.AppGlyphs.selectAll,
                onPressed: state.onToggleSelectAll,
              ),
          ],
        ),
      );
    }

    final controller = state.searchController;
    final focusNode = state.searchFocusNode;
    final hasInlineSearch = controller != null && focusNode != null;
    final overflow = _LibraryOverflowMenu(
      onOpenHistory: state.onOpenHistory,
      onShuffle: state.hasSongs ? state.onShuffle : null,
      onUpdatePlaylist: state.onUpdatePlaylist,
      updatingPlaylist: state.updatingPlaylist,
    );
    final closedBar = Row(
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
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
        ),
        const SizedBox(width: _songsHeaderActionGap),
        _SongsHeaderIconButton(
          tooltip: '歌单管理',
          icon: Icons.queue_music_rounded,
          onPressed: state.onOpenPlaylists,
        ),
        const SizedBox(width: _songsHeaderActionGap),
        // The inline search is painted above this row. Reserve its closed
        // button width so long titles cannot push playlist management under it.
        if (hasInlineSearch)
          SizedBox(width: prism.TonalButtonSize.bar.button)
        else
          _SongsHeaderIconButton(
            tooltip: state.searchLabel,
            icon: Icons.search_rounded,
            onPressed: state.onSearch,
          ),
        const SizedBox(width: _songsHeaderActionGap),
        overflow,
      ],
    );

    if (!hasInlineSearch) {
      return SizedBox(
        key: const ValueKey('songs-header-normal'),
        height: 44,
        child: closedBar,
      );
    }

    return SizedBox(
      key: const ValueKey('songs-header-normal'),
      height: 44,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Prism UI fades the covered app-bar content out of the search layer
          // and removes it from hit testing while the field owns the toolbar.
          AnimatedOpacity(
            opacity: state.searchMode ? 0 : 1,
            duration: AppMotion.short,
            curve: AppMotion.emphasized,
            child: IgnorePointer(
              ignoring: state.searchMode,
              child: ExcludeSemantics(
                excluding: state.searchMode,
                child: closedBar,
              ),
            ),
          ),
          Positioned.fill(
            child: ExpandingHeaderSearch(
              title: state.libraryTitle,
              hint: '搜索',
              collapsedContent: const SizedBox.shrink(),
              closedEndInset:
                  _songsHeaderActionGap + prism.TonalButtonSize.bar.button,
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
    return prism.TonalButtonTheme(
      size: prism.TonalButtonSize.bar,
      glass: prism.LiquidGlassScope.of(context),
      child: prism.ElasticPress(
        enabled: onPressed != null,
        child: prism.IconButton(
          tooltip: tooltip,
          onPressed: onPressed,
          style: headerControlButtonStyle(context),
          icon: Icon(icon, size: prism.TonalButtonSize.bar.icon),
        ),
      ),
    );
  }
}

class _SongsHeaderGlyphButton extends StatelessWidget {
  const _SongsHeaderGlyphButton({
    required this.tooltip,
    required this.glyph,
    required this.onPressed,
  });

  final String tooltip;
  final prism_glyph.Glyph glyph;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return prism.TonalButtonTheme(
      size: prism.TonalButtonSize.bar,
      glass: prism.LiquidGlassScope.of(context),
      child: prism.ElasticPress(
        child: prism.IconButton(
          tooltip: tooltip,
          onPressed: onPressed,
          icon: prism_glyph.GlyphIcon(
            glyph,
            size: prism.TonalButtonSize.bar.icon,
          ),
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
    final glass = prism.LiquidGlassScope.of(context);
    return prism.PopupAnchor(
      key: const ValueKey('songs-overflow-menu'),
      targetBuilder: (open) => prism.TonalButtonTheme(
        size: prism.TonalButtonSize.bar,
        glass: glass,
        child: prism.IconButton(
          tooltip: '更多歌曲操作',
          style: const prism.ButtonStyle(
            shape: CircleBorder(),
            tapTargetSize: prism.TapTargetSize.padded,
          ).merge(headerControlButtonStyle(context)),
          onPressed: open,
          icon: const glyph.GlyphIcon(glyph.Glyphs.more),
        ),
      ),
      popupBuilder: (_) => prism.PopupMenu(
        items: [
          prism.PopupMenuItem(
            label: '随机播放',
            glyph: prism_glyphs.AppGlyphs.shuffle,
            executeImmediately: true,
            onPressed: onShuffle,
          ),
          if (onUpdatePlaylist != null)
            prism.PopupMenuItem(
              label: updatingPlaylist ? '正在更新' : '更新歌单',
              glyph: prism_glyphs.AppGlyphs.refresh,
              executeImmediately: true,
              onPressed: updatingPlaylist ? null : onUpdatePlaylist,
            ),
          prism.PopupMenuItem(
            label: '下载历史',
            glyph: prism_glyphs.AppGlyphs.clock,
            executeImmediately: true,
            onPressed: onOpenHistory ?? () => context.go('/downloads'),
          ),
        ],
      ),
    );
  }
}
