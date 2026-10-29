import 'dart:async';

import 'package:flutter/material.dart' hide SearchController;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cy_shine_music/core/models/enums.dart';
import 'package:cy_shine_music/core/models/music_info.dart';
import 'package:cy_shine_music/core/models/search_response.dart';
import 'package:cy_shine_music/core/models/search_category.dart';
import 'package:cy_shine_music/core/storage/settings_store.dart';
import 'package:cy_shine_music/core/ui/app_toast.dart';
import 'package:cy_shine_music/features/player/player_audio_handler.dart';
import 'package:cy_shine_music/features/playlists/playlist_store.dart';
import 'package:cy_shine_music/features/search/search_controller.dart';
import 'package:cy_shine_music/features/search/search_page.dart';
import 'package:cy_shine_music/features/search/search_toolbar_state.dart';
import 'package:cy_shine_music/features/search/widgets/search_result_tile.dart';
import 'package:cy_shine_music/features/songs/widgets/song_actions_menu.dart';
import 'package:cy_shine_music/router.dart';
import 'package:cy_shine_music/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('app theme uses the platform system font', () {
    for (final theme in [AppTheme.light(), AppTheme.dark()]) {
      final families = [
        theme.textTheme.bodyMedium?.fontFamily,
        theme.textTheme.titleLarge?.fontFamily,
      ];
      expect(families, isNot(contains('Plus Jakarta Sans')));
      expect(families, isNot(contains('Manrope')));
    }
  });

  testWidgets(
    'search results show nine rows above the shell toolbar with compact actions',
    (tester) async {
      await _usePhoneViewport(tester);
      final prefs = await SharedPreferences.getInstance();
      final audioHandler = PlayerAudioHandler();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          searchControllerProvider.overrideWith(_TestSearchController.new),
          playerAudioHandlerProvider.overrideWithValue(audioHandler),
        ],
      );
      final router = createAppRouter(initialLocation: '/');
      addTearDown(() {
        router.dispose();
        container.dispose();
        unawaited(audioHandler.disposeHandler());
      });

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            debugShowCheckedModeBanner: false,
            theme: _testTheme(),
            routerConfig: router,
          ),
        ),
      );
      await _pumpUi(tester);

      final toolbarActionTop = tester.getTopLeft(find.byTooltip('发现')).dy;
      final fullyVisibleRows = find
          .byType(SearchResultTile)
          .evaluate()
          .map(_globalRect)
          .where((rect) => rect.top >= 0 && rect.bottom <= toolbarActionTop)
          .length;
      expect(fullyVisibleRows, 9);

      final firstTile = find.byType(SearchResultTile).first;
      expect(tester.getSize(firstTile).height, 62);
      final actionsMenu = find.byKey(
        const ValueKey('search-result-menu-page-1-song-01'),
      );
      expect(actionsMenu, findsOneWidget);
      expect(tester.getSize(actionsMenu), const Size.square(44));
      await tester.tap(actionsMenu);
      await _pumpUi(tester);
      expect(find.text('下载'), findsOneWidget);
      expect(find.text('添加到歌单'), findsOneWidget);
      await tester.tapAt(const Offset(4, 4));
      await _pumpUi(tester);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'search result adds online music to a playlist and deduplicates',
    (tester) async {
      await _usePhoneViewport(tester);
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          searchControllerProvider.overrideWith(_TestSearchController.new),
        ],
      );
      addTearDown(container.dispose);
      final playlist = await container
          .read(localPlaylistsProvider.notifier)
          .create('Online favorites');

      await tester.pumpWidget(
        _testAppWithContainer(container, const SearchPage()),
      );
      await _pumpUi(tester);

      final actionsMenu = find.byKey(
        const ValueKey('search-result-menu-page-1-song-01'),
      );
      await tester.tap(actionsMenu);
      await _pumpUi(tester);
      await tester.tap(find.text('添加到歌单'));
      await _pumpUi(tester);
      expect(find.text('添加歌曲到'), findsOneWidget);

      await tester.tap(find.text('Online favorites'));
      await _pumpUi(tester);

      var stored = container
          .read(localPlaylistsProvider)
          .singleWhere((item) => item.id == playlist.id);
      expect(stored.tracks, hasLength(1));
      final track = stored.tracks.single;
      expect(track.musicId, 'page-1-song-01');
      expect(track.source, MusicSource.wy);
      expect(track.localPath, isNull);
      expect(track.musicInfo?.id, 'page-1-song-01');
      expect(find.text('已添加到「Online favorites」'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));

      await tester.tap(actionsMenu);
      await _pumpUi(tester);
      await tester.tap(find.text('添加到歌单'));
      await _pumpUi(tester);
      expect(find.text('添加歌曲到'), findsOneWidget);
      await tester.tap(find.text('Online favorites'));
      await _pumpUi(tester);

      stored = container
          .read(localPlaylistsProvider)
          .singleWhere((item) => item.id == playlist.id);
      expect(stored.tracks, hasLength(1));
      expect(find.text('歌曲已在「Online favorites」中'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 4));
    },
  );

  testWidgets(
    'tablet enlarges toolbar and moves paging FAB clear of song menus',
    (tester) async {
      await _usePhoneViewport(tester, size: const Size(1280, 800));
      final prefs = await SharedPreferences.getInstance();
      final audioHandler = PlayerAudioHandler();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          searchControllerProvider.overrideWith(_TestSearchController.new),
          playerAudioHandlerProvider.overrideWithValue(audioHandler),
        ],
      );
      final router = createAppRouter(initialLocation: '/');
      addTearDown(() {
        router.dispose();
        container.dispose();
        unawaited(audioHandler.disposeHandler());
      });

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            debugShowCheckedModeBanner: false,
            theme: _testTheme(),
            routerConfig: router,
          ),
        ),
      );
      await _pumpUi(tester);

      expect(tester.getSize(find.byTooltip('发现')), const Size(96, 60));
      final fabRect = tester.getRect(find.byType(FloatingActionButton));
      final menuRect = tester.getRect(find.byType(SongActionsMenu).last);
      expect(fabRect.right, lessThan(menuRect.left));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('previous and next page callbacks reset search results to top', (
    tester,
  ) async {
    await _usePhoneViewport(tester);
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        searchControllerProvider.overrideWith(_TestSearchController.new),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      _testAppWithContainer(container, const SearchPage()),
    );
    await _pumpUi(tester);

    final listFinder = find.byType(ListView);
    final scrollableFinder = find.descendant(
      of: listFinder,
      matching: find.byType(Scrollable),
    );
    final position = tester.state<ScrollableState>(scrollableFinder).position;

    position.jumpTo(position.maxScrollExtent);
    await tester.pump();
    expect(position.pixels, greaterThan(0));

    container.read(searchToolbarStateProvider).onNext!();
    await _pumpUi(tester);
    expect(container.read(searchControllerProvider).page, 2);
    expect(position.pixels, position.minScrollExtent);
    expect(find.text('Page 2 song 01'), findsOneWidget);

    position.jumpTo(position.maxScrollExtent);
    await tester.pump();
    expect(position.pixels, greaterThan(0));

    container.read(searchToolbarStateProvider).onPrev!();
    await _pumpUi(tester);
    expect(container.read(searchControllerProvider).page, 1);
    expect(position.pixels, position.minScrollExtent);
    expect(find.text('Page 1 song 01'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('starting another search dismisses the previous search error', (
    tester,
  ) async {
    await _usePhoneViewport(tester);
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        searchControllerProvider.overrideWith(_ErrorSearchController.new),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      _testAppWithContainer(container, const SearchPage()),
    );
    await _pumpUi(tester);
    expect(
      find.byKey(const ValueKey('app-toast-root-overlay')),
      findsOneWidget,
    );

    final controller =
        container.read(searchControllerProvider.notifier)
            as _ErrorSearchController;
    controller.fail('TX 搜索暂时受限');
    expect(container.read(searchControllerProvider).error, 'TX 搜索暂时受限');
    await tester.pump();
    await tester.pumpAndSettle();
    expect(container.read(searchControllerProvider).error, 'TX 搜索暂时受限');
    expect(find.text('TX 搜索暂时受限'), findsOneWidget);
    expect(find.byKey(const ValueKey('app-toast-capsule')), findsOneWidget);

    controller.startRetry();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.text('TX 搜索暂时受限'), findsNothing);
    expect(find.byKey(const ValueKey('app-toast-capsule')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Rect _globalRect(Element element) {
  final renderBox = element.renderObject! as RenderBox;
  return renderBox.localToGlobal(Offset.zero) & renderBox.size;
}

Future<void> _usePhoneViewport(
  WidgetTester tester, {
  Size size = const Size(390, 844),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  });
}

Future<void> _pumpUi(WidgetTester tester) async {
  for (var index = 0; index < 12; index++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Widget _testAppWithContainer(ProviderContainer container, Widget home) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: _testTheme(),
      builder: (context, child) =>
          AppToastOverlay(child: child ?? const SizedBox.shrink()),
      home: home,
    ),
  );
}

ThemeData _testTheme() => ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
);

class _TestSearchController extends SearchController {
  @override
  SearchState build() =>
      _stateForPage(keyword: 'Search test', source: MusicSource.all, page: 1);

  @override
  Future<void> search({
    required String keyword,
    MusicSource? source,
    int page = 1,
  }) async {
    state = _stateForPage(
      keyword: keyword,
      source: source ?? state.source,
      page: page,
    );
  }
}

class _ErrorSearchController extends SearchController {
  @override
  SearchState build() => const SearchState(source: MusicSource.tx);

  void fail(String message) {
    state = state.copyWith(loading: false, error: message);
  }

  void startRetry() {
    state = state.copyWith(loading: true, error: null);
  }
}

SearchState _stateForPage({
  required String keyword,
  required MusicSource source,
  required int page,
}) {
  const limit = 30;
  return SearchState(
    category: SearchCategory.songs,
    keyword: keyword,
    source: source,
    page: page,
    response: SearchResponse(
      list: [
        for (var index = 1; index <= limit; index++)
          _music(page: page, index: index),
      ],
      page: page,
      limit: limit,
      allPage: 2,
      total: limit * 2,
      source: source,
    ),
  );
}

MusicInfo _music({required int page, required int index}) {
  final paddedIndex = index.toString().padLeft(2, '0');
  final id = 'page-$page-song-$paddedIndex';
  return MusicInfo.fromJson({
    'id': id,
    'name': 'Page $page song $paddedIndex',
    'singer': 'Test artist $paddedIndex',
    'source': MusicSource.wy.code,
    'interval': '03:30',
    'meta': {
      'songId': id,
      'albumName': 'Test album',
      'qualitys': [
        {'type': Quality.k320.code},
      ],
    },
  });
}
