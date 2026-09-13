import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cy_shine_music/core/storage/settings_store.dart';
import 'package:cy_shine_music/features/player/player_audio_handler.dart';
import 'package:cy_shine_music/features/player/player_controller.dart';
import 'package:cy_shine_music/features/player/player_page.dart';
import 'package:cy_shine_music/features/settings/settings_page.dart';
import 'package:cy_shine_music/features/shell/app_shell.dart';
import 'package:cy_shine_music/features/shell/player_transition.dart';
import 'package:cy_shine_music/features/shell/shell_navigation.dart';
import 'package:cy_shine_music/features/shell/widgets/bottom_toolbar.dart';
import 'package:cy_shine_music/features/shell/widgets/mini_player_bar.dart';
import 'package:cy_shine_music/features/songs/songs_toolbar_state.dart';
import 'package:cy_shine_music/router.dart';
import 'package:cy_shine_music/theme/app_theme.dart';

final _miniPlayer = find.byKey(const ValueKey('native-mini-player'));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('legacy pager remains the default and settings switch live', (
    tester,
  ) async {
    final harness = await _pumpApp(tester, native: false);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byTooltip('播放页'), findsOneWidget);

    await tester.drag(find.byType(BottomToolbar), const Offset(-180, 0));
    await _pumpUi(tester);
    expect(find.byType(MiniPlayerBar), findsOneWidget);
    expect(harness.controller.nextCalls, 0);
    await tester.drag(find.byType(BottomToolbar), const Offset(180, 0));
    await _pumpUi(tester);
    expect(find.byTooltip('播放页'), findsOneWidget);

    final setting = find.descendant(
      of: find.byKey(const ValueKey('use-native-navigation-setting')),
      matching: find.byType(Switch),
    );
    await tester.ensureVisible(setting);
    await _pumpUi(tester);
    await tester.tap(setting);
    await _pumpUi(tester);
    expect(harness.location, '/settings');
    expect(find.byType(BottomToolbar), findsNothing);
    expect(find.byType(NavigationBar).hitTestable(), findsOneWidget);
    expect(_miniPlayer.hitTestable(), findsOneWidget);
    expect(harness.controller.snapshot.track?.id, _track.id);
    expect(harness.controller.snapshot.playing, isTrue);

    await tester.ensureVisible(setting);
    await _pumpUi(tester);
    await tester.tap(setting);
    await _pumpUi(tester);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byTooltip('播放页'), findsOneWidget);
    expect(harness.location, '/settings');
    expect(harness.controller.snapshot.playing, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'native player is visible for tracks and loading, including pause',
    (tester) async {
      final harness = await _pumpApp(tester, initialState: const PlayerState());
      expect(find.byType(NavigationDestination), findsNWidgets(3));
      expect(find.byTooltip('播放页'), findsNothing);
      expect(_miniPlayer, findsNothing);

      harness.controller.seed(const PlayerState(loading: true));
      await _pumpUi(tester);
      expect(_miniPlayer.hitTestable(), findsOneWidget);
      harness.controller.seed(_playing.copyWith(playing: false));
      await _pumpUi(tester);
      expect(_miniPlayer.hitTestable(), findsOneWidget);

      harness.controller.seed(const PlayerState());
      await _pumpUi(tester);
      expect(_miniPlayer, findsNothing);
      expect(find.byType(NavigationBar).hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'native controls stay fixed while scrolling and reserve content space',
    (tester) async {
      await _pumpApp(tester);
      final playerRect = tester.getRect(_miniPlayer);
      final navigationRect = tester.getRect(find.byType(NavigationBar));
      expect(
        tester.getCenter(find.byType(MiniPlayerBar)).dy,
        closeTo(playerRect.center.dy, 0.01),
      );
      expect(playerRect.bottom, lessThan(navigationRect.top));
      expect(
        tester.getBottomLeft(find.byType(SettingsPage)).dy,
        lessThanOrEqualTo(navigationRect.top),
      );
      expect(
        tester.getBottomLeft(find.byType(SettingsPage)).dy,
        greaterThan(playerRect.top),
      );

      await tester.drag(
        find.descendant(
          of: find.byType(SettingsPage),
          matching: find.byType(CustomScrollView),
        ),
        const Offset(0, -450),
      );
      await _pumpUi(tester);
      expect(tester.getRect(_miniPlayer), playerRect);
      expect(tester.getRect(find.byType(NavigationBar)), navigationRect);
      expect(_miniPlayer.hitTestable(), findsOneWidget);
      await _tapTab(tester, '发现');
      final categoryFab = find.byKey(const ValueKey('discovery-category-fab'));
      expect(categoryFab.hitTestable(), findsOneWidget);
      expect(
        tester.getBottomLeft(categoryFab).dy,
        lessThan(tester.getTopLeft(_miniPlayer).dy),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'native swipes change tracks once without navigating or opening player',
    (tester) async {
      final harness = await _pumpApp(tester);
      await tester.drag(_miniPlayer, const Offset(-130, 0));
      await _pumpUi(tester);
      expect(harness.controller.nextCalls, 1);
      expect(harness.controller.previousCalls, 0);
      expect(harness.location, '/settings');

      await tester.drag(_miniPlayer, const Offset(130, 0));
      await _pumpUi(tester);
      expect(harness.controller.previousCalls, 1);
      expect(harness.location, '/settings');

      await tester.drag(_miniPlayer, const Offset(-25, 0));
      final gesture = await tester.startGesture(tester.getCenter(_miniPlayer));
      await gesture.moveBy(const Offset(-130, 0));
      await gesture.cancel();
      await _pumpUi(tester);
      expect(harness.controller.nextCalls, 1);

      harness.controller.seed(_playing.copyWith(loading: true));
      await _pumpUi(tester);
      await tester.drag(_miniPlayer, const Offset(-130, 0));
      await _pumpUi(tester);
      expect(harness.controller.nextCalls, 1);
      expect(harness.location, '/settings');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'native tabs restore child routes and active taps return to the root',
    (tester) async {
      final harness = await _pumpApp(
        tester,
        initialLocation: '/settings/webdav',
      );
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        2,
      );
      await _tapTab(tester, '歌曲');
      expect(harness.location, '/songs');
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        1,
      );
      await _tapTab(tester, '设置');
      expect(harness.location, '/settings/webdav');
      await _tapTab(tester, '设置');
      expect(harness.location, '/settings');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('native player tap and pulls preserve the full return URI', (
    tester,
  ) async {
    const origin = '/settings/webdav?section=sync';
    final harness = await _pumpApp(tester, initialLocation: origin);
    await tester.tap(find.byTooltip('打开播放页'));
    await _pumpUi(tester);
    expect(harness.location, '/player');
    expect(
      tester.widget<PlayerPage>(find.byType(PlayerPage)).returnLocation,
      origin,
    );
    expect(find.byType(NavigationBar).hitTestable(), findsNothing);
    await tester.binding.handlePopRoute();
    await _pumpUi(tester);
    expect(harness.location, origin);

    final playerElement = tester.element(find.byType(PlayerPage));
    final shortPull = await tester.startGesture(tester.getCenter(_miniPlayer));
    await shortPull.moveBy(const Offset(0, -20));
    await shortPull.moveBy(const Offset(0, -30));
    await shortPull.up();
    await _pumpUi(tester);
    expect(harness.location, origin);
    expect(_miniPlayer.hitTestable(), findsOneWidget);

    final longPull = await tester.startGesture(tester.getCenter(_miniPlayer));
    await longPull.moveBy(const Offset(0, -20));
    await longPull.moveBy(const Offset(0, -500));
    await longPull.up();
    await _pumpUi(tester);
    expect(harness.location, '/player');
    expect(tester.element(find.byType(PlayerPage)), same(playerElement));
    await tester.binding.handlePopRoute();
    await _pumpUi(tester);
    expect(harness.location, origin);
    expect(harness.controller.nextCalls, 0);
    expect(harness.controller.previousCalls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('capsule morph keeps one cover and the originating page alive', (
    tester,
  ) async {
    final harness = await _pumpApp(tester);
    final originalPage = tester.element(find.byType(SettingsPage));
    final gesture = await tester.startGesture(tester.getCenter(_miniPlayer));
    await tester.pump();
    await tester.pump();
    final transition = tester
        .widget<PlayerTransitionScope>(find.byType(PlayerTransitionScope))
        .transition;
    final source = transition.miniCover!;
    final end = transition.fullCover!;
    await gesture.moveBy(const Offset(0, -20));
    await tester.pump();
    await gesture.moveBy(Offset(0, -transition.travel / 2));
    await tester.pump();
    expect(transition.progress.value, closeTo(.5, .001));
    final shared = tester.getRect(
      find.byKey(const ValueKey('player-shared-cover')),
    );
    expect(
      shared.center.dx,
      closeTo(source.center.dx + .75 * (end.center.dx - source.center.dx), .01),
    );
    expect(
      shared.center.dy,
      closeTo(source.center.dy + .25 * (end.center.dy - source.center.dy), .01),
    );
    for (final anchor in tester.widgetList<PlayerCoverAnchor>(
      find.byType(PlayerCoverAnchor),
    )) {
      final opacity = find
          .descendant(of: find.byWidget(anchor), matching: find.byType(Opacity))
          .first;
      expect(tester.widget<Opacity>(opacity).opacity, 0);
    }
    await gesture.up();
    await _pumpUi(tester);
    expect(harness.location, '/player');
    expect(tester.element(find.byType(SettingsPage)), same(originalPage));
    expect(find.byKey(const ValueKey('player-shared-cover')), findsNothing);

    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(harness.location, '/player');
    expect(transition.progress.value, inExclusiveRange(0, 1));
    expect(tester.element(find.byType(SettingsPage)), same(originalPage));
    await _pumpUi(tester);
    expect(harness.location, '/settings');
    expect(tester.element(find.byType(SettingsPage)), same(originalPage));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a closing spring can be grabbed and reversed without a stale pop',
    (tester) async {
      final harness = await _pumpApp(tester);
      await tester.tap(find.byTooltip('打开播放页'));
      await _pumpUi(tester);
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('player-shared-cover'))),
      );
      await gesture.moveBy(const Offset(0, -20));
      await tester.pump();
      await gesture.moveBy(const Offset(0, -220));
      await tester.pump();
      await gesture.up();
      await _pumpUi(tester);
      expect(harness.location, '/player');
      expect(
        tester.widget<PlayerPage>(find.byType(PlayerPage)).progress.value,
        1,
      );
      await tester.binding.handlePopRoute();
      await _pumpUi(tester);
      expect(harness.location, '/settings');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'native controls recover after keyboard and search-player return',
    (tester) async {
      final harness = await _pumpApp(tester, initialLocation: '/songs/search');
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      await _pumpUi(tester);
      expect(_miniPlayer.hitTestable(), findsNothing);
      expect(find.byType(NavigationBar).hitTestable(), findsNothing);
      tester.view.resetViewInsets();
      await _pumpUi(tester);
      expect(_miniPlayer.hitTestable(), findsOneWidget);

      await tester.tap(find.byType(SearchBar));
      await _pumpUi(tester);
      expect(_miniPlayer.hitTestable(), findsNothing);
      openPlayer(
        tester.element(find.byType(SearchBar)),
        returnLocation: '/songs/search',
      );
      await _pumpUi(tester);
      await tester.binding.handlePopRoute();
      await _pumpUi(tester);
      expect(harness.location, '/songs/search');
      expect(
        tester.widget<SearchBar>(find.byType(SearchBar)).focusNode?.hasFocus,
        isFalse,
      );
      expect(_miniPlayer.hitTestable(), findsOneWidget);
      expect(find.byType(NavigationBar).hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [const Size(320, 640), const Size(900, 500)]) {
    testWidgets('native controls fit $size with safe area and large text', (
      tester,
    ) async {
      await _pumpApp(
        tester,
        size: size,
        textScale: 2,
        initialLocation: '/downloads',
      );
      final playerRect = tester.getRect(_miniPlayer);
      final navigationRect = tester.getRect(find.byType(NavigationBar));
      expect(playerRect.left, greaterThanOrEqualTo(14));
      expect(
        tester.getCenter(find.byType(MiniPlayerBar)).dy,
        closeTo(playerRect.center.dy, 0.01),
      );
      expect(playerRect.right, lessThanOrEqualTo(size.width - 14));
      expect(playerRect.bottom, lessThan(navigationRect.top));
      expect(navigationRect.bottom, size.height);
      expect(tester.takeException(), isNull);
    });
  }
}

const _track = PlayerTrack(
  id: 'native-navigation-test',
  kind: PlayerTrackKind.localFile,
  title: '当前歌曲',
  artist: '测试歌手',
  album: '测试专辑',
  sourceLabel: '本地',
  qualityLabel: 'flac',
);
const _playing = PlayerState(
  track: _track,
  playing: true,
  duration: Duration(minutes: 3),
  canPlayPrevious: true,
  canPlayNext: true,
);

class _PlayerController extends PlayerController {
  _PlayerController(super.ref, PlayerState initial) {
    state = initial;
  }

  int nextCalls = 0;
  int previousCalls = 0;
  PlayerState get snapshot => state;
  void seed(PlayerState value) => state = value;

  @override
  Future<void> playNext() async {
    nextCalls++;
  }

  @override
  Future<void> playPrevious() async {
    previousCalls++;
  }
}

class _Harness {
  const _Harness(this.router, this.controller);
  final GoRouter router;
  final _PlayerController controller;
  String get location => router.routeInformationProvider.value.uri.toString();
}

Future<_Harness> _pumpApp(
  WidgetTester tester, {
  bool native = true,
  String initialLocation = '/settings',
  PlayerState initialState = _playing,
  Size size = const Size(390, 844),
  double textScale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  tester.view.padding = const FakeViewPadding(bottom: 24);
  tester.view.viewPadding = const FakeViewPadding(bottom: 24);
  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
    tester.view.resetPadding();
    tester.view.resetViewPadding();
    tester.view.resetViewInsets();
  });
  SharedPreferences.setMockInitialValues({
    if (native) 'use_native_navigation': true,
  });
  final prefs = await SharedPreferences.getInstance();
  final audioHandler = PlayerAudioHandler();
  final router = createAppRouter(initialLocation: initialLocation);
  late _PlayerController controller;
  addTearDown(() {
    router.dispose();
    unawaited(audioHandler.disposeHandler());
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        playerAudioHandlerProvider.overrideWithValue(audioHandler),
        playerControllerProvider.overrideWith(
          (ref) => controller = _PlayerController(ref, initialState),
        ),
        songsSearchAutoFocusProvider.overrideWith((ref) => false),
      ],
      child: MaterialApp.router(
        theme: AppTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        routerConfig: router,
      ),
    ),
  );
  await _pumpUi(tester);
  // Audio-handler initial streams settle before applying the test transport state.
  ProviderScope.containerOf(
    tester.element(find.byType(AppShell)),
  ).read(playerControllerProvider);
  controller.seed(initialState);
  await _pumpUi(tester);
  return _Harness(router, controller);
}

Future<void> _tapTab(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
  );
  await _pumpUi(tester);
}

Future<void> _pumpUi(WidgetTester tester) async {
  for (var index = 0; index < 12; index++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
