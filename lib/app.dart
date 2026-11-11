import 'dart:async';
import 'dart:io';

// CorePalette is still the public Android palette returned by dynamic_color
// 1.8.x, even though material_color_utilities marks it deprecated internally.
// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:material_color_utilities/material_color_utilities.dart';

import 'core/services/app_logger.dart';
import 'core/services/permission_service.dart';
import 'core/services/saf_storage.dart';
import 'core/services/storage_location.dart';
import 'core/storage/settings_store.dart';
import 'core/sync/webdav_sync_controller.dart';
import 'core/ui/app_toast.dart';
import 'core/ui/car_display_layout.dart';
import 'features/downloads/download_history_store.dart';
import 'core/music_sources/music_source_controller.dart';
import 'features/music_sources/music_source_update_prompt.dart';
import 'features/player/player_controller.dart';
import 'features/playlists/playlist_store.dart';
import 'features/player/music_home_widget_service.dart';
import 'features/songs/local_song_scan_cache.dart';
import 'features/startup/startup_gate.dart';
import 'router.dart';
import 'theme/app_motion.dart';
import 'theme/app_theme.dart';
import 'theme/dynamic_color_scheme.dart';
import 'theme/dynamic_color_status.dart';

class CyShineMusicApp extends ConsumerStatefulWidget {
  const CyShineMusicApp({super.key});

  @override
  ConsumerState<CyShineMusicApp> createState() => _CyShineMusicAppState();
}

class _CyShineMusicAppState extends ConsumerState<CyShineMusicApp>
    with WidgetsBindingObserver {
  Future<CorePalette?>? _corePaletteFuture;
  String? _lastLoggedScheme;
  static const _audioIntentChannel = MethodChannel(
    'cy_shine_music/audio_intent',
  );
  bool _externalAudioReady = false;
  bool _handlingExternalAudio = false;
  bool _externalAudioRequested = false;
  bool _openedExternalAudio = false;
  bool _sourceUpdatePromptsReady = false;
  MusicHomeWidgetService? _homeWidgetService;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _corePaletteFuture = DynamicColorPlugin.getCorePalette();
    if (Platform.isAndroid) {
      final homeWidgetService = ref.read(musicHomeWidgetProvider);
      homeWidgetService.onOpenPlayer = _openWidgetPlayer;
      _homeWidgetService = homeWidgetService;
      _audioIntentChannel.setMethodCallHandler((call) async {
        if (call.method != 'audioAvailable') return;
        _externalAudioRequested = true;
        await _openPendingExternalAudio();
      });
    }
    // Warm persisted library and player state after the first frame, even when
    // the startup screen is skipped.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(downloadHistoryProvider);
      ref.read(musicSourceControllerProvider);
      unawaited(
        ref.read(musicSourceControllerProvider.notifier).checkAllForUpdates(),
      );
      ref.read(webDavSyncControllerProvider);
      ref.read(playerControllerProvider.notifier);
      if (Platform.isAndroid) ref.read(musicHomeWidgetSyncProvider);
      unawaited(_initializeLocalLibrary());
    });
  }

  @override
  void dispose() {
    _homeWidgetService?.onOpenPlayer = null;
    if (Platform.isAndroid) _audioIntentChannel.setMethodCallHandler(null);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _initializeLocalLibrary() async {
    final cache = ref.read(localSongScanCacheProvider);
    final selected = ref.read(settingsProvider).localMusicDirs;
    final directories = <String>[];
    for (final directory in selected) {
      directories.add(
        isContentLocation(directory)
            ? await SafStorage.resolveLocalPath(
                    directory,
                    requireReadable: false,
                  ) ??
                  directory
            : directory,
      );
    }
    if (!mounted) return;
    // Do not overwrite a folder selection changed while migration was pending.
    if (!listEquals(selected, ref.read(settingsProvider).localMusicDirs)) {
      return;
    }
    if (!listEquals(selected, directories)) {
      await ref.read(settingsProvider.notifier).setLocalMusicDirs(directories);
    }
    await cache.ensureScan(directories: directories);
    if (!mounted) return;
    await cache.linkKnownPaths([
      for (final entry in ref.read(downloadHistoryProvider))
        if (entry.savedPath != null) entry.savedPath!,
      for (final playlist in ref.read(localPlaylistsProvider))
        for (final track in playlist.tracks)
          if (track.localPath != null) track.localPath!,
    ]);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (mounted &&
        (state == AppLifecycleState.paused ||
            state == AppLifecycleState.inactive)) {
      unawaited(ref.read(localSongScanCacheProvider).flush());
    }
    if (state != AppLifecycleState.resumed || !mounted) return;
    unawaited(ref.read(webDavSyncControllerProvider.notifier).onAppResumed());
  }

  Future<void> _onStartupReady() async {
    try {
      _externalAudioReady = true;
      await _openPendingExternalAudio();
      await _openWidgetPlayer();
      if (!mounted || _openedExternalAudio) return;
      await _checkPermission();
    } finally {
      if (mounted) setState(() => _sourceUpdatePromptsReady = true);
    }
  }

  Future<void> _openWidgetPlayer() async {
    if (!mounted || !_externalAudioReady) return;
    if (!(_homeWidgetService?.takeOpenPlayerRequest() ?? false)) return;
    final location = appRouter.routeInformationProvider.value.uri;
    if (location.path != '/player') {
      unawaited(appRouter.push<void>('/player', extra: location.toString()));
    }
  }

  Future<void> _openPendingExternalAudio() async {
    if (!Platform.isAndroid ||
        !mounted ||
        !_externalAudioReady ||
        _handlingExternalAudio) {
      return;
    }
    _handlingExternalAudio = true;
    try {
      do {
        _externalAudioRequested = false;
        try {
          final path = await _audioIntentChannel.invokeMethod<String>(
            'takePendingAudio',
          );
          if (!mounted) return;
          if (path == null) continue;
          _openedExternalAudio = true;
          // Check again after playback setup in case another file arrived while
          // the provider was being read or the player's tags were loading.
          _externalAudioRequested = true;
          final player = ref.read(playerControllerProvider.notifier);
          final playback = player.playFromFile(path);
          final location = appRouter.routeInformationProvider.value.uri;
          if (location.path != '/player') {
            unawaited(
              appRouter.push<void>('/player', extra: location.toString()),
            );
          }
          await playback;
        } on MissingPluginException {
          // Other platforms and test engines do not install the Android entry.
          return;
        } catch (error) {
          await AppLogger.write('external-audio', 'open failed: $error');
          if (!mounted) return;
          final context = rootNavigatorKey.currentContext;
          if (context != null && context.mounted) {
            showAppToast(
              context,
              '无法打开音乐文件，请确认文件可访问后重试',
              type: AppToastType.error,
            );
          }
        }
      } while (mounted && _externalAudioRequested);
    } finally {
      _handlingExternalAudio = false;
    }
  }

  Future<bool> _checkPermission() async {
    final granted = await PermissionService.hasAudioLibraryRead();
    await AppLogger.write('app', 'startup permission status granted=$granted');
    if (granted) {
      await PermissionService.markAudioPermissionRequestAttempted();
      return true;
    }
    if (await PermissionService.hasAudioPermissionRequestAttempted()) {
      return true;
    }
    // Wait one frame so the router has a chance to mount its home screen.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final ctx = rootNavigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return false;
    // Remember the explanation itself, including "稍后再说" or dismissal.
    if (await PermissionService.hasAudioPermissionRequestAttempted()) {
      return true;
    }
    await PermissionService.markAudioPermissionRequestAttempted();
    if (!ctx.mounted) return false;
    final shouldRequest = await _showPermissionDialog(ctx);
    if (!shouldRequest) return true;

    final ok = await PermissionService.requestAudioLibraryRead();
    if (ok && mounted) {
      unawaited(
        ref
            .read(localSongScanCacheProvider)
            .refresh(directories: ref.read(settingsProvider).localMusicDirs),
      );
    }
    await AppLogger.write(
      'app',
      'startup permission user-triggered granted=$ok',
    );
    final root = rootNavigatorKey.currentContext;
    if (root == null || !root.mounted) return false;
    showAppToast(
      root,
      ok ? '已允许读取本地音乐' : '未授权，可在「设置→权限与目录」中开启音乐和音频权限',
      type: ok ? AppToastType.success : AppToastType.warning,
    );
    // Let the user return to the library after handling the permission prompt.
    return false;
  }

  Future<bool> _showPermissionDialog(BuildContext context) async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            icon: const Icon(Icons.library_music_outlined, size: 36),
            title: const Text('读取本地音乐'),
            content: const Text(
              '允许读取设备上的音乐和音频，在选定文件夹中查找歌曲及封面。\n\n'
              '暂不授权也可以继续使用，之后可在「设置→权限与目录」中开启。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('稍后再说'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('去授权'),
              ),
            ],
          ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final themeMode = settings.themeMode;

    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        return FutureBuilder<CorePalette?>(
          future: _corePaletteFuture,
          builder: (context, snapshot) {
            final corePalette = snapshot.data;
            final lightScheme = corePalette == null
                ? lightDynamic
                : DynamicColorScheme.fromCorePalette(
                    corePalette,
                    brightness: Brightness.light,
                  );
            final darkScheme = corePalette == null
                ? darkDynamic
                : DynamicColorScheme.fromCorePalette(
                    corePalette,
                    brightness: Brightness.dark,
                  );

            final dynamicSeed = lightScheme?.primary ?? darkScheme?.primary;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              final next = DynamicColorStatus(
                available: dynamicSeed != null,
                seed: dynamicSeed,
              );
              final current = ref.read(dynamicColorStatusProvider);
              if (current.available != next.available ||
                  current.seed?.toARGB32() != next.seed?.toARGB32()) {
                ref.read(dynamicColorStatusProvider.notifier).state = next;
              }
            });

            final useDynamicScheme =
                settings.useDynamicColor &&
                lightScheme != null &&
                darkScheme != null;
            final lightTheme = AppTheme.fromScheme(
              useDynamicScheme
                  ? lightScheme
                  : AppTheme.schemeFor(
                      settings.themeSeed,
                      Brightness.light,
                      settings.colorStyle,
                    ),
              colors: settings.customTheme.enabled
                  ? settings.customTheme.light
                  : null,
              style: settings.colorStyle,
            );
            final darkTheme = AppTheme.fromScheme(
              useDynamicScheme
                  ? darkScheme
                  : AppTheme.schemeFor(
                      settings.themeSeed,
                      Brightness.dark,
                      settings.colorStyle,
                    ),
              colors: settings.customTheme.enabled
                  ? settings.customTheme.dark
                  : null,
              style: settings.colorStyle,
            );
            final isDark = switch (themeMode) {
              ThemeMode.light => false,
              ThemeMode.dark => true,
              ThemeMode.system =>
                MediaQuery.platformBrightnessOf(context) == Brightness.dark,
            };
            _logColorSchemeOnce(
              useDynamicScheme ? (isDark ? darkScheme : lightScheme) : null,
              fromCorePalette: corePalette != null,
            );
            final overlayIsDark = settings.customTheme.enabled
                ? ThemeData.estimateBrightnessForColor(
                        (isDark ? darkTheme : lightTheme)
                            .scaffoldBackgroundColor,
                      ) ==
                      Brightness.dark
                : isDark;
            final overlayStyle = SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              systemNavigationBarColor: Colors.transparent,
              systemNavigationBarDividerColor: Colors.transparent,
              systemStatusBarContrastEnforced: false,
              systemNavigationBarContrastEnforced: false,
              statusBarIconBrightness: overlayIsDark
                  ? Brightness.light
                  : Brightness.dark,
              statusBarBrightness: overlayIsDark
                  ? Brightness.dark
                  : Brightness.light,
              systemNavigationBarIconBrightness: overlayIsDark
                  ? Brightness.light
                  : Brightness.dark,
            );

            return MaterialApp.router(
              title: '栖弦',
              debugShowCheckedModeBanner: false,
              themeAnimationDuration: AppMotion.long,
              themeAnimationCurve: AppMotion.emphasized,
              themeMode: themeMode,
              theme: lightTheme,
              darkTheme: darkTheme,
              routerConfig: appRouter,
              builder: (context, child) {
                // Route-specific regions (such as artwork headers) override
                // this baseline only while they are visible in the layer tree.
                return AnnotatedRegion<SystemUiOverlayStyle>(
                  value: overlayStyle,
                  child: CarDisplayViewport(
                    enabled: settings.carDisplayEnabled,
                    sizeFactor: settings.carDisplaySize,
                    child: AppToastOverlay(
                      child: MusicSourceUpdatePrompt(
                        navigatorKey: rootNavigatorKey,
                        ready: _sourceUpdatePromptsReady,
                        child: StartupGate(
                          skipStartupScreen: settings.skipStartupScreen,
                          onReady: _onStartupReady,
                          child: child ?? const SizedBox.shrink(),
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  void _logColorSchemeOnce(
    ColorScheme? scheme, {
    required bool fromCorePalette,
  }) {
    if (scheme == null) return;
    final signature =
        '${scheme.brightness}:${scheme.primary.toARGB32()}:'
        '${scheme.surfaceContainerHigh.toARGB32()}:$fromCorePalette';
    if (_lastLoggedScheme == signature) return;
    _lastLoggedScheme = signature;
    AppLogger.write(
      'theme',
      'dynamic=$fromCorePalette brightness=${scheme.brightness.name} '
          'surface=${_hex(scheme.surface)} '
          'surfaceContainerHigh=${_hex(scheme.surfaceContainerHigh)} '
          'primary=${_hex(scheme.primary)} '
          'primaryContainer=${_hex(scheme.primaryContainer)}',
    );
  }

  String _hex(Color color) {
    return '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
  }
}
