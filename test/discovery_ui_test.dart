import 'dart:async';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:heroine/heroine.dart';
import 'package:prism_ui/prism_ui.dart' show LiquidGlassHost;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cy_shine_music/core/api/music_api.dart';
import 'package:cy_shine_music/core/models/download_capabilities.dart';
import 'package:cy_shine_music/core/models/enums.dart';
import 'package:cy_shine_music/core/models/leaderboard_info.dart';
import 'package:cy_shine_music/core/models/music_info.dart';
import 'package:cy_shine_music/core/models/online_collection_kind.dart';
import 'package:cy_shine_music/core/models/playlist_info.dart';
import 'package:cy_shine_music/core/models/playlist_summary.dart';
import 'package:cy_shine_music/core/models/search_response.dart';
import 'package:cy_shine_music/core/models/search_category.dart';
import 'package:cy_shine_music/core/music_sources/music_source_controller.dart';
import 'package:cy_shine_music/core/storage/settings_store.dart';
import 'package:cy_shine_music/core/ui/app_toast.dart';
import 'package:cy_shine_music/core/ui/container_transform.dart';
import 'package:cy_shine_music/core/ui/cover_placeholder.dart';
import 'package:cy_shine_music/core/ui/widgets/prism_environment.dart';
import 'package:cy_shine_music/core/ui/widgets/spring_artwork_hero.dart';
import 'package:cy_shine_music/features/discovery/discovery_content.dart';
import 'package:cy_shine_music/features/discovery/discovery_controller.dart';
import 'package:cy_shine_music/features/discovery/leaderboards_page.dart';
import 'package:cy_shine_music/features/discovery/online_playlist_detail_page.dart';
import 'package:cy_shine_music/features/discovery/widgets/leaderboard_artwork.dart';
import 'package:cy_shine_music/features/downloads/download_history_entry.dart';
import 'package:cy_shine_music/features/player/player_audio_handler.dart';
import 'package:cy_shine_music/features/player/player_controller.dart';
import 'package:cy_shine_music/features/playlists/playlist_store.dart';
import 'package:cy_shine_music/features/playlists/widgets/immersive_playlist_chrome.dart';
import 'package:cy_shine_music/features/search/search_controller.dart';
import 'package:cy_shine_music/features/search/search_page.dart';
import 'package:cy_shine_music/features/search/search_toolbar_state.dart';
import 'package:cy_shine_music/features/shell/widgets/discovery_category_fab.dart';
import 'package:cy_shine_music/features/shell/widgets/shell_header.dart';
import 'package:cy_shine_music/router.dart';

import 'helpers/prism_test_environment.dart';

const _testDiscoverySources = <MusicSource>[
  MusicSource.kw,
  MusicSource.kg,
  MusicSource.tx,
  MusicSource.wy,
  MusicSource.mg,
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('leaderboard grid resolves missing covers from the first song', (
    tester,
  ) async {
    await _useViewport(tester, const Size(390, 844));
    final prefs = await _freshPreferences();
    final fake = _FakeDiscoveryApi(resolveCovers: true);
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        musicApiProvider.overrideWithValue(fake),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      _appWithContainer(
        container,
        const LeaderboardsPage(source: MusicSource.kw),
      ),
    );
    await tester.pumpAndSettle();

    final artwork = tester.widgetList<LeaderboardArtwork>(
      find.byType(LeaderboardArtwork),
    );
    expect(artwork, hasLength(4));
    expect(
      artwork.map((item) => item.coverUrl),
      everyElement('https://img.test/kw_1.jpg'),
    );
    expect(fake.coverRequests, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('discovery masonry uses two stable columns on phones', (
    tester,
  ) async {
    // 网格懒加载：视口要高到放下全部 9 张卡片。
    await _useViewport(tester, const Size(390, 2400));
    final prefs = await _freshPreferences();
    final fake = _FakeDiscoveryApi();
    final container = ProviderContainer(
      overrides: [
        discoverySourcesProvider.overrideWithValue(_testDiscoverySources),
        sharedPreferencesProvider.overrideWithValue(prefs),
        musicApiProvider.overrideWithValue(fake),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      _appWithContainer(container, const DiscoveryContent()),
    );
    await tester.pumpAndSettle();

    final before = _cardPositions(tester, MusicSource.kw, 9);
    expect(find.byType(CoverUnavailablePlaceholder), findsNWidgets(9));
    expect(
      tester
          .widgetList<Heroine>(find.byType(Heroine))
          .where(
            (hero) =>
                hero.tag == onlinePlaylistArtworkHeroTag(MusicSource.kw, '1'),
          ),
      hasLength(1),
    );
    expect(container.read(selectedDiscoverySourceProvider), MusicSource.kw);
    expect(
      before.values.map((offset) => offset.dx.round()).toSet(),
      hasLength(2),
    );

    container.invalidate(featuredPlaylistsProvider(MusicSource.kw));
    await tester.pumpAndSettle();
    expect(_cardPositions(tester, MusicSource.kw, 9), before);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'discovery shows independent leaderboard previews above playlists',
    (tester) async {
      await _useViewport(tester, const Size(390, 844));
      final prefs = await _freshPreferences();
      final fake = _FakeDiscoveryApi();
      final container = ProviderContainer(
        overrides: [
          discoverySourcesProvider.overrideWithValue(_testDiscoverySources),
          sharedPreferencesProvider.overrideWithValue(prefs),
          musicApiProvider.overrideWithValue(fake),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _appWithContainer(container, const DiscoveryContent()),
      );
      await tester.pumpAndSettle();

      expect(find.text('官方排行榜'), findsOneWidget);
      expect(find.text('精选歌单'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('leaderboard-preview-kw:1')),
        findsOneWidget,
      );
      expect(find.textContaining('榜单歌曲 1'), findsWidgets);
      expect(find.textContaining('榜单歌曲 3'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'opening an online playlist uses a spring cover and a light page fade',
    (tester) async {
      await _useViewport(tester, const Size(390, 844));
      final prefs = await _freshPreferences();
      final fake = _FakeDiscoveryApi(delayDetail: true);
      final audioHandler = PlayerAudioHandler();
      final router = createAppRouter();
      final container = ProviderContainer(
        overrides: [
          discoverySourcesProvider.overrideWithValue(_testDiscoverySources),
          sharedPreferencesProvider.overrideWithValue(prefs),
          musicApiProvider.overrideWithValue(fake),
          playerAudioHandlerProvider.overrideWithValue(audioHandler),
        ],
      );
      addTearDown(() {
        container.dispose();
        router.dispose();
        unawaited(audioHandler.disposeHandler());
      });

      await tester.pumpWidget(_routerApp(container, router));
      for (var frame = 0; frame < 12; frame++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      const cardKey = ValueKey('discovery-card-kw:1');
      final cardRect = tester.getRect(find.byKey(cardKey));

      await tester.tap(find.byKey(cardKey));
      for (var frame = 0; frame < 6; frame++) {
        await tester.pump(const Duration(milliseconds: 1));
        if (find.byType(OnlinePlaylistDetailPage).evaluate().isNotEmpty) break;
      }
      await tester.pump();
      // 卡片起点仍用来管理首次滚动；整页不再做容器缩放。
      final transition = tester.widget<ContainerTransformTransition>(
        find.byType(ContainerTransformTransition),
      );
      _expectRectCloseTo(transition.origin!.rect, cardRect);
      expect(transition.springHero, isTrue);
      expect(find.byKey(ContainerTransformTransition.surfaceKey), findsNothing);

      await _pumpAnimationFrames(tester, const Duration(milliseconds: 80));
      expect(find.byType(OnlinePlaylistDetailPage), findsOneWidget);
      // Both endpoints remain mounted; the overlay paints one artwork layer.
      expect(
        tester
            .widgetList<Heroine>(find.byType(Heroine))
            .where(
              (hero) =>
                  hero.tag == onlinePlaylistArtworkHeroTag(MusicSource.kw, '1'),
            ),
        hasLength(2),
      );
      expect(find.byKey(SpringArtworkHero.flightKey), findsOneWidget);

      await _pumpAnimationFrames(tester, const Duration(milliseconds: 600));
      await tester.pump();
      _expectOnlineDetailFullyOpaque(tester);

      // 返回时只淡出页面，下层网格保持位置。
      expect(await tester.binding.handlePopRoute(), isTrue);
      await _pumpAnimationFrames(tester, const Duration(milliseconds: 80));
      expect(find.byType(OnlinePlaylistDetailPage), findsOneWidget);

      await _pumpAnimationFrames(tester, const Duration(milliseconds: 400));
      await tester.pump();
      expect(find.byType(OnlinePlaylistDetailPage), findsNothing);
      expect(find.byKey(ContainerTransformTransition.surfaceKey), findsNothing);
      expect(tester.getRect(find.byKey(cardKey)), cardRect);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a partially hidden card flies from its crop and returns fully visible',
    (tester) async {
      await _useViewport(tester, const Size(390, 844));
      final prefs = await _freshPreferences();
      final fake = _FakeDiscoveryApi();
      final audioHandler = PlayerAudioHandler();
      final router = createAppRouter();
      final container = ProviderContainer(
        overrides: [
          discoverySourcesProvider.overrideWithValue(_testDiscoverySources),
          sharedPreferencesProvider.overrideWithValue(prefs),
          musicApiProvider.overrideWithValue(fake),
          playerAudioHandlerProvider.overrideWithValue(audioHandler),
        ],
      );
      addTearDown(() {
        container.dispose();
        router.dispose();
        unawaited(audioHandler.disposeHandler());
      });

      await tester.pumpWidget(_routerApp(container, router));
      for (var frame = 0; frame < 12; frame++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      const cardKey = ValueKey('discovery-card-kw:1');
      final scrollable = find
          .descendant(
            of: find.byKey(const PageStorageKey('discovery-kw-scroll')),
            matching: find.byType(Scrollable),
          )
          .first;
      final viewport = tester.getRect(scrollable);
      final position = tester.state<ScrollableState>(scrollable).position;
      // 卡片顶部 40dp 滚到视口外。
      position.jumpTo(
        position.pixels +
            tester.getRect(find.byKey(cardKey)).top -
            viewport.top +
            40,
      );
      await tester.pump();
      final hiddenRect = tester.getRect(find.byKey(cardKey));
      expect(hiddenRect.top, closeTo(viewport.top - 40, 0.5));
      final hiddenPixels = position.pixels;

      await tester.tapAt(hiddenRect.center);
      for (var frame = 0; frame < 6; frame++) {
        await tester.pump(const Duration(milliseconds: 1));
        if (find.byType(OnlinePlaylistDetailPage).evaluate().isNotEmpty) break;
      }
      await tester.pump();

      // 从封面可见部分起飞，被视口裁掉的顶边没有圆角。
      final origin = tester
          .widget<ContainerTransformTransition>(
            find.byType(ContainerTransformTransition),
          )
          .origin!;
      _expectRectCloseTo(origin.rect, hiddenRect);
      _expectRectCloseTo(
        origin.startRect,
        Rect.fromLTRB(
          hiddenRect.left,
          viewport.top,
          hiddenRect.right,
          hiddenRect.bottom,
        ),
      );
      expect(origin.startBorderRadius.topLeft, Radius.zero);
      expect(origin.startBorderRadius.bottomLeft, isNot(Radius.zero));
      expect(find.byKey(ContainerTransformTransition.surfaceKey), findsNothing);
      final visibleCover = origin.cover!.rect.intersect(origin.startRect);
      _expectRectCloseTo(
        tester.getRect(find.byKey(SpringArtworkHero.flightKey)),
        visibleCover,
        tolerance: 4,
      );
      expect(
        tester.widget(find.byKey(SpringArtworkHero.flightKey)),
        isA<ClipRect>(),
      );

      // 详情已盖住列表时，将整张卡片调整到完整可见。
      await _pumpAnimationFrames(tester, const Duration(milliseconds: 600));
      await tester.pump();
      expect(position.pixels, closeTo(hiddenPixels - 48, 0.5));

      // 返回的弹簧飞行落在完整卡片上。
      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pump();
      await _pumpAnimationFrames(tester, const Duration(milliseconds: 330));
      final shownRect = tester.getRect(find.byKey(cardKey));
      expect(shownRect.top, closeTo(viewport.top + 8, 0.5));
      final shownCover = origin.remeasure()!.cover!.rect;
      final landing = tester.getRect(find.byKey(SpringArtworkHero.flightKey));
      expect(landing.width, greaterThanOrEqualTo(shownCover.width));
      expect(landing.width, lessThan(390));
      // The route can finish first; the final spring frames stay in the
      // navigator overlay rather than being clipped inside the target card.
      await _pumpAnimationFrames(tester, const Duration(milliseconds: 1000));
      await tester.pumpAndSettle(const Duration(milliseconds: 16));
      expect(find.byKey(SpringArtworkHero.flightKey), findsNothing);
      expect(find.byType(OnlinePlaylistDetailPage), findsNothing);
      expect(tester.getRect(find.byKey(cardKey)), shownRect);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a scrolled detail flies back without resetting its scroll', (
    tester,
  ) async {
    await _useViewport(tester, const Size(390, 844));
    final prefs = await _freshPreferences();
    final fake = _FakeDiscoveryApi(detailTrackCount: 40);
    final audioHandler = PlayerAudioHandler();
    final router = createAppRouter();
    final container = ProviderContainer(
      overrides: [
        discoverySourcesProvider.overrideWithValue(_testDiscoverySources),
        sharedPreferencesProvider.overrideWithValue(prefs),
        musicApiProvider.overrideWithValue(fake),
        playerAudioHandlerProvider.overrideWithValue(audioHandler),
      ],
    );
    addTearDown(() {
      container.dispose();
      router.dispose();
      unawaited(audioHandler.disposeHandler());
    });

    await tester.pumpWidget(_routerApp(container, router));
    for (var frame = 0; frame < 12; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    const cardKey = ValueKey('discovery-card-kw:1');
    const shuttleKey = ValueKey('artwork-hero-shuttle');
    ScrollPosition detailPosition() => tester
        .state<ScrollableState>(
          find
              .descendant(
                of: find.byType(OnlinePlaylistDetailPage),
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position;

    Future<void> open() async {
      await tester.tap(find.byKey(cardKey));
      for (var frame = 0; frame < 6; frame++) {
        await tester.pump(const Duration(milliseconds: 1));
        if (find.byType(OnlinePlaylistDetailPage).evaluate().isNotEmpty) {
          break;
        }
      }
      await tester.pump();
    }

    await open();
    await _pumpAnimationFrames(tester, const Duration(milliseconds: 600));
    await tester.pump();
    detailPosition().jumpTo(600);
    await tester.pump();
    expect(detailPosition().pixels, 600);

    // 头图已滚走：飞行副本从记住的头图位置收回，实际列表不跳回顶部。
    expect(await tester.binding.handlePopRoute(), isTrue);
    await tester.pump();
    await _pumpAnimationFrames(tester, const Duration(milliseconds: 120));
    expect(find.byKey(shuttleKey), findsNothing);
    expect(find.byKey(ContainerTransformTransition.coverKey), findsNothing);
    expect(find.byKey(ContainerTransformTransition.surfaceKey), findsNothing);
    expect(find.byKey(SpringArtworkHero.flightKey), findsOneWidget);
    expect(detailPosition().pixels, 600);
    final flying = tester.getRect(find.byKey(SpringArtworkHero.flightKey));
    expect(flying.width, lessThan(390 - 8));
    expect(flying.width, greaterThan(180));
    await _pumpAnimationFrames(tester, const Duration(milliseconds: 200));
    await _pumpAnimationFrames(tester, const Duration(milliseconds: 200));
    expect(find.byType(OnlinePlaylistDetailPage), findsNothing);

    // 再次从卡片打开：回到顶部，封面 Hero 照常飞到头图。
    await open();
    await _pumpAnimationFrames(tester, const Duration(milliseconds: 80));
    expect(find.byType(Heroine), findsWidgets);
    await _pumpAnimationFrames(tester, const Duration(milliseconds: 600));
    await tester.pump();
    expect(detailPosition().pixels, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('discovery routes draw their section titles inside the page', (
    tester,
  ) async {
    await _useViewport(tester, const Size(390, 844));
    final prefs = await _freshPreferences();
    final fake = _FakeDiscoveryApi();
    final audioHandler = PlayerAudioHandler();
    final router = createAppRouter();
    final container = ProviderContainer(
      overrides: [
        discoverySourcesProvider.overrideWithValue(_testDiscoverySources),
        sharedPreferencesProvider.overrideWithValue(prefs),
        musicApiProvider.overrideWithValue(fake),
        playerAudioHandlerProvider.overrideWithValue(audioHandler),
      ],
    );
    addTearDown(() {
      container.dispose();
      router.dispose();
      unawaited(audioHandler.disposeHandler());
    });

    await tester.pumpWidget(_routerApp(container, router));
    for (var frame = 0; frame < 12; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.byType(ShellHeader), findsNothing);
    expect(
      find.descendant(of: find.byType(SearchPage), matching: find.text('发现')),
      findsOneWidget,
    );
    final contentTop = tester.getTopLeft(find.byType(DiscoveryContent)).dy;

    await tester.tap(find.byKey(const ValueKey('leaderboard-all-kw')));
    await tester.pumpAndSettle();
    expect(find.byType(LeaderboardsPage), findsOneWidget);
    expect(find.byType(ShellHeader), findsNothing);
    expect(
      find.descendant(
        of: find.byType(LeaderboardsPage),
        matching: find.text('排行榜'),
      ),
      findsOneWidget,
    );

    expect(await tester.binding.handlePopRoute(), isTrue);
    await tester.pumpAndSettle();
    expect(find.byType(LeaderboardsPage), findsNothing);
    expect(tester.getTopLeft(find.byType(DiscoveryContent)).dy, contentTop);
    expect(tester.takeException(), isNull);
  });

  testWidgets('artwork theme reuses its resolved color after remounting', (
    tester,
  ) async {
    final prefs = await _freshPreferences();
    const probeKey = ValueKey('artwork-theme-color-probe');
    final baseScheme = ColorScheme.fromSeed(seedColor: Colors.teal);
    final artwork = MemoryImage(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAAXNSR0IArs4c6QAA'
        'AARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAASSURBVBhXY7ij'
        'rPsfhKEM3f8ATTgIrTbBk9sAAAAASUVORK5CYII=',
      ),
    );

    Widget app({required bool showArtworkTheme}) {
      return ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: MaterialApp(
          theme: ThemeData(useMaterial3: true, colorScheme: baseScheme),
          home: showArtworkTheme
              ? PlaylistArtworkTheme(
                  artworkProvider: artwork,
                  cacheKey: 'test:resolved-artwork-remount',
                  child: Builder(
                    builder: (context) => ColoredBox(
                      key: probeKey,
                      color: Theme.of(context).colorScheme.primary,
                      child: const SizedBox.expand(),
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      );
    }

    Color probeColor() => tester.widget<ColoredBox>(find.byKey(probeKey)).color;

    await tester.pumpWidget(app(showArtworkTheme: true));
    for (var frame = 0; frame < 20; frame++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      if (probeColor() != baseScheme.primary) break;
    }
    await tester.pump(const Duration(milliseconds: 600));
    final artworkColor = probeColor();
    expect(artworkColor, isNot(baseScheme.primary));

    await tester.pumpWidget(app(showArtworkTheme: false));
    await tester.pump();
    await tester.pumpWidget(app(showArtworkTheme: true));

    expect(probeColor(), artworkColor);
    await tester.pump();
    expect(probeColor(), artworkColor);
    expect(tester.takeException(), isNull);
  });

  testWidgets('online detail remembers discovery artwork without route extra', (
    tester,
  ) async {
    await _useViewport(tester, const Size(390, 844));
    final prefs = await _freshPreferences();
    final fake = _FakeDiscoveryApi(delayDetail: true);
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        musicApiProvider.overrideWithValue(fake),
      ],
    );
    addTearDown(container.dispose);
    const coverUrl = 'https://img.test/discovery-cover.jpg';
    const page = OnlinePlaylistDetailPage(
      source: MusicSource.kw,
      playlistId: '1',
    );

    await tester.pumpWidget(
      _appWithContainer(
        container,
        const OnlinePlaylistDetailPage(
          source: MusicSource.kw,
          playlistId: '1',
          summary: PlaylistSummary(
            id: '1',
            name: '发现页歌单',
            source: MusicSource.kw,
            coverUrl: coverUrl,
          ),
        ),
      ),
    );
    await tester.pump();
    final firstProvider = tester
        .widget<PlaylistArtworkTheme>(find.byType(PlaylistArtworkTheme))
        .artworkProvider;
    expect(firstProvider, isA<CachedNetworkImageProvider>());

    await tester.pumpWidget(
      _appWithContainer(container, const SizedBox.shrink()),
    );
    await tester.pump();
    await tester.pumpWidget(_appWithContainer(container, page));
    await tester.pump();

    final restoredProvider = tester
        .widget<PlaylistArtworkTheme>(find.byType(PlaylistArtworkTheme))
        .artworkProvider;
    expect(restoredProvider, firstProvider);
    await tester.pump(const Duration(seconds: 6));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('discovery platform menu and displayed source stay in sync', (
    tester,
  ) async {
    await _useViewport(tester, const Size(390, 844));
    final prefs = await _freshPreferences();
    final fake = _FakeDiscoveryApi();
    final container = ProviderContainer(
      overrides: [
        discoverySourcesProvider.overrideWithValue(_testDiscoverySources),
        sharedPreferencesProvider.overrideWithValue(prefs),
        musicApiProvider.overrideWithValue(fake),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_appWithContainer(container, const SearchPage()));
    await tester.pumpAndSettle();

    expect(container.read(selectedDiscoverySourceProvider), MusicSource.kw);

    for (final source in [MusicSource.kg, MusicSource.kw, MusicSource.mg]) {
      await tester.tap(
        find.byKey(const ValueKey('search-platform-menu-anchor')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('${source.label}音乐'));
      await tester.pumpAndSettle();
      expect(container.read(selectedDiscoverySourceProvider), source);
      expect(
        find.byKey(ValueKey('discovery-card-${source.code}:1')),
        findsOneWidget,
      );
    }
    expect(find.text('咪咕'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('discovery cards wear static glass instead of live panes', (
    tester,
  ) async {
    await _useViewport(tester, const Size(390, 844));
    final prefs = await _freshPreferences();
    final fake = _FakeDiscoveryApi();
    final container = ProviderContainer(
      overrides: [
        discoverySourcesProvider.overrideWithValue(_testDiscoverySources),
        sharedPreferencesProvider.overrideWithValue(prefs),
        musicApiProvider.overrideWithValue(fake),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      _appWithContainer(
        container,
        const PrismEnvironment(child: DiscoveryContent()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('discovery-card-kw:1')), findsOneWidget);

    // 卡片铺在纯色背景上：滚动时不应有任何玻璃逐帧重拍背景。
    final scrollable = tester.widget<CustomScrollView>(
      find.byKey(const PageStorageKey('discovery-kw-scroll')),
    );
    final captures = LiquidGlassHost.debugCaptures;
    scrollable.controller!.position.jumpTo(200);
    await tester.pump();
    expect(LiquidGlassHost.debugCaptures, greaterThan(captures));
    expect(LiquidGlassHost.debugLastCapture!.panes, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('discovery masonry uses three columns on wide layouts', (
    tester,
  ) async {
    await _useViewport(tester, const Size(900, 1800));
    final prefs = await _freshPreferences();
    final fake = _FakeDiscoveryApi();
    final container = ProviderContainer(
      overrides: [
        discoverySourcesProvider.overrideWithValue(_testDiscoverySources),
        sharedPreferencesProvider.overrideWithValue(prefs),
        musicApiProvider.overrideWithValue(fake),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      _appWithContainer(container, const DiscoveryContent()),
    );
    await tester.pumpAndSettle();

    final positions = _cardPositions(tester, MusicSource.kw, 9);
    expect(
      positions.values.map((offset) => offset.dx.round()).toSet(),
      hasLength(3),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('discovery loads the next catalog page near the bottom', (
    tester,
  ) async {
    await _useViewport(tester, const Size(390, 844));
    final prefs = await _freshPreferences();
    final fake = _FakeDiscoveryApi(paginateFeatured: true);
    final container = ProviderContainer(
      overrides: [
        discoverySourcesProvider.overrideWithValue(_testDiscoverySources),
        sharedPreferencesProvider.overrideWithValue(prefs),
        musicApiProvider.overrideWithValue(fake),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      _appWithContainer(container, const DiscoveryContent()),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('discovery-card-kw:31')), findsNothing);

    final scrollable = tester.widget<CustomScrollView>(
      find.byKey(const PageStorageKey('discovery-kw-scroll')),
    );
    final position = scrollable.controller!.position;
    position.jumpTo(position.maxScrollExtent);
    await tester.pump();
    await tester.pumpAndSettle();

    expect(fake.featuredPages, contains(2));
    expect(find.byKey(const ValueKey('discovery-card-kw:31')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'discovery category FAB reloads sorting and hides when singular',
    (tester) async {
      await _useViewport(tester, const Size(390, 844));
      final prefs = await _freshPreferences();
      final fake = _FakeDiscoveryApi();
      final container = ProviderContainer(
        overrides: [
          discoverySourcesProvider.overrideWithValue(_testDiscoverySources),
          sharedPreferencesProvider.overrideWithValue(prefs),
          musicApiProvider.overrideWithValue(fake),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _appWithContainer(
          container,
          const Stack(
            children: [
              DiscoveryContent(),
              Positioned.fill(child: DiscoveryCategoryFabLayer()),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('discovery-category-fab')),
        findsOneWidget,
      );
      expect(fake.featuredCategories.last, 'new');
      final spotlightBefore = tester.element(
        find.byKey(const ValueKey('leaderboard-preview-kw:1')),
      );

      await tester.tap(find.byKey(const ValueKey('discovery-category-fab')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('discovery-category-hot')));
      // 分类切换只让「精选歌单」区块变化，官方排行榜卡片原地不动。
      await tester.pump();
      expect(
        tester.element(find.byKey(const ValueKey('leaderboard-preview-kw:1'))),
        same(spotlightBefore),
      );
      await tester.pumpAndSettle();
      expect(
        tester.element(find.byKey(const ValueKey('leaderboard-preview-kw:1'))),
        same(spotlightBefore),
      );
      expect(find.byKey(const ValueKey('discovery-card-kw:1')), findsOneWidget);

      expect(
        container.read(selectedDiscoveryCategoryProvider(MusicSource.kw)),
        'hot',
      );
      expect(fake.featuredCategories.last, 'hot');

      container.read(selectedDiscoverySourceProvider.notifier).state =
          MusicSource.mg;
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('discovery-category-fab')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('discovery category FAB yields to search paging', (tester) async {
    final prefs = await _freshPreferences();
    final container = ProviderContainer(
      overrides: [
        discoverySourcesProvider.overrideWithValue(_testDiscoverySources),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
    );
    addTearDown(container.dispose);
    container.read(searchToolbarStateProvider.notifier).state =
        const SearchToolbarState(visible: true);

    await tester.pumpWidget(
      _appWithContainer(container, const DiscoveryCategoryFabLayer()),
    );

    expect(find.byKey(const ValueKey('discovery-category-fab')), findsNothing);
  });

  testWidgets('discovery source seeds the next search source', (tester) async {
    await _useViewport(tester, const Size(390, 844));
    final prefs = await _freshPreferences();
    final fake = _FakeDiscoveryApi();
    final container = ProviderContainer(
      overrides: [
        discoverySourcesProvider.overrideWithValue(_testDiscoverySources),
        sharedPreferencesProvider.overrideWithValue(prefs),
        musicApiProvider.overrideWithValue(fake),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_appWithContainer(container, const SearchPage()));
    await tester.pumpAndSettle();
    expect(container.read(searchControllerProvider).source, MusicSource.kw);

    await tester.tap(find.byKey(const ValueKey('search-platform-menu-anchor')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('QQ音乐'));
    await tester.pumpAndSettle();

    expect(container.read(selectedDiscoverySourceProvider), MusicSource.tx);
    expect(container.read(searchControllerProvider).source, MusicSource.tx);
    expect(find.byKey(const ValueKey('discovery-card-tx:1')), findsOneWidget);

    await tester.tap(find.byType(SearchBar));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText).last, '周杰伦');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump(const Duration(milliseconds: 400));

    expect(fake.searchRequests, [
      const SearchQuery(keyword: '周杰伦', source: MusicSource.tx, page: 1),
    ]);
    expect(container.read(searchControllerProvider).source, MusicSource.tx);
  });

  testWidgets('long press preview lists only the first eight tracks', (
    tester,
  ) async {
    await _useViewport(tester, const Size(390, 844));
    final prefs = await _freshPreferences();
    final fake = _FakeDiscoveryApi();
    final container = ProviderContainer(
      overrides: [
        discoverySourcesProvider.overrideWithValue(_testDiscoverySources),
        sharedPreferencesProvider.overrideWithValue(prefs),
        musicApiProvider.overrideWithValue(fake),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      _appWithContainer(container, const DiscoveryContent()),
    );
    await tester.pumpAndSettle();
    await tester.longPress(find.byKey(const ValueKey('discovery-card-kw:1')));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('预览歌曲 1'), findsOneWidget);
    expect(find.text('预览歌曲 8'), findsOneWidget);
    expect(find.text('预览歌曲 9'), findsNothing);
    expect(find.text('查看完整歌单'), findsOneWidget);
    expect(fake.detailRequests, 1);
  });

  test(
    'online playlist detail provider shares one completed request',
    () async {
      final fake = _FakeDiscoveryApi();
      final container = ProviderContainer(
        overrides: [musicApiProvider.overrideWithValue(fake)],
      );
      addTearDown(container.dispose);
      const key = OnlinePlaylistKey(source: MusicSource.kw, id: '1');

      await container.read(onlinePlaylistDetailProvider(key).future);
      await container.read(onlinePlaylistDetailProvider(key).future);

      expect(fake.detailRequests, 1);
      expect(fake.detailTrackLimits, [onlinePlaylistDetailInitialTrackLimit]);
    },
  );

  test(
    'online detail provider routes leaderboard keys independently',
    () async {
      final fake = _FakeDiscoveryApi();
      final container = ProviderContainer(
        overrides: [musicApiProvider.overrideWithValue(fake)],
      );
      addTearDown(container.dispose);
      const playlistKey = OnlinePlaylistKey(source: MusicSource.kw, id: '1');
      const boardKey = OnlinePlaylistKey(
        source: MusicSource.kw,
        id: '1',
        kind: OnlineCollectionKind.leaderboard,
      );

      final playlist = await container.read(
        onlinePlaylistDetailProvider(playlistKey).future,
      );
      final leaderboard = await container.read(
        onlinePlaylistDetailProvider(boardKey).future,
      );

      expect(playlist.name, '酷我精选歌单 1');
      expect(leaderboard.name, '酷我榜单 1');
      expect(playlistKey, isNot(boardKey));
    },
  );

  test('online song cover fallback bypasses a broken embedded URL', () async {
    final fake = _FakeDiscoveryApi(resolveCovers: true);
    final container = ProviderContainer(
      overrides: [musicApiProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);
    final music = _music(MusicSource.kg, 7, '需要补图的歌曲');

    final url = await container.read(
      onlineTrackCoverProvider(OnlineTrackCoverKey(music)).future,
    );

    expect(url, 'https://img.test/${music.id}.jpg');
    expect(fake.coverRequests, 1);
    expect(fake.lastCoverRequestPreferredCached, isFalse);
  });

  test('search controller reuses cached platform pages', () async {
    final prefs = await _freshPreferences();
    final fake = _FakeDiscoveryApi();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        musicApiProvider.overrideWithValue(fake),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(searchControllerProvider.notifier);

    await controller.search(keyword: '缓存测试', source: MusicSource.tx, page: 1);
    await controller.search(keyword: '缓存测试', source: MusicSource.kg, page: 1);
    await controller.search(keyword: '缓存测试', source: MusicSource.tx, page: 1);
    await controller.search(keyword: '缓存测试', source: MusicSource.kg, page: 1);
    await controller.search(keyword: '缓存测试', source: MusicSource.kg, page: 2);
    await controller.search(keyword: '缓存测试', source: MusicSource.kg, page: 2);

    expect(fake.searchRequests, [
      const SearchQuery(keyword: '缓存测试', source: MusicSource.tx, page: 1),
      const SearchQuery(keyword: '缓存测试', source: MusicSource.kg, page: 1),
      const SearchQuery(keyword: '缓存测试', source: MusicSource.kg, page: 2),
    ]);
  });

  testWidgets(
    'search cancel restores discovery and rejects the stale response',
    (tester) async {
      await _useViewport(tester, const Size(390, 844));
      final prefs = await _freshPreferences();
      final fake = _FakeDiscoveryApi(delaySearch: true);
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          musicApiProvider.overrideWithValue(fake),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(_appWithContainer(container, const SearchPage()));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(SearchBar));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(EditableText).last, '慢搜索');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump(const Duration(milliseconds: 300));

      final cancelButton = find.byTooltip('取消搜索').hitTestable();
      expect(cancelButton, findsOneWidget);
      await tester.tap(cancelButton);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(DiscoveryContent), findsOneWidget);
      expect(container.read(searchControllerProvider).isSearchActive, isFalse);

      fake.completeSearch();
      await tester.pumpAndSettle();
      expect(container.read(searchControllerProvider).isSearchActive, isFalse);
      expect(find.text('迟到的搜索结果'), findsNothing);
    },
  );

  testWidgets(
    'online detail can favorite and unfavorite without leaving the page',
    (tester) async {
      await _useViewport(tester, const Size(390, 844));
      final prefs = await _freshPreferences();
      final fake = _FakeDiscoveryApi();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          musicApiProvider.overrideWithValue(fake),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _appWithContainer(
          container,
          const OnlinePlaylistDetailPage(
            source: MusicSource.kw,
            playlistId: '1',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('immersive-playlist-header')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('playlist-detail-info')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('immersive-playlist-header')),
          matching: find.byType(BackdropFilter),
        ),
        findsNothing,
      );
      expect(find.byTooltip('返回上一页'), findsOneWidget);
      expect(find.text('播放全部'), findsOneWidget);
      expect(find.byTooltip('歌曲操作'), findsWidgets);
      await tester.tap(find.text('收藏歌单'));
      await tester.pumpAndSettle();

      expect(container.read(localPlaylistsProvider), hasLength(1));
      expect(find.text('已收藏'), findsOneWidget);
      await tester.tap(find.text('已收藏'));
      await tester.pumpAndSettle();

      expect(container.read(localPlaylistsProvider), isEmpty);
      expect(find.text('收藏歌单'), findsOneWidget);
      expect(find.byType(OnlinePlaylistDetailPage), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('online detail keeps header actions stable while data loads', (
    tester,
  ) async {
    await _useViewport(tester, const Size(390, 844));
    final prefs = await _freshPreferences();
    final fake = _FakeDiscoveryApi(delayDetail: true);
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        musicApiProvider.overrideWithValue(fake),
      ],
    );
    addTearDown(container.dispose);
    const description = '这是一段用于验证固定两行简介区域的完整歌单描述。';
    const summary = PlaylistSummary(
      id: '1',
      name: '酷我精选歌单 1',
      source: MusicSource.kw,
      creator: '酷我编辑',
      description: description,
      trackCount: 10,
      playCount: 5000,
    );

    await tester.pumpWidget(
      _appWithContainer(
        container,
        const OnlinePlaylistDetailPage(
          source: MusicSource.kw,
          playlistId: '1',
          summary: summary,
        ),
      ),
    );
    await tester.pump();

    final playButton = find.byKey(const ValueKey('playlist-play-all'));
    final saveButton = find.byKey(const ValueKey('playlist-favorite'));
    final descriptionSlot = find.byKey(
      const ValueKey('playlist-description-slot'),
    );
    final artworkHeader = find.byKey(
      const ValueKey('immersive-playlist-header'),
    );
    final detailInfo = find.byKey(const ValueKey('playlist-detail-info'));
    expect(playButton, findsOneWidget);
    expect(saveButton, findsOneWidget);
    expect(find.text('歌曲  10'), findsOneWidget);
    expect(tester.getSize(descriptionSlot).height, 40);
    final tooltip = tester.widget<Tooltip>(
      find.descendant(of: descriptionSlot, matching: find.byType(Tooltip)),
    );
    expect(tooltip.message, description);
    expect(tooltip.triggerMode, TooltipTriggerMode.manual);

    await tester.tap(find.byKey(const ValueKey('playlist-detail-title')));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text(description), findsOneWidget);

    await tester.longPress(find.text(description));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text(description), findsNWidgets(2));
    expect(Tooltip.dismissAllToolTips(), isTrue);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text(description), findsOneWidget);

    final loadingPlayTop = tester.getTopLeft(playButton).dy;
    final loadingSaveTop = tester.getTopLeft(saveButton).dy;
    final loadingHeadingTop = tester.getTopLeft(find.text('歌曲  10')).dy;
    final loadingDescriptionTop = tester.getTopLeft(descriptionSlot).dy;
    // 数据到达时只换歌曲列表：头图与滚动视图原地保留，不整页重建。
    final headerElement = tester.element(artworkHeader);
    final scrollState = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byType(OnlinePlaylistDetailPage),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(tester.getSize(artworkHeader).height, closeTo(844 * 0.4, 0.1));
    expect(
      tester.getBottomLeft(artworkHeader).dy,
      closeTo(tester.getTopLeft(detailInfo).dy, 0.1),
    );
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('playlist-detail-title'))).dy,
      greaterThanOrEqualTo(tester.getBottomLeft(artworkHeader).dy),
    );

    fake.completeDetail();
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(playButton).dy, loadingPlayTop);
    expect(tester.getTopLeft(saveButton).dy, loadingSaveTop);
    expect(tester.getTopLeft(find.text('歌曲  10')).dy, loadingHeadingTop);
    expect(tester.getTopLeft(descriptionSlot).dy, loadingDescriptionTop);
    expect(tester.getSize(descriptionSlot).height, 40);
    expect(tester.element(artworkHeader), same(headerElement));
    expect(
      tester.state<ScrollableState>(
        find
            .descendant(
              of: find.byType(OnlinePlaylistDetailPage),
              matching: find.byType(Scrollable),
            )
            .first,
      ),
      same(scrollState),
    );
    expect(
      tester.getBottomLeft(artworkHeader).dy,
      closeTo(tester.getTopLeft(detailInfo).dy, 0.1),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'online detail keeps and saves the discovery artwork after data loads',
    (tester) async {
      await _useViewport(tester, const Size(390, 844));
      final prefs = await _freshPreferences();
      final fake = _FakeDiscoveryApi(
        detailCoverUrl: 'https://img.test/detail-only-cover.jpg',
      );
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          musicApiProvider.overrideWithValue(fake),
        ],
      );
      addTearDown(container.dispose);
      const discoveryCover = 'http://p1.music.126.net/discovery-cover/test.jpg';
      const summary = PlaylistSummary(
        id: '1',
        name: '发现页歌单',
        source: MusicSource.kw,
        coverUrl: discoveryCover,
      );

      await tester.pumpWidget(
        _appWithContainer(
          container,
          const OnlinePlaylistDetailPage(
            source: MusicSource.kw,
            playlistId: '1',
            summary: summary,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      final artworkTheme = tester.widget<PlaylistArtworkTheme>(
        find.byType(PlaylistArtworkTheme),
      );
      final provider = artworkTheme.artworkProvider;
      expect(provider, isA<CachedNetworkImageProvider>());
      expect(
        (provider! as CachedNetworkImageProvider).url,
        'https://p1.music.126.net/discovery-cover/test.jpg?param=640y640',
      );
      expect(
        tester.widget<Hero>(find.byType(Hero)).tag,
        onlinePlaylistArtworkHeroTag(MusicSource.kw, '1'),
      );

      await tester.tap(find.text('收藏歌单'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(
        container.read(localPlaylistsProvider).single.coverUrl,
        discoveryCover,
      );
      await tester.pump(const Duration(seconds: 6));
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('online detail favorites the full playlist after shallow load', (
    tester,
  ) async {
    await _useViewport(tester, const Size(390, 844));
    final prefs = await _freshPreferences();
    final fake = _FakeDiscoveryApi(detailTrackCount: 65);
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        musicApiProvider.overrideWithValue(fake),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      _appWithContainer(
        container,
        const OnlinePlaylistDetailPage(source: MusicSource.kw, playlistId: '1'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('歌曲  40/65'), findsOneWidget);
    await tester.tap(find.text('收藏歌单'));
    await tester.pumpAndSettle();

    final saved = container.read(localPlaylistsProvider).single;
    expect(saved.tracks, hasLength(65));
    expect(fake.detailTrackLimits, [40, null]);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('online detail plays immediately then expands the queue', (
    tester,
  ) async {
    await _useViewport(tester, const Size(390, 844));
    final prefs = await _freshPreferences();
    final fake = _FakeDiscoveryApi(detailTrackCount: 65);
    final audioHandler = PlayerAudioHandler();
    late _RecordingPlayerController player;
    final router = GoRouter(
      initialLocation: '/discover/playlists/kw/1',
      routes: [
        GoRoute(
          path: '/discover/playlists/:source/:id',
          builder: (_, _) => const OnlinePlaylistDetailPage(
            source: MusicSource.kw,
            playlistId: '1',
          ),
        ),
        GoRoute(path: '/player', builder: (_, _) => const SizedBox.shrink()),
      ],
    );
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        musicApiProvider.overrideWithValue(fake),
        downloadCapabilitiesProvider.overrideWithValue(
          const AsyncData(
            DownloadCapabilities(
              sources: {
                MusicSource.kw: [Quality.k320],
              },
              availableSources: [MusicSource.kw],
            ),
          ),
        ),
        playerAudioHandlerProvider.overrideWithValue(audioHandler),
        playerControllerProvider.overrideWith(
          (ref) => player = _RecordingPlayerController(ref),
        ),
      ],
    );
    addTearDown(() {
      container.dispose();
      router.dispose();
      unawaited(audioHandler.disposeHandler());
    });

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
          ),
          builder: (context, child) =>
              AppToastOverlay(child: child ?? const SizedBox.shrink()),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('歌曲  40/65'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('playlist-play-all')));
    await tester.pumpAndSettle();

    expect(fake.detailTrackLimits, [40, null]);
    expect(player.events, ['play:40', 'expand:65']);
    expect(player.playedQueue, hasLength(40));
    expect(player.playedQueue.first.musicId, 'kw_1');
    expect(player.playedQueue.last.musicId, 'kw_40');
    expect(player.expandedQueue, hasLength(65));
    expect(player.expandedQueue.last.musicId, 'kw_65');
    expect(player.playedEntry?.musicId, 'kw_1');
    expect(
      router.routeInformationProvider.value.uri.path,
      '/discover/playlists/kw/1',
    );
    expect(tester.takeException(), isNull);
  });
}

class _RecordingPlayerController extends PlayerController {
  _RecordingPlayerController(super.ref);

  List<DownloadHistoryEntry> playedQueue = const [];
  List<DownloadHistoryEntry> expandedQueue = const [];
  DownloadHistoryEntry? playedEntry;
  final List<String> events = <String>[];

  @override
  Future<void> playFromPlaylistQueue(
    DownloadHistoryEntry entry,
    List<DownloadHistoryEntry> queue, {
    String? playlistId,
  }) async {
    playedEntry = entry;
    playedQueue = List<DownloadHistoryEntry>.of(queue);
    events.add('play:${queue.length}');
  }

  @override
  bool expandPlaylistQueue({
    required List<DownloadHistoryEntry> expectedQueue,
    required List<DownloadHistoryEntry> expandedQueue,
  }) {
    this.expandedQueue = List<DownloadHistoryEntry>.of(expandedQueue);
    events.add('expand:${expandedQueue.length}');
    return true;
  }
}

class _FakeDiscoveryApi extends MusicApi {
  _FakeDiscoveryApi({
    this.delaySearch = false,
    this.delayDetail = false,
    this.resolveCovers = false,
    this.detailCoverUrl,
    this.paginateFeatured = false,
    this.detailTrackCount = 10,
  });

  final bool delaySearch;
  final bool delayDetail;
  final bool resolveCovers;
  final String? detailCoverUrl;
  final bool paginateFeatured;
  final int detailTrackCount;
  final Completer<SearchResponse> _search = Completer<SearchResponse>();
  final Completer<PlaylistInfo> _detail = Completer<PlaylistInfo>();
  int detailRequests = 0;
  int coverRequests = 0;
  bool? lastCoverRequestPreferredCached;
  final List<int> featuredPages = <int>[];
  final List<String?> featuredCategories = <String?>[];
  final List<int?> detailTrackLimits = <int?>[];
  final List<SearchQuery> searchRequests = <SearchQuery>[];

  @override
  Future<String?> getPicUrl({
    required MusicInfo musicInfo,
    bool preferCached = true,
  }) async {
    coverRequests++;
    lastCoverRequestPreferredCached = preferCached;
    return resolveCovers ? 'https://img.test/${musicInfo.id}.jpg' : null;
  }

  @override
  Future<List<PlaylistSummary>> featuredPlaylists({
    required MusicSource source,
    int page = 1,
    int limit = 20,
    String? categoryId,
  }) async {
    featuredPages.add(page);
    featuredCategories.add(categoryId);
    final start = paginateFeatured ? (page - 1) * limit + 1 : 1;
    final count = paginateFeatured ? (page == 1 ? limit : 5) : 9;
    return [
      for (var index = start; index < start + count; index++)
        PlaylistSummary(
          id: '$index',
          name: '${source.label}精选歌单 $index',
          source: source,
          creator: '${source.label}编辑',
          description: '固定发现页简介 $index',
          trackCount: 10,
          playCount: 1000 + index,
        ),
    ];
  }

  @override
  Future<List<LeaderboardSummary>> getLeaderboards(MusicSource source) async {
    return [
      for (var index = 1; index <= 4; index++)
        LeaderboardSummary(
          id: '${source.code}__$index',
          boardId: '$index',
          name: '${source.label}榜单 $index',
          source: source,
        ),
    ];
  }

  @override
  Future<LeaderboardSummary> getLeaderboardPreview(
    LeaderboardSummary board, {
    int limit = 3,
  }) async {
    return board.copyWith(
      previewTracks: [
        for (var index = 1; index <= limit; index++)
          _music(board.source, index, '榜单歌曲 $index'),
      ],
    );
  }

  @override
  Future<PlaylistInfo> getLeaderboard({
    required MusicSource source,
    required String boardId,
    int? maxTracks,
  }) async {
    final count = maxTracks ?? detailTrackCount;
    return PlaylistInfo(
      id: boardId,
      name: '${source.label}榜单 $boardId',
      source: source,
      creator: source.label,
      trackCount: detailTrackCount,
      tracks: [
        for (var index = 1; index <= count.clamp(0, detailTrackCount); index++)
          _music(source, index, '榜单歌曲 $index'),
      ],
    );
  }

  @override
  Future<PlaylistInfo> parsePlaylist({
    required String input,
    MusicSource source = MusicSource.all,
    int? maxTracks,
  }) {
    detailRequests++;
    detailTrackLimits.add(maxTracks);
    final loadedCount = maxTracks == null || maxTracks <= 0
        ? detailTrackCount
        : maxTracks.clamp(0, detailTrackCount).toInt();
    final playlist = PlaylistInfo(
      id: input,
      name: '${source.label}精选歌单 $input',
      source: source,
      creator: '${source.label}编辑',
      description: '固定歌单详情',
      coverUrl: detailCoverUrl,
      playCount: 5000,
      trackCount: detailTrackCount,
      tracks: [
        for (var index = 1; index <= loadedCount; index++)
          _music(source, index, '预览歌曲 $index'),
      ],
    );
    return delayDetail ? _detail.future : Future.value(playlist);
  }

  @override
  Future<SearchResponse> searchContent({
    required String keyword,
    required MusicSource source,
    required SearchCategory category,
    int page = 1,
    int limit = 30,
  }) {
    // Keep this fake focused on search-controller caching. The real catalog
    // fan-out can return partial notices, which are intentionally retryable
    // and therefore not cached by the production controller.
    searchRequests.add(
      SearchQuery(
        keyword: keyword,
        source: source,
        page: page,
        category: category,
      ),
    );
    if (delaySearch) return _search.future;
    return Future.value(_searchResponse(source));
  }

  @override
  Future<SearchResponse> searchMusic({
    required String keyword,
    required MusicSource source,
    int page = 1,
    int limit = 30,
  }) {
    searchRequests.add(
      SearchQuery(keyword: keyword, source: source, page: page),
    );
    if (delaySearch) return _search.future;
    return Future.value(_searchResponse(source));
  }

  @override
  Future<List<String>> searchTip({
    required String keyword,
    required MusicSource source,
    int limit = 8,
  }) async => const [];

  void completeSearch() {
    if (!_search.isCompleted) {
      _search.complete(_searchResponse(MusicSource.all));
    }
  }

  void completeDetail() {
    if (_detail.isCompleted) return;
    _detail.complete(
      PlaylistInfo(
        id: '1',
        name: '酷我精选歌单 1',
        source: MusicSource.kw,
        creator: '酷我编辑',
        description: '这是一段用于验证固定两行简介区域的完整歌单描述。',
        playCount: 5000,
        trackCount: 10,
        tracks: [
          for (var index = 1; index <= 10; index++)
            _music(MusicSource.kw, index, '预览歌曲 $index'),
        ],
      ),
    );
  }
}

SearchResponse _searchResponse(MusicSource source) => SearchResponse(
  list: [_music(MusicSource.kw, 99, '迟到的搜索结果')],
  page: 1,
  limit: 30,
  allPage: 1,
  total: 1,
  source: source,
);

MusicInfo _music(MusicSource source, int id, String name) {
  return MusicInfo.fromJson({
    'id': '${source.code}_$id',
    'name': name,
    'singer': '测试歌手',
    'source': source.code,
    'interval': '03:20',
    'meta': {
      'songId': id,
      'albumName': '测试专辑',
      'qualitys': [
        {'type': Quality.k320.code, 'size': '8.00M'},
      ],
    },
  });
}

Map<String, Offset> _cardPositions(
  WidgetTester tester,
  MusicSource source,
  int count,
) {
  return {
    for (var index = 1; index <= count; index++)
      '$index': tester.getTopLeft(
        find.byKey(ValueKey('discovery-card-${source.code}:$index')),
      ),
  };
}

Future<void> _pumpAnimationFrames(
  WidgetTester tester,
  Duration duration,
) async {
  const frame = Duration(milliseconds: 16);
  var remaining = duration;
  while (remaining > Duration.zero) {
    final step = remaining < frame ? remaining : frame;
    await tester.pump(step);
    remaining -= step;
  }
}

void _expectOnlineDetailFullyOpaque(WidgetTester tester) {
  final detail = find.byType(OnlinePlaylistDetailPage);
  expect(detail, findsOneWidget);
  final fades = find.ancestor(
    of: detail,
    matching: find.byType(FadeTransition),
  );
  for (final fade in tester.widgetList<FadeTransition>(fades)) {
    expect(fade.opacity.value, closeTo(1, 0.001));
  }
}

Future<SharedPreferences> _freshPreferences() async {
  SharedPreferences.setMockInitialValues({});
  return SharedPreferences.getInstance();
}

Future<void> _useViewport(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  });
}

Widget _routerApp(ProviderContainer container, GoRouter router) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
      ),
      builder: (context, child) => buildPrismTestEnvironment(
        context,
        AppToastOverlay(child: child ?? const SizedBox.shrink()),
      ),
      routerConfig: router,
    ),
  );
}

void _expectRectCloseTo(Rect actual, Rect expected, {double tolerance = 0.5}) {
  expect(actual.left, closeTo(expected.left, tolerance));
  expect(actual.top, closeTo(expected.top, tolerance));
  expect(actual.right, closeTo(expected.right, tolerance));
  expect(actual.bottom, closeTo(expected.bottom, tolerance));
}

Widget _appWithContainer(ProviderContainer container, Widget home) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
      ),
      builder: (context, child) => buildPrismTestEnvironment(
        context,
        AppToastOverlay(child: child ?? const SizedBox.shrink()),
      ),
      home: Scaffold(body: home),
    ),
  );
}
