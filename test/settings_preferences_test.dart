import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cy_shine_music/core/api/dio_factory.dart';
import 'package:cy_shine_music/core/models/enums.dart';
import 'package:cy_shine_music/core/models/music_info.dart';
import 'package:cy_shine_music/core/storage/settings_store.dart';
import 'package:cy_shine_music/features/search/widgets/source_filter_chips.dart';
import 'package:cy_shine_music/features/settings/settings_page.dart';
import 'package:cy_shine_music/features/settings/settings_section.dart';
import 'package:cy_shine_music/features/settings/widgets/settings_action.dart';
import 'package:cy_shine_music/features/settings/widgets/settings_style.dart';
import 'package:cy_shine_music/theme/app_theme.dart';
import 'package:cy_shine_music/theme/color_style.dart';
import 'package:prism_ui/prism_ui.dart' as prism;

import 'helpers/prism_test_environment.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'settings default to four search sources and highest quality preferences',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final container = _settingsContainer(prefs);
      addTearDown(container.dispose);

      final settings = container.read(settingsProvider);

      expect(settings.enabledSearchSources, kDefaultEnabledSearchSources);
      expect(settings.enabledSearchSources, isNot(contains(MusicSource.mg)));
      expect(settings.onlinePlaybackQuality, OnlinePlaybackQuality.highest);
      expect(settings.batchDownloadQuality, OnlinePlaybackQuality.highest);
      expect(settings.showMiniLyrics, isTrue);
      expect(settings.allowMixWithOthers, isFalse);
      expect(settings.autoPlayOnStartup, isFalse);
      expect(settings.grooveShiftEnabled, isFalse);
      expect(settings.bluetoothLyricEnabled, isFalse);
      expect(settings.bluetoothFullLyricEnabled, isFalse);
      expect(settings.bluetoothLyricNoticeSeen, isFalse);
      expect(settings.useNativeNavigation, isFalse);
      expect(settings.localMusicDir, settings.downloadDir);
      expect(settings.useBuiltInSourceFilePicker, isFalse);
    },
  );

  test('WebDAV appearance restore changes only appearance settings', () async {
    final prefs = await SharedPreferences.getInstance();
    final container = _settingsContainer(prefs);
    addTearDown(container.dispose);
    final notifier = container.read(settingsProvider.notifier);
    await notifier.setOnlinePlaybackQuality(OnlinePlaybackQuality.lossless);

    await notifier.applyAppearanceFromSync({
      'themeMode': 'dark',
      'themeSeedArgb': 0xFF123456,
      'useDynamicColor': true,
    });

    final restored = container.read(settingsProvider);
    expect(restored.themeMode, ThemeMode.dark);
    expect(restored.themeSeed.toARGB32(), 0xFF123456);
    expect(restored.useDynamicColor, isTrue);
    expect(restored.onlinePlaybackQuality, OnlinePlaybackQuality.lossless);
  });

  test('color style persists and defaults to soft', () async {
    final prefs = await SharedPreferences.getInstance();
    final container = _settingsContainer(prefs);
    expect(container.read(settingsProvider).colorStyle, AppColorStyle.soft);

    await container
        .read(settingsProvider.notifier)
        .setColorStyle(AppColorStyle.vivid);
    container.dispose();

    final restored = _settingsContainer(prefs);
    addTearDown(restored.dispose);
    expect(restored.read(settingsProvider).colorStyle, AppColorStyle.vivid);
  });

  test(
    'source file picker preference survives restart and appearance sync',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final container = _settingsContainer(prefs);
      await container
          .read(settingsProvider.notifier)
          .setUseBuiltInSourceFilePicker(true);
      await container.read(settingsProvider.notifier).applyAppearanceFromSync({
        'themeMode': 'dark',
        'themeSeedArgb': 0xFF123456,
        'useDynamicColor': false,
      });
      expect(
        container.read(settingsProvider).useBuiltInSourceFilePicker,
        isTrue,
      );
      container.dispose();

      final restored = _settingsContainer(prefs);
      addTearDown(restored.dispose);
      expect(
        restored.read(settingsProvider).useBuiltInSourceFilePicker,
        isTrue,
      );
      await restored
          .read(settingsProvider.notifier)
          .setUseBuiltInSourceFilePicker(false);
      expect(prefs.getBool('use_built_in_source_file_picker'), isFalse);
    },
  );

  test('appearance sync round-trips the color style', () async {
    final prefs = await SharedPreferences.getInstance();
    final container = _settingsContainer(prefs);
    addTearDown(container.dispose);
    final notifier = container.read(settingsProvider.notifier);

    await notifier.setColorStyle(AppColorStyle.faithful);
    expect(
      notifier.exportAppearanceForSync()['colorStyle'],
      AppColorStyle.faithful.code,
    );

    await notifier.applyAppearanceFromSync({
      'themeMode': 'light',
      'themeSeedArgb': 0xFF00BCD4,
      'colorStyle': AppColorStyle.creative.code,
      'useDynamicColor': false,
    });
    expect(container.read(settingsProvider).colorStyle, AppColorStyle.creative);
  });

  test(
    'appearance payload without a color style keeps the local one',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final container = _settingsContainer(prefs);
      addTearDown(container.dispose);
      final notifier = container.read(settingsProvider.notifier);
      await notifier.setColorStyle(AppColorStyle.vivid);

      // 旧版本写的备份没有 colorStyle 字段，不应被当成损坏数据。
      await notifier.applyAppearanceFromSync({
        'themeMode': 'dark',
        'themeSeedArgb': 0xFF123456,
        'useDynamicColor': false,
      });

      final restored = container.read(settingsProvider);
      expect(restored.colorStyle, AppColorStyle.vivid);
      expect(restored.themeMode, ThemeMode.dark);
    },
  );

  test('appearance sync rejects an unknown color style', () async {
    final prefs = await SharedPreferences.getInstance();
    final container = _settingsContainer(prefs);
    addTearDown(container.dispose);

    expect(
      () => container.read(settingsProvider.notifier).applyAppearanceFromSync({
        'themeMode': 'dark',
        'themeSeedArgb': 0xFF123456,
        'colorStyle': 'not-a-style',
        'useDynamicColor': false,
      }),
      throwsA(isA<FormatException>()),
    );
  });

  test('native navigation is opt-in and persists across restarts', () async {
    final prefs = await SharedPreferences.getInstance();
    final container = _settingsContainer(prefs);
    expect(AppSettings.fallback.useNativeNavigation, isFalse);
    expect(container.read(settingsProvider).useNativeNavigation, isFalse);
    await container
        .read(settingsProvider.notifier)
        .setUseNativeNavigation(true);
    container.dispose();

    final restored = _settingsContainer(prefs);
    expect(restored.read(settingsProvider).useNativeNavigation, isTrue);
    await restored
        .read(settingsProvider.notifier)
        .setUseNativeNavigation(false);
    restored.dispose();

    final disabled = _settingsContainer(prefs);
    addTearDown(disabled.dispose);
    expect(disabled.read(settingsProvider).useNativeNavigation, isFalse);
  });

  test(
    'navigation mode persists across restarts and supports dual capsule',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final container = _settingsContainer(prefs);
      expect(
        AppSettings.fallback.navigationMode,
        AppNavigationMode.singleCapsule,
      );
      expect(
        container.read(settingsProvider).navigationMode,
        AppNavigationMode.singleCapsule,
      );

      await container
          .read(settingsProvider.notifier)
          .setNavigationMode(AppNavigationMode.dualCapsule);
      container.dispose();

      final restored = _settingsContainer(prefs);
      expect(
        restored.read(settingsProvider).navigationMode,
        AppNavigationMode.dualCapsule,
      );
      expect(restored.read(settingsProvider).useNativeNavigation, isFalse);

      await restored
          .read(settingsProvider.notifier)
          .setNavigationMode(AppNavigationMode.native);
      restored.dispose();

      final nativeMode = _settingsContainer(prefs);
      addTearDown(nativeMode.dispose);
      expect(
        nativeMode.read(settingsProvider).navigationMode,
        AppNavigationMode.native,
      );
      expect(nativeMode.read(settingsProvider).useNativeNavigation, isTrue);
    },
  );

  test('GrooveShift switch persists under its current name', () async {
    final prefs = await SharedPreferences.getInstance();
    final container = _settingsContainer(prefs);
    expect(container.read(settingsProvider).grooveShiftEnabled, isFalse);

    await container.read(settingsProvider.notifier).setGrooveShiftEnabled(true);
    expect(prefs.getBool('groove_shift_enabled'), isTrue);
    container.dispose();

    final restored = _settingsContainer(prefs);
    addTearDown(restored.dispose);
    expect(restored.read(settingsProvider).grooveShiftEnabled, isTrue);
  });

  test('GrooveShift can be disabled after restart', () async {
    SharedPreferences.setMockInitialValues({'groove_shift_enabled': true});
    final prefs = await SharedPreferences.getInstance();
    final container = _settingsContainer(prefs);
    expect(container.read(settingsProvider).grooveShiftEnabled, isTrue);
    await container
        .read(settingsProvider.notifier)
        .setGrooveShiftEnabled(false);
    container.dispose();

    final restored = _settingsContainer(prefs);
    addTearDown(restored.dispose);
    expect(restored.read(settingsProvider).grooveShiftEnabled, isFalse);
  });

  test('player preferences persist', () async {
    final prefs = await SharedPreferences.getInstance();
    final container = _settingsContainer(prefs);
    final notifier = container.read(settingsProvider.notifier);

    await notifier.setShowMiniLyrics(false);
    await notifier.setAllowMixWithOthers(true);
    await notifier.setBluetoothLyricEnabled(true);
    await notifier.setBluetoothFullLyricEnabled(true);
    await notifier.markBluetoothLyricNoticeSeen();
    container.dispose();

    final restored = _settingsContainer(prefs);
    addTearDown(restored.dispose);
    final settings = restored.read(settingsProvider);
    expect(settings.showMiniLyrics, isFalse);
    expect(settings.allowMixWithOthers, isTrue);
    expect(settings.bluetoothLyricEnabled, isTrue);
    expect(settings.bluetoothFullLyricEnabled, isTrue);
    expect(settings.bluetoothLyricNoticeSeen, isTrue);
  });

  test('auto-play-on-startup preference persists across restarts', () async {
    final prefs = await SharedPreferences.getInstance();
    final container = _settingsContainer(prefs);
    final notifier = container.read(settingsProvider.notifier);

    await notifier.setAutoPlayOnStartup(true);
    container.dispose();

    final restored = _settingsContainer(prefs);
    addTearDown(restored.dispose);
    expect(restored.read(settingsProvider).autoPlayOnStartup, isTrue);
  });

  testWidgets('bluetooth lyric warning is shown only on first enable', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final prefs = await SharedPreferences.getInstance();
    final container = _settingsContainer(prefs);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          builder: buildPrismTestEnvironment,
          theme: AppTheme.light(),
          home: const SettingsPage(section: SettingsSection.playback),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final row = find.byKey(const ValueKey('bluetooth-lyric-setting'));
    final toggle = find.descendant(
      of: row,
      matching: find.byType(prism.Switch),
    );
    await tester.ensureVisible(toggle);
    await tester.pumpAndSettle();
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(find.text('蓝牙歌词提示'), findsOneWidget);
    await tester.tap(find.text('我知道了'));
    await tester.pumpAndSettle();
    expect(container.read(settingsProvider).bluetoothLyricEnabled, isTrue);
    expect(container.read(settingsProvider).bluetoothLyricNoticeSeen, isTrue);

    await tester.tap(toggle);
    await tester.pumpAndSettle();
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(find.text('蓝牙歌词提示'), findsNothing);
    expect(container.read(settingsProvider).bluetoothLyricEnabled, isTrue);
  });

  testWidgets('switch settings align with actions and keep vertical spacing', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: buildPrismTestEnvironment,
        theme: AppTheme.light(),
        home: Scaffold(
          body: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SettingsAction(
                key: const ValueKey('reference-setting-action'),
                icon: Icons.search_rounded,
                title: '参考设置项',
                subtitle: '参考说明',
                onTap: () {},
              ),
              SettingsSwitchAction(
                key: const ValueKey('first-switch-setting'),
                icon: Icons.bluetooth_audio_rounded,
                title: '显示蓝牙歌词',
                subtitle: '蓝牙歌词说明',
                value: false,
                onChanged: (_) {},
              ),
              SettingsSwitchAction(
                key: const ValueKey('second-switch-setting'),
                icon: Icons.lyrics_rounded,
                title: '显示完整蓝牙歌词',
                subtitle: '完整歌词说明',
                value: false,
                onChanged: (_) {},
              ),
            ],
          ),
        ),
      ),
    );

    Finder bubbleWithin(Key key) => find.descendant(
      of: find.byKey(key),
      matching: find.byType(SettingsSymbolBubble),
    );

    final referenceRect = tester.getRect(
      bubbleWithin(const ValueKey('reference-setting-action')),
    );
    final firstRect = tester.getRect(
      bubbleWithin(const ValueKey('first-switch-setting')),
    );
    final secondRect = tester.getRect(
      bubbleWithin(const ValueKey('second-switch-setting')),
    );
    expect(firstRect.left, referenceRect.left);
    expect(secondRect.left, referenceRect.left);
    expect(secondRect.top - firstRect.bottom, greaterThanOrEqualTo(24));
    expect(tester.takeException(), isNull);
  });

  test('legacy resolver setting is removed', () async {
    SharedPreferences.setMockInitialValues({
      'base_url': 'https://legacy.example.com',
    });
    final prefs = await SharedPreferences.getInstance();
    final container = _settingsContainer(prefs);
    addTearDown(container.dispose);

    container.read(settingsProvider);
    await Future<void>.delayed(Duration.zero);
    expect(prefs.getString('base_url'), isNull);
  });

  testWidgets(
    'settings categories expose related controls instead of resolver settings',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final prefs = await SharedPreferences.getInstance();
      final container = _settingsContainer(prefs);
      addTearDown(container.dispose);

      Future<void> pumpSection(SettingsSection section) async {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              builder: buildPrismTestEnvironment,
              theme: AppTheme.light(),
              home: SettingsPage(section: section),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await pumpSection(SettingsSection.network);
      expect(find.text('音源管理'), findsOneWidget);
      final pickerSetting = find.byKey(
        const ValueKey('source-file-picker-setting'),
      );
      await tester.tap(
        find.descendant(of: pickerSetting, matching: find.byType(prism.Switch)),
      );
      await tester.pumpAndSettle();
      expect(
        container.read(settingsProvider).useBuiltInSourceFilePicker,
        isTrue,
      );
      expect(find.text('WebDAV 同步'), findsOneWidget);
      expect(find.text('URL 解析服务器'), findsNothing);
      expect(find.text('解析服务器健康检查'), findsNothing);
      await pumpSection(SettingsSection.playback);
      expect(find.text('允许与其他 APP 共同播放'), findsOneWidget);
      await pumpSection(SettingsSection.downloads);
      expect(find.text('批量下载音质'), findsOneWidget);
      expect(find.text('目录'), findsOneWidget);
      expect(find.text('浏览U盘'), findsOneWidget);
      expect(find.text('添加 U 盘文件夹'), findsOneWidget);
      expect(find.text('下载位置'), findsOneWidget);
      await pumpSection(SettingsSection.about);
      expect(find.text('检查更新'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'search sources and playback quality persist and reject an empty set',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final container = _settingsContainer(prefs);
      final notifier = container.read(settingsProvider.notifier);

      expect(
        await notifier.setSearchSourceEnabled(MusicSource.mg, true),
        isTrue,
      );
      await notifier.setOnlinePlaybackQuality(OnlinePlaybackQuality.lossless);
      await notifier.setBatchDownloadQuality(OnlinePlaybackQuality.high);
      for (final source in [MusicSource.kg, MusicSource.tx, MusicSource.wy]) {
        expect(await notifier.setSearchSourceEnabled(source, false), isTrue);
      }
      expect(
        await notifier.setSearchSourceEnabled(MusicSource.kw, false),
        isTrue,
      );
      expect(
        await notifier.setSearchSourceEnabled(MusicSource.mg, false),
        isFalse,
      );

      expect(container.read(settingsProvider).enabledSearchSources, {
        MusicSource.mg,
      });
      container.dispose();

      final restored = _settingsContainer(prefs);
      addTearDown(restored.dispose);
      expect(restored.read(settingsProvider).enabledSearchSources, {
        MusicSource.mg,
      });
      expect(
        restored.read(settingsProvider).onlinePlaybackQuality,
        OnlinePlaybackQuality.lossless,
      );
      expect(
        restored.read(settingsProvider).batchDownloadQuality,
        OnlinePlaybackQuality.high,
      );
    },
  );

  test(
    'local music scan folder follows download folder until customized',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final container = _settingsContainer(prefs);
      final notifier = container.read(settingsProvider.notifier);

      await notifier.setDownloadDir('/storage/emulated/0/Music/Downloads');
      expect(
        container.read(settingsProvider).localMusicDir,
        '/storage/emulated/0/Music/Downloads',
      );

      await notifier.setLocalMusicDir('/storage/1234-5678/Music');
      await notifier.setDownloadDir('/storage/emulated/0/Music/NewDownloads');

      expect(
        container.read(settingsProvider).downloadDir,
        '/storage/emulated/0/Music/NewDownloads',
      );
      expect(
        container.read(settingsProvider).localMusicDir,
        '/storage/1234-5678/Music',
      );
      container.dispose();

      final restored = _settingsContainer(prefs);
      addTearDown(restored.dispose);
      expect(
        restored.read(settingsProvider).localMusicDir,
        '/storage/1234-5678/Music',
      );
    },
  );

  test(
    'saved search source codes are ordered, deduplicated, and sanitized',
    () {
      expect(decodeEnabledSearchSources(['mg', 'unknown', 'mg', 'all', 'kw']), {
        MusicSource.kw,
        MusicSource.mg,
      });
      expect(decodeEnabledSearchSources([]), kDefaultEnabledSearchSources);
    },
  );

  group('online playback quality resolution', () {
    test('keeps highest behavior and honors an exact preference', () {
      final music = _musicWithQualities([
        Quality.k128,
        Quality.flac,
        Quality.k320,
      ]);

      expect(
        music.playbackQualityFor(OnlinePlaybackQuality.highest),
        Quality.flac,
      );
      expect(
        music.playbackQualityFor(OnlinePlaybackQuality.high),
        Quality.k320,
      );
    });

    test(
      'falls down first, then up when the preferred quality is unavailable',
      () {
        expect(
          _musicWithQualities([
            Quality.hires,
            Quality.k320,
            Quality.k128,
          ]).playbackQualityFor(OnlinePlaybackQuality.lossless),
          Quality.k320,
        );
        expect(
          _musicWithQualities([
            Quality.flac,
          ]).playbackQualityFor(OnlinePlaybackQuality.high),
          Quality.flac,
        );
      },
    );

    test('uses 128K when a track has no advertised qualities', () {
      expect(
        _musicWithQualities(
          const [],
        ).playbackQualityFor(OnlinePlaybackQuality.hires),
        Quality.k128,
      );
    });
  });

  testWidgets(
    'source filter stays full width and slides smoothly between sources',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final prefs = await SharedPreferences.getInstance();
      final container = _settingsContainer(prefs);
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            builder: buildPrismTestEnvironment,
            theme: AppTheme.light(),
            home: const Scaffold(body: SourceFilterChips()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('咪咕'), findsNothing);
      final defaultWidth = tester
          .getSize(find.byKey(const ValueKey('search-source-filter')))
          .width;
      final scaffoldWidth = tester.getSize(find.byType(Scaffold)).width;
      expect(defaultWidth, closeTo(scaffoldWidth - 24, 0.01));

      final indicator = find.byKey(const ValueKey('search-source-indicator'));
      final initialLeft = tester.getTopLeft(indicator).dx;
      await tester.tap(find.byKey(const ValueKey('search-source-tx')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      final middleLeft = tester.getTopLeft(indicator).dx;
      expect(middleLeft, greaterThan(initialLeft));
      await tester.pumpAndSettle();
      final finalLeft = tester.getTopLeft(indicator).dx;
      expect(middleLeft, lessThan(finalLeft));

      await container
          .read(settingsProvider.notifier)
          .setSearchSourceEnabled(MusicSource.mg, true);
      await tester.pumpAndSettle();

      expect(find.text('咪咕'), findsOneWidget);
      final expandedWidth = tester
          .getSize(find.byKey(const ValueKey('search-source-filter')))
          .width;
      expect(expandedWidth, closeTo(defaultWidth, 0.01));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Prism menus apply network and quality choices and can reopen', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = _settingsContainer(await SharedPreferences.getInstance());
    addTearDown(container.dispose);

    Future<void> pumpSection(SettingsSection section) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            builder: buildPrismTestEnvironment,
            theme: AppTheme.light(),
            home: SettingsPage(section: section),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await pumpSection(SettingsSection.network);
    final anchor = find.byKey(const ValueKey('network-adapter-menu-anchor'));
    await tester.tap(anchor);
    await tester.pumpAndSettle();
    expect(find.byType(prism.PopupMenu), findsOneWidget);
    expect(
      tester
          .widget<prism.PopupMenu>(find.byType(prism.PopupMenu))
          .items
          .singleWhere((item) => item.label == NetworkAdapterMode.system.label)
          .checked,
      isTrue,
    );
    await tester.tap(find.text(NetworkAdapterMode.io.label));
    await tester.pumpAndSettle();
    expect(
      container.read(settingsProvider).networkAdapterMode,
      NetworkAdapterMode.io,
    );
    expect(find.byType(prism.PopupMenu), findsNothing);
    await tester.tap(anchor);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<prism.PopupMenu>(find.byType(prism.PopupMenu))
          .items
          .singleWhere((item) => item.label == NetworkAdapterMode.io.label)
          .checked,
      isTrue,
    );
    expect(await tester.binding.handlePopRoute(), isTrue);
    await tester.pumpAndSettle();

    await pumpSection(SettingsSection.playback);
    final qualityAnchor = find.byKey(
      const ValueKey('online-quality-menu-anchor'),
    );
    await tester.tap(qualityAnchor);
    await tester.pumpAndSettle();
    expect(find.byType(prism.PopupMenu), findsOneWidget);
    await tester.tap(find.text(OnlinePlaybackQuality.lossless.label));
    await tester.pumpAndSettle();
    expect(
      container.read(settingsProvider).onlinePlaybackQuality,
      OnlinePlaybackQuality.lossless,
    );
    expect(find.byType(prism.PopupMenu), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('search source management stays open for multi-selection', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final prefs = await SharedPreferences.getInstance();
    final container = _settingsContainer(prefs);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          builder: buildPrismTestEnvironment,
          theme: AppTheme.light(),
          home: const SettingsPage(section: SettingsSection.playback),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final anchor = find.byKey(const ValueKey('search-source-menu-anchor'));
    await tester.tap(anchor);
    await tester.pumpAndSettle();
    final panel = find.byType(prism.PopupMenu);
    final miguOption = find.text('咪咕');
    expect(panel, findsOneWidget);
    expect(tester.getSize(panel).width, lessThanOrEqualTo(280));
    await tester.tap(miguOption);
    await tester.pumpAndSettle();

    expect(
      container.read(settingsProvider).enabledSearchSources,
      contains(MusicSource.mg),
    );
    expect(panel, findsOneWidget);
    expect(miguOption, findsOneWidget);
    await tester.tap(miguOption);
    await tester.pumpAndSettle();
    expect(
      container.read(settingsProvider).enabledSearchSources,
      isNot(contains(MusicSource.mg)),
    );
    expect(panel, findsOneWidget);
    expect(await tester.binding.handlePopRoute(), isTrue);
    await tester.pumpAndSettle();
    expect(panel, findsNothing);
    expect(tester.takeException(), isNull);
  });
}

ProviderContainer _settingsContainer(SharedPreferences prefs) {
  return ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
}

MusicInfo _musicWithQualities(List<Quality> qualities) {
  return MusicInfo(
    id: 'quality-test',
    name: 'Quality test',
    singer: 'Tester',
    source: MusicSource.wy,
    interval: '03:00',
    meta: MusicMeta(
      songId: 'quality-test',
      albumName: 'Test album',
      qualitys: [for (final quality in qualities) QualityOption(type: quality)],
      raw: const {},
    ),
    raw: const {},
  );
}
