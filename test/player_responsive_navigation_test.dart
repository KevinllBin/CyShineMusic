import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cy_shine_music/core/models/enums.dart';
import 'package:cy_shine_music/core/models/music_info.dart';
import 'package:cy_shine_music/core/storage/settings_store.dart';
import 'package:cy_shine_music/features/player/player_audio_handler.dart';
import 'package:cy_shine_music/features/player/player_controller.dart';
import 'package:cy_shine_music/features/player/lyric_parser.dart';
import 'package:cy_shine_music/features/player/player_page.dart';
import 'package:cy_shine_music/features/player/widgets/album_cluster.dart';
import 'package:cy_shine_music/features/player/widgets/karaoke_lyrics_view.dart';
import 'package:cy_shine_music/features/player/widgets/lyrics_panel.dart';
import 'package:cy_shine_music/features/shell/shell_route_utils.dart';
import 'package:cy_shine_music/router.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('system back from debug returns to settings', (tester) async {
    final harness = await _pumpRoutedApp(tester, initialLocation: '/debug');

    expect(harness.router.routeInformationProvider.value.uri.path, '/debug');
    expect(await tester.binding.handlePopRoute(), isTrue);
    await _pumpUi(tester);

    expect(harness.router.routeInformationProvider.value.uri.path, '/settings');
    expect(tester.takeException(), isNull);
  });

  testWidgets('music sources remains a valid player return location', (
    tester,
  ) async {
    expect(
      normalizedPlayerReturnLocation('/settings/sources', '/songs'),
      '/settings/sources',
    );

    final harness = await _pumpRoutedApp(tester, initialLocation: '/songs');
    harness.router.go('/player', extra: '/settings/sources');
    await _pumpUi(tester);

    final player = tester.widget<PlayerPage>(find.byType(PlayerPage));
    expect(player.active, isTrue);
    expect(player.returnLocation, '/settings/sources');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'compact remote player keeps title in header and exposes quality action',
    (tester) async {
      final controller = await _pumpPlayer(
        tester,
        size: const Size(390, 844),
        track: const PlayerTrack(
          id: 'tx:remote-song',
          kind: PlayerTrackKind.remote,
          title: '窄屏在线歌曲',
          artist: '不应在封面下重复的歌手',
          album: '测试专辑',
          sourceLabel: 'QQ',
          qualityLabel: '320k',
          availableQualityOptions: [
            QualityOption(type: Quality.k320, size: '9.48 MB'),
            QualityOption(type: Quality.k192),
            QualityOption(type: Quality.k128, size: '3.82 MB'),
          ],
          remoteUrl: 'https://audio.example/remote-song.mp3',
        ),
      );

      expect(
        find.byKey(const ValueKey('player-compact-pager')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('player-wide-layout')), findsNothing);
      expect(find.byType(PageView), findsOneWidget);

      // Track metadata belongs to the header on every compact page and must
      // not be repeated below the cover.
      expect(find.text('窄屏在线歌曲'), findsOneWidget);
      expect(find.text('不应在封面下重复的歌手'), findsOneWidget);
      final title = tester.widget<Text>(
        find.byKey(const ValueKey('player-header-title')),
      );
      final artist = tester.widget<Text>(
        find.byKey(const ValueKey('player-header-artist')),
      );
      expect(title.style?.fontWeight, FontWeight.w500);
      expect(artist.style?.fontSize, lessThan(title.style!.fontSize!));
      expect(artist.style?.fontWeight, FontWeight.w400);

      final source = find.byKey(const ValueKey('player-source-chip'));
      final qualityTag = find.byKey(const ValueKey('player-quality-tag'));
      final quality = find.byKey(const ValueKey('player-quality-button'));
      expect(source, findsOneWidget);
      expect(qualityTag, findsOneWidget);
      expect(
        find.descendant(of: source, matching: find.text('QQ')),
        findsOneWidget,
      );
      expect(quality, findsOneWidget);
      expect(
        find.descendant(of: quality, matching: find.text('320k')),
        findsOneWidget,
      );
      expect(tester.getSize(qualityTag), tester.getSize(source));
      expect(tester.getSize(qualityTag), const Size(80, 28));

      await tester.tap(quality);
      await _pumpUi(tester);

      expect(
        find.byKey(const ValueKey('player-quality-sheet')),
        findsOneWidget,
      );
      expect(find.text('文件大小 9.48 MB'), findsOneWidget);
      expect(find.text('文件大小未知'), findsNothing);
      expect(find.text('较高品质 192K'), findsNothing);
      expect(
        find.byKey(const ValueKey('player-quality-option-192k')),
        findsNothing,
      );
      expect(find.text('文件大小 3.82 MB'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('player-quality-option-128k')),
      );
      await _pumpUi(tester);

      expect(controller.switchedQuality, Quality.k128);
      expect(find.byKey(const ValueKey('player-quality-sheet')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('compact local player uses static quality and local source tag', (
    tester,
  ) async {
    await _pumpPlayer(
      tester,
      size: const Size(390, 844),
      track: const PlayerTrack(
        id: 'local:test-song',
        kind: PlayerTrackKind.localFile,
        title: '窄屏本地歌曲',
        artist: '本地歌手',
        album: '本地专辑',
        sourceLabel: 'QQ',
        qualityLabel: 'FLAC',
        localPath: 'test-song.flac',
      ),
    );

    expect(find.text('窄屏本地歌曲'), findsOneWidget);
    expect(find.text('本地歌手'), findsOneWidget);
    expect(find.byKey(const ValueKey('player-quality-button')), findsNothing);

    final source = find.byKey(const ValueKey('player-source-chip'));
    final quality = find.byKey(const ValueKey('player-quality-tag'));
    expect(source, findsOneWidget);
    expect(quality, findsOneWidget);
    expect(tester.getSize(quality), tester.getSize(source));
    expect(
      find.descendant(of: source, matching: find.text('本地')),
      findsOneWidget,
    );
    expect(find.text('FLAC'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('late audio readiness does not remount loaded lyrics', (
    tester,
  ) async {
    const lyrics = KaraokeLyrics([
      KaraokeLyricLine(startMs: 0, endMs: 3000, text: '已经加载的歌词'),
    ]);
    final controller = await _pumpLyricsPanel(
      tester,
      const PlayerState(lyrics: lyrics),
    );
    final lyricsView = tester.element(find.byType(KaraokeLyricsView));

    controller.setStateForTest(
      const PlayerState(
        track: PlayerTrack(
          id: 'tx:late-audio:remote',
          kind: PlayerTrackKind.remote,
          title: '高音质歌曲',
          artist: '测试歌手',
          album: '测试专辑',
          sourceLabel: 'QQ',
          qualityLabel: 'hires',
          remoteUrl: 'https://audio.example/late.flac',
        ),
        lyrics: lyrics,
        duration: Duration(minutes: 4),
      ),
    );
    await tester.pump();

    expect(find.byType(KaraokeLyricsView), findsOneWidget);
    expect(tester.element(find.byType(KaraokeLyricsView)), same(lyricsView));
    expect(tester.takeException(), isNull);
  });

  testWidgets('lyrics fade before the viewport clips their top and bottom', (
    tester,
  ) async {
    const lyrics = KaraokeLyrics([
      KaraokeLyricLine(startMs: 0, endMs: 3000, text: '第一句歌词'),
      KaraokeLyricLine(startMs: 3000, endMs: 6000, text: '第二句歌词'),
      KaraokeLyricLine(startMs: 6000, endMs: 9000, text: '第三句歌词'),
    ]);
    await _pumpPlayer(
      tester,
      size: const Size(390, 844),
      track: const PlayerTrack(
        id: 'tx:lyrics-edge-fade',
        kind: PlayerTrackKind.remote,
        title: '歌词边缘测试',
        artist: '测试歌手',
        album: '测试专辑',
        sourceLabel: 'QQ',
        qualityLabel: '320k',
        remoteUrl: 'https://audio.example/lyrics-edge-fade.mp3',
      ),
      lyrics: lyrics,
    );
    await tester.drag(
      find.byKey(const ValueKey('player-compact-pager')),
      const Offset(-360, 0),
    );
    await _pumpUi(tester);

    final viewport = find.byType(KaraokeLyricsView);
    final edgeFade = find.byKey(const ValueKey('karaoke-lyrics-edge-fade'));
    final list = find.byKey(const ValueKey('karaoke-lyrics-list'));
    expect(edgeFade, findsOneWidget);
    expect(list, findsOneWidget);
    expect(tester.getRect(edgeFade), tester.getRect(viewport));
    expect(tester.getRect(list), tester.getRect(viewport));
    expect(tester.widget<ShaderMask>(edgeFade).blendMode, BlendMode.dstIn);
    expect(tester.takeException(), isNull);
  });

  testWidgets('wide player renders album and lyrics together without pager', (
    tester,
  ) async {
    await _pumpPlayer(
      tester,
      size: const Size(1024, 600),
      track: const PlayerTrack(
        id: 'wy:wide-song',
        kind: PlayerTrackKind.remote,
        title: '宽屏歌曲',
        artist: '宽屏歌手',
        album: '宽屏专辑',
        sourceLabel: '网易',
        qualityLabel: '无损',
        remoteUrl: 'https://audio.example/wide-song.flac',
      ),
    );

    expect(find.byKey(const ValueKey('player-wide-layout')), findsOneWidget);
    expect(find.byKey(const ValueKey('player-compact-pager')), findsNothing);
    expect(find.byType(PageView), findsNothing);
    expect(find.byType(VerticalDivider), findsNothing);
    expect(find.byType(AlbumPage), findsOneWidget);
    expect(find.byType(LyricsPanel), findsOneWidget);
    expect(find.text('宽屏歌曲'), findsOneWidget);
    expect(find.text('宽屏歌手'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _RouterHarness {
  const _RouterHarness({required this.router});

  final GoRouter router;
}

class _SeededPlayerController extends PlayerController {
  _SeededPlayerController(super.ref, PlayerState initialState) {
    state = initialState;
  }

  Quality? switchedQuality;

  void setStateForTest(PlayerState next) => state = next;

  @override
  Future<bool> switchQuality(Quality quality) async {
    switchedQuality = quality;
    return true;
  }
}

Future<_SeededPlayerController> _pumpLyricsPanel(
  WidgetTester tester,
  PlayerState initialState,
) async {
  final preferences = await SharedPreferences.getInstance();
  final audioHandler = PlayerAudioHandler();
  addTearDown(() => unawaited(audioHandler.disposeHandler()));
  late _SeededPlayerController controller;

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        playerAudioHandlerProvider.overrideWithValue(audioHandler),
        playerControllerProvider.overrideWith(
          (ref) => controller = _SeededPlayerController(ref, initialState),
        ),
      ],
      child: MaterialApp(
        theme: _theme(),
        home: const Scaffold(body: LyricsPanel()),
      ),
    ),
  );
  await _pumpUi(tester);
  return controller;
}

Future<_RouterHarness> _pumpRoutedApp(
  WidgetTester tester, {
  required String initialLocation,
}) async {
  final preferences = await SharedPreferences.getInstance();
  final audioHandler = PlayerAudioHandler();
  final router = createAppRouter(initialLocation: initialLocation);
  addTearDown(router.dispose);
  addTearDown(() => unawaited(audioHandler.disposeHandler()));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        playerAudioHandlerProvider.overrideWithValue(audioHandler),
        playerControllerProvider.overrideWith(
          (ref) => _SeededPlayerController(ref, const PlayerState()),
        ),
      ],
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        theme: _theme(),
        routerConfig: router,
      ),
    ),
  );
  await _pumpUi(tester);
  return _RouterHarness(router: router);
}

Future<_SeededPlayerController> _pumpPlayer(
  WidgetTester tester, {
  required Size size,
  required PlayerTrack track,
  KaraokeLyrics lyrics = const KaraokeLyrics([]),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  });

  final preferences = await SharedPreferences.getInstance();
  final audioHandler = PlayerAudioHandler();
  addTearDown(() => unawaited(audioHandler.disposeHandler()));
  final initialState = PlayerState(
    track: track,
    duration: const Duration(minutes: 3),
    lyrics: lyrics,
  );
  late _SeededPlayerController controller;

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        playerAudioHandlerProvider.overrideWithValue(audioHandler),
        playerControllerProvider.overrideWith(
          (ref) => controller = _SeededPlayerController(ref, initialState),
        ),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: _theme(),
        home: PlayerPage(
          returnLocation: '/songs',
          progress: const AlwaysStoppedAnimation<double>(1),
          active: true,
          onDismissRequested: _ignoreDismiss,
        ),
      ),
    ),
  );
  await _pumpUi(tester);
  return controller;
}

ThemeData _theme() {
  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
  );
}

void _ignoreDismiss([String? target]) {}

Future<void> _pumpUi(WidgetTester tester) async {
  for (var index = 0; index < 12; index++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
