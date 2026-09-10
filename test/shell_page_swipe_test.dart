import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cy_shine_music/core/api/music_api.dart';
import 'package:cy_shine_music/core/models/enums.dart';
import 'package:cy_shine_music/core/models/music_info.dart';
import 'package:cy_shine_music/core/models/playlist_summary.dart';
import 'package:cy_shine_music/core/models/search_response.dart';
import 'package:cy_shine_music/core/storage/settings_store.dart';
import 'package:cy_shine_music/features/discovery/discovery_controller.dart';
import 'package:cy_shine_music/features/player/player_audio_handler.dart';
import 'package:cy_shine_music/features/player/player_controller.dart';
import 'package:cy_shine_music/features/search/search_controller.dart';
import 'package:cy_shine_music/features/shell/app_shell.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('page swipes keep the current route at discovery boundaries', (
    tester,
  ) async {
    final harness = await _pumpSwipeApp(tester);
    for (final source in [MusicSource.kw, MusicSource.mg]) {
      harness.container.read(selectedDiscoverySourceProvider.notifier).state =
          source;
      await tester.pump();
      for (final offset in [const Offset(-150, 0), const Offset(150, 0)]) {
        await _dragPage(tester, '/', offset);
        expect(harness.location, '/');
        expect(harness.container.read(selectedDiscoverySourceProvider), source);
      }
    }
    for (final location in ['/songs', '/songs/search', '/settings']) {
      harness.router.go(location);
      await _pumpUi(tester);
      for (final offset in [const Offset(-150, 0), const Offset(150, 0)]) {
        await _dragPage(tester, location, offset);
        expect(harness.location, location);
      }
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('active search swipes keep the selected source and route', (
    tester,
  ) async {
    final harness = await _pumpSwipeApp(tester);
    unawaited(
      harness.container
          .read(searchControllerProvider.notifier)
          .search(keyword: '滑动测试'),
    );
    await _pumpUi(tester);
    for (final source in [MusicSource.kw, MusicSource.wy]) {
      harness.container
          .read(searchControllerProvider.notifier)
          .setSource(source);
      await _pumpUi(tester);
      for (final offset in [const Offset(-150, 0), const Offset(150, 0)]) {
        await _dragPage(tester, '/', offset);
        expect(harness.container.read(searchControllerProvider).source, source);
        expect(harness.location, '/');
      }
    }
    expect(tester.takeException(), isNull);
  });
}

class _SwipeHarness {
  const _SwipeHarness({required this.container, required this.router});

  final ProviderContainer container;
  final GoRouter router;

  String get location => router.routeInformationProvider.value.uri.path;
}

class _SwipeMusicApi extends MusicApi {
  @override
  Future<List<PlaylistSummary>> featuredPlaylists({
    required MusicSource source,
    int page = 1,
    int limit = 20,
    String? categoryId,
  }) async {
    return [PlaylistSummary(id: '1', name: '测试歌单', source: source)];
  }

  @override
  Future<SearchResponse> searchMusic({
    required String keyword,
    required MusicSource source,
    int page = 1,
    int limit = 30,
  }) async {
    return SearchResponse(
      list: [_music(source)],
      page: page,
      limit: limit,
      allPage: page + 1,
      total: 1,
      source: source,
    );
  }

  @override
  Future<List<String>> searchTip({
    required String keyword,
    required MusicSource source,
    int limit = 8,
  }) async => const [];
}

class _IdlePlayerController extends PlayerController {
  _IdlePlayerController(super.ref) {
    state = const PlayerState();
  }
}

Future<_SwipeHarness> _pumpSwipeApp(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  });

  final preferences = await SharedPreferences.getInstance();
  final audioHandler = PlayerAudioHandler();
  final router = _createSwipeRouter();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(preferences),
      musicApiProvider.overrideWithValue(_SwipeMusicApi()),
      playerAudioHandlerProvider.overrideWithValue(audioHandler),
      playerControllerProvider.overrideWith(_IdlePlayerController.new),
    ],
  );
  addTearDown(router.dispose);
  addTearDown(container.dispose);
  addTearDown(() => unawaited(audioHandler.disposeHandler()));

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        ),
        routerConfig: router,
      ),
    ),
  );
  await _pumpUi(tester);
  return _SwipeHarness(container: container, router: router);
}

GoRouter _createSwipeRouter() {
  return GoRouter(
    routes: [
      ShellRoute(
        builder: (context, state, child) => AppShell(
          location: state.uri.path,
          routeLocation: state.uri.toString(),
          playerReturnLocation: '/songs',
          playlistBackLocation: '/playlists',
          child: child,
        ),
        routes: [
          for (final path in const [
            '/',
            '/songs',
            '/songs/search',
            '/settings',
          ])
            GoRoute(
              path: path,
              pageBuilder: (context, state) => NoTransitionPage<void>(
                child: ColoredBox(
                  key: ValueKey('swipe-route-$path'),
                  color: Colors.transparent,
                ),
              ),
            ),
        ],
      ),
    ],
  );
}

Future<void> _dragPage(
  WidgetTester tester,
  String location,
  Offset offset,
) async {
  await tester.drag(find.byKey(ValueKey('swipe-route-$location')), offset);
  await _pumpUi(tester);
}

Future<void> _pumpUi(WidgetTester tester) async {
  for (var index = 0; index < 12; index++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

MusicInfo _music(MusicSource source) {
  return MusicInfo.fromJson({
    'id': '${source.code}_swipe-test',
    'name': '滑动测试歌曲',
    'singer': '测试歌手',
    'source': source.code,
    'interval': '03:20',
    'meta': {
      'songId': 'swipe-test',
      'albumName': '测试专辑',
      'qualitys': [
        {'type': Quality.k320.code, 'size': '8.00M'},
      ],
    },
  });
}
