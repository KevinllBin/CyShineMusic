import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'features/debug/debug_log_page.dart';
import 'features/discovery/leaderboards_page.dart';
import 'features/discovery/online_playlist_detail_page.dart';
import 'features/downloads/download_history_page.dart';
import 'features/equalizer/equalizer_page.dart';
import 'core/models/enums.dart';
import 'core/models/leaderboard_info.dart';
import 'core/models/online_collection_kind.dart';
import 'core/models/playlist_summary.dart';
import 'core/ui/container_transform.dart';
import 'core/ui/skippable_exit_transition.dart';
import 'features/playlists/online_playlist_import_page.dart';
import 'features/playlists/playlist_detail_page.dart';
import 'features/playlists/playlist_management_page.dart';
import 'features/search/search_page.dart';
import 'features/settings/settings_page.dart';
import 'features/settings/webdav_sync_page.dart';
import 'features/music_sources/music_source_page.dart';
import 'features/shell/app_shell.dart';
import 'features/shell/player_pull_scope.dart';
import 'features/shell/shell_navigation.dart';
import 'features/shell/shell_page_storage.dart';
import 'features/shell/shell_page_frame.dart';
import 'features/shell/shell_route_utils.dart';
import 'features/songs/songs_page.dart';
import 'theme/app_motion.dart';

// Exposed so app-level overlays (e.g. the startup permission dialog) can find
// a stable BuildContext after the router mounts.
final rootNavigatorKey = GlobalKey<NavigatorState>();

final appRouter = createAppRouter(navigatorKey: rootNavigatorKey);

GoRouter createAppRouter({
  String initialLocation = '/',
  GlobalKey<NavigatorState>? navigatorKey,
}) {
  GoRouter.optionURLReflectsImperativeAPIs = true;
  final tabShellKey = GlobalKey<StatefulNavigationShellState>();
  return GoRouter(
    navigatorKey: navigatorKey,
    initialLocation: initialLocation,
    routes: [
      ShellRoute(
        builder: (context, state, child) {
          return ShellTabNavigationScope(
            navigationKey: tabShellKey,
            child: AppShell(
              location: state.uri.path,
              routeLocation: state.uri.toString(),
              playerReturnLocation: _playerReturnLocationFromExtra(state.extra),
              playlistBackLocation: _playlistBackLocationFromUri(state.uri),
              child: child,
            ),
          );
        },
        routes: [
          StatefulShellRoute.indexedStack(
            key: tabShellKey,
            builder: (context, state, navigationShell) => navigationShell,
            branches: [
              StatefulShellBranch(
                initialLocation: '/',
                routes: [
                  GoRoute(
                    path: '/',
                    pageBuilder: (context, state) => NoTransitionPage(
                      child: _shellPageContent(
                        state,
                        child: const SearchPage(),
                      ),
                    ),
                  ),
                  GoRoute(
                    path: '/discover/playlists/:source/:id',
                    pageBuilder: (context, state) {
                      final source = MusicSource.tryFromCode(
                        state.pathParameters['source'] ?? '',
                      );
                      final id = state.pathParameters['id'] ?? '';
                      return _containerTransformPage(
                        context,
                        key: state.pageKey,
                        extra: state.extra,
                        child: _shellPageContent(
                          state,
                          child: OnlinePlaylistDetailPage(
                            source: source == null || source == MusicSource.all
                                ? MusicSource.kw
                                : source,
                            playlistId: id,
                            summary: _routePayload<PlaylistSummary>(
                              state.extra,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  GoRoute(
                    path: '/discover/leaderboards/:source',
                    pageBuilder: (context, state) {
                      final source = MusicSource.tryFromCode(
                        state.pathParameters['source'] ?? '',
                      );
                      return _fadeThroughPage(
                        context,
                        key: state.pageKey,
                        extra: state.extra,
                        child: _shellPageContent(
                          state,
                          child: LeaderboardsPage(
                            source: source == null || source == MusicSource.all
                                ? MusicSource.kw
                                : source,
                          ),
                        ),
                      );
                    },
                  ),
                  GoRoute(
                    path: '/discover/leaderboards/:source/:id',
                    pageBuilder: (context, state) {
                      final source = MusicSource.tryFromCode(
                        state.pathParameters['source'] ?? '',
                      );
                      final resolvedSource =
                          source == null || source == MusicSource.all
                          ? MusicSource.kw
                          : source;
                      final id = state.pathParameters['id'] ?? '';
                      final board = _routePayload<LeaderboardSummary>(
                        state.extra,
                      );
                      return _containerTransformPage(
                        context,
                        key: state.pageKey,
                        extra: state.extra,
                        child: _shellPageContent(
                          state,
                          child: OnlinePlaylistDetailPage(
                            source: resolvedSource,
                            playlistId: id,
                            kind: OnlineCollectionKind.leaderboard,
                            summary: board == null
                                ? null
                                : PlaylistSummary(
                                    id: board.boardId,
                                    name: board.name,
                                    source: board.source,
                                    coverUrl: board.coverUrl,
                                  ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
              StatefulShellBranch(
                initialLocation: '/songs',
                routes: [
                  GoRoute(
                    path: '/downloads',
                    pageBuilder: (context, state) => NoTransitionPage(
                      child: _shellPageContent(
                        state,
                        child: const DownloadHistoryPage(),
                      ),
                    ),
                  ),
                  GoRoute(path: '/history', redirect: (_, _) => '/downloads'),
                  GoRoute(
                    path: '/songs',
                    pageBuilder: (context, state) => NoTransitionPage(
                      child: _shellPageContent(state, child: const SongsPage()),
                    ),
                  ),
                  GoRoute(
                    path: '/songs/search',
                    pageBuilder: (context, state) => NoTransitionPage(
                      child: _shellPageContent(
                        state,
                        child: const SongsPage(searchMode: true),
                      ),
                    ),
                  ),
                  GoRoute(
                    path: '/playlists',
                    pageBuilder: (context, state) => NoTransitionPage(
                      child: _shellPageContent(
                        state,
                        child: const PlaylistManagementPage(),
                      ),
                    ),
                  ),
                  GoRoute(
                    path: '/playlists/import',
                    pageBuilder: (context, state) => NoTransitionPage(
                      child: _shellPageContent(
                        state,
                        child: const OnlinePlaylistImportPage(),
                      ),
                    ),
                  ),
                  GoRoute(
                    path: '/playlists/:id',
                    pageBuilder: (context, state) => NoTransitionPage(
                      child: _shellPageContent(
                        state,
                        child: PlaylistDetailPage(
                          playlistId: state.pathParameters['id'] ?? '',
                          returnLocation: state.uri.toString(),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              StatefulShellBranch(
                initialLocation: '/settings',
                routes: [
                  GoRoute(
                    path: '/settings',
                    pageBuilder: (context, state) => NoTransitionPage(
                      child: _shellPageContent(
                        state,
                        child: const SettingsPage(),
                      ),
                    ),
                  ),
                  GoRoute(
                    path: '/settings/sources',
                    pageBuilder: (context, state) => NoTransitionPage(
                      child: _shellPageContent(
                        state,
                        child: const MusicSourcePage(),
                      ),
                    ),
                  ),
                  GoRoute(
                    path: '/settings/webdav',
                    pageBuilder: (context, state) => NoTransitionPage(
                      child: _shellPageContent(
                        state,
                        child: const WebDavSyncPage(),
                      ),
                    ),
                  ),
                  GoRoute(
                    path: '/settings/equalizer',
                    pageBuilder: (context, state) => NoTransitionPage(
                      child: _shellPageContent(
                        state,
                        child: const EqualizerPage(),
                      ),
                    ),
                  ),
                  GoRoute(
                    path: '/debug',
                    pageBuilder: (context, state) => NoTransitionPage(
                      child: _shellPageContent(
                        state,
                        child: const DebugLogPage(),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          GoRoute(
            path: '/player',
            // The player overlays all three retained tab navigators.
            pageBuilder: (context, state) => CustomTransitionPage<void>(
              opaque: false,
              transitionDuration: Duration.zero,
              reverseTransitionDuration: Duration.zero,
              transitionsBuilder: (_, animation, secondaryAnimation, child) =>
                  child,
              child: const _PlayerRouteBackdrop(),
            ),
          ),
        ],
      ),
    ],
  );
}

Widget _shellPageContent(GoRouterState state, {required Widget child}) {
  return ShellPageFrame(
    location: state.matchedLocation,
    playlistBackLocation: _playlistBackLocationFromUri(state.uri),
    child: ShellPageStorage(child: child),
  );
}

class _PlayerRouteBackdrop extends StatelessWidget {
  const _PlayerRouteBackdrop();
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) PlayerPullScope.maybeOf(context)?.onClose();
    },
    child: const SizedBox.shrink(),
  );
}

/// 发现页卡片 → 歌单/榜单详情：页面从被点击的卡片矩形展开（M3 container
/// transform），封面 Hero 沿同一条曲线飞到头图；返回时原路收回。起点随
/// extra 传入，没有起点（深链、预览弹窗）时退化为整页淡入；从别的 tab
/// 切回（[ShellTabSwitch]）时直接出现。
///
/// 路由时长同时驱动页面容器与封面 Hero，两者共用 [AppMotion.long] /
/// [AppMotion.medium]。
CustomTransitionPage<void> _containerTransformPage(
  BuildContext context, {
  required LocalKey key,
  required Object? extra,
  required Widget child,
}) {
  final reduceMotion = MediaQuery.disableAnimationsOf(context);
  final origin = extra is ContainerTransformExtra ? extra.origin : null;
  return CustomTransitionPage<void>(
    key: key,
    transitionDuration: reduceMotion || extra is ShellTabSwitch
        ? Duration.zero
        : AppMotion.long,
    reverseTransitionDuration: reduceMotion ? Duration.zero : AppMotion.medium,
    transitionsBuilder: (_, animation, _, child) => SkippableExitTransition(
      animation: animation,
      skipExit: _leavesDiscovery,
      child: ContainerTransformTransition(
        animation: animation,
        origin: origin,
        child: child,
      ),
    ),
    child: child,
  );
}

/// 发现页「查看全部」→ 排行榜列表：整页淡入并轻微上浮，返回时淡出；从别的
/// tab 切回（[ShellTabSwitch]）时直接出现。
/// AppShell 对发现区各路由之间不做切换动画，这里的过渡是唯一的。
CustomTransitionPage<void> _fadeThroughPage(
  BuildContext context, {
  required LocalKey key,
  required Object? extra,
  required Widget child,
}) {
  final reduceMotion = MediaQuery.disableAnimationsOf(context);
  return CustomTransitionPage<void>(
    key: key,
    transitionDuration: reduceMotion || extra is ShellTabSwitch
        ? Duration.zero
        : AppMotion.medium,
    reverseTransitionDuration: reduceMotion ? Duration.zero : AppMotion.short,
    transitionsBuilder: (_, animation, _, child) {
      final eased = animation.drive(CurveTween(curve: AppMotion.emphasized));
      return SkippableExitTransition(
        animation: animation,
        skipExit: _leavesDiscovery,
        child: FadeTransition(
          opacity: eased,
          child: SlideTransition(
            position: eased.drive(
              Tween<Offset>(begin: const Offset(0, 0.03), end: Offset.zero),
            ),
            child: child,
          ),
        ),
      );
    },
    child: child,
  );
}

/// 发现区页面退场时，新位置已不在发现区（切到了别的 tab）：这是整体替换
/// 而不是返回，直接隐藏，不播放收回动画——新 tab 由 AppShell 自己过渡。
/// 系统返回键 pop 时 GoRouter 尚未更新位置，仍在发现区，照常收回。
bool _leavesDiscovery(BuildContext context) {
  final location = GoRouter.of(context).routerDelegate.currentConfiguration;
  return !isDiscoveryLocation(location.uri.path);
}

/// 路由 extra 既可能是裸的业务对象，也可能包在 [ContainerTransformExtra] 里。
T? _routePayload<T extends Object>(Object? extra) {
  return switch (extra) {
    T payload => payload,
    ContainerTransformExtra(payload: T payload) => payload,
    _ => null,
  };
}

String _playerReturnLocationFromExtra(Object? extra) {
  if (extra is String && isPlayerReturnLocation(extra)) return extra;
  return '/songs';
}

String _playlistBackLocationFromUri(Uri uri) {
  if (uri.path == '/playlists/import') return '/playlists';
  if (uri.path.startsWith('/playlists/') &&
      uri.queryParameters['from'] == 'manage') {
    return '/playlists';
  }
  return '/songs';
}
