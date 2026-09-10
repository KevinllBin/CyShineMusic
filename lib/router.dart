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
import 'features/playlists/online_playlist_import_page.dart';
import 'features/playlists/playlist_detail_page.dart';
import 'features/playlists/playlist_management_page.dart';
import 'features/search/search_page.dart';
import 'features/settings/settings_page.dart';
import 'features/settings/webdav_sync_page.dart';
import 'features/music_sources/music_source_page.dart';
import 'features/shell/app_shell.dart';
import 'features/shell/shell_page_storage.dart';
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
  return GoRouter(
    navigatorKey: navigatorKey,
    initialLocation: initialLocation,
    routes: [
      ShellRoute(
        builder: (context, state, child) {
          return AppShell(
            location: state.uri.path,
            routeLocation: state.uri.toString(),
            playerReturnLocation: _playerReturnLocationFromExtra(state.extra),
            playlistBackLocation: _playlistBackLocationFromUri(state.uri),
            child: child,
          );
        },
        routes: [
          GoRoute(
            path: '/',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: ShellPageStorage(child: SearchPage()),
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
                child: ShellPageStorage(
                  child: OnlinePlaylistDetailPage(
                    source: source == null || source == MusicSource.all
                        ? MusicSource.kw
                        : source,
                    playlistId: id,
                    summary: _routePayload<PlaylistSummary>(state.extra),
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
                child: ShellPageStorage(
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
              final resolvedSource = source == null || source == MusicSource.all
                  ? MusicSource.kw
                  : source;
              final id = state.pathParameters['id'] ?? '';
              final board = _routePayload<LeaderboardSummary>(state.extra);
              return _containerTransformPage(
                context,
                key: state.pageKey,
                extra: state.extra,
                child: ShellPageStorage(
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
          GoRoute(
            path: '/downloads',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: ShellPageStorage(child: DownloadHistoryPage()),
            ),
          ),
          GoRoute(
            path: '/player',
            // The player itself is hosted by AppShell as a drag-driven layer
            // above the route content, so entering and leaving `/player` never
            // remounts it. The route only carries the location and its
            // `extra` return target; see AppShell's player pull layer.
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: SizedBox.shrink()),
          ),
          GoRoute(path: '/history', redirect: (_, _) => '/downloads'),
          GoRoute(
            path: '/songs',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: ShellPageStorage(child: SongsPage()),
            ),
          ),
          GoRoute(
            path: '/songs/search',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: ShellPageStorage(child: SongsPage(searchMode: true)),
            ),
          ),
          GoRoute(
            path: '/playlists',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: ShellPageStorage(child: PlaylistManagementPage()),
            ),
          ),
          GoRoute(
            path: '/playlists/import',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: ShellPageStorage(child: OnlinePlaylistImportPage()),
            ),
          ),
          GoRoute(
            path: '/playlists/:id',
            pageBuilder: (context, state) => NoTransitionPage(
              child: ShellPageStorage(
                child: PlaylistDetailPage(
                  playlistId: state.pathParameters['id'] ?? '',
                  returnLocation: state.uri.toString(),
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/settings',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: ShellPageStorage(child: SettingsPage()),
            ),
          ),
          GoRoute(
            path: '/settings/sources',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: ShellPageStorage(child: MusicSourcePage()),
            ),
          ),
          GoRoute(
            path: '/settings/webdav',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: ShellPageStorage(child: WebDavSyncPage()),
            ),
          ),
          GoRoute(
            path: '/settings/equalizer',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: ShellPageStorage(child: EqualizerPage()),
            ),
          ),
          GoRoute(
            path: '/debug',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: ShellPageStorage(child: DebugLogPage()),
            ),
          ),
        ],
      ),
    ],
  );
}

/// 发现页卡片 → 歌单/榜单详情：页面从被点击的卡片矩形展开（M3 container
/// transform），封面 Hero 沿同一条曲线飞到头图；返回时原路收回。起点随
/// extra 传入，没有起点（深链、预览弹窗）时退化为整页淡入。
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
    transitionDuration: reduceMotion ? Duration.zero : AppMotion.long,
    reverseTransitionDuration: reduceMotion ? Duration.zero : AppMotion.medium,
    transitionsBuilder: (_, animation, _, child) =>
        ContainerTransformTransition(
          animation: animation,
          origin: origin,
          child: child,
        ),
    child: child,
  );
}

/// 发现页「查看全部」→ 排行榜列表：整页淡入并轻微上浮，返回时淡出。
/// AppShell 对发现区各路由之间不做切换动画，这里的过渡是唯一的。
CustomTransitionPage<void> _fadeThroughPage(
  BuildContext context, {
  required LocalKey key,
  required Widget child,
}) {
  final reduceMotion = MediaQuery.disableAnimationsOf(context);
  return CustomTransitionPage<void>(
    key: key,
    transitionDuration: reduceMotion ? Duration.zero : AppMotion.medium,
    reverseTransitionDuration: reduceMotion ? Duration.zero : AppMotion.short,
    transitionsBuilder: (_, animation, _, child) {
      final eased = animation.drive(CurveTween(curve: AppMotion.emphasized));
      return FadeTransition(
        opacity: eased,
        child: SlideTransition(
          position: eased.drive(
            Tween<Offset>(begin: const Offset(0, 0.03), end: Offset.zero),
          ),
          child: child,
        ),
      );
    },
    child: child,
  );
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
  if (extra is String && _isPlayerReturnLocation(extra)) return extra;
  return '/songs';
}

bool _isPlayerReturnLocation(String location) {
  if (location.startsWith('/discover/playlists/') ||
      location.startsWith('/discover/leaderboards/')) {
    return true;
  }
  if (location == '/playlists' || location.startsWith('/playlists/')) {
    return true;
  }
  return switch (location) {
    '/' ||
    '/downloads' ||
    '/songs' ||
    '/songs/search' ||
    '/settings' ||
    '/settings/sources' ||
    '/settings/webdav' ||
    '/settings/equalizer' ||
    '/debug' => true,
    _ => false,
  };
}

String _playlistBackLocationFromUri(Uri uri) {
  if (uri.path == '/playlists/import') return '/playlists';
  if (uri.path.startsWith('/playlists/') &&
      uri.queryParameters['from'] == 'manage') {
    return '/playlists';
  }
  return '/songs';
}
