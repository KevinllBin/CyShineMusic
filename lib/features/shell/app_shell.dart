import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/storage/settings_store.dart';
import '../../core/ui/app_toast.dart';
import '../../core/ui/cover_image_source.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_theme.dart';
import '../player/player_page.dart';
import '../player/widgets/spinning_cover_art.dart';
import '../player/player_controller.dart';
import '../playlists/playlist_detail_toolbar_state.dart';
import '../songs/songs_toolbar_state.dart';
import 'player_pull_scope.dart';
import 'player_transition.dart';
import 'shell_bottom_area.dart';
import 'shell_route_utils.dart';
import 'shell_toolbar_visibility.dart';
import 'tab_location_memory.dart';
import 'widgets/bottom_toolbar.dart';
import 'widgets/discovery_category_fab.dart';
import 'widgets/native_bottom_navigation.dart';
import 'widgets/search_paging_fab.dart';
import 'widgets/shell_header.dart';
import 'widgets/toolbar_metrics.dart';
import 'widgets/toolbar_capsule.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({
    super.key,
    required this.child,
    required this.location,
    required this.routeLocation,
    required this.playerReturnLocation,
    required this.playlistBackLocation,
  });

  final Widget child;
  final String location;
  final String routeLocation;
  final String playerReturnLocation;
  final String playlistBackLocation;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell>
    with TickerProviderStateMixin {
  _ShellRouteMotion _routeMotion = _ShellRouteMotion.forward;
  String _playerReturnLocation = '/songs';
  late final AnimationController _toolbarRevealController;

  /// Player reveal progress: 0 parks the player layer below the screen, 1
  /// seats it. This is the single source of truth for entering, leaving and
  /// dragging the player — the page itself never animates.
  late final AnimationController _pull;
  late final PlayerPullGestures _pullGestures;

  /// Mounted lazily on first pull and never torn down again, so the backdrop's
  /// async blur pipeline only ever runs its cold start once.
  bool _playerLayerMounted = false;
  bool _pullActive = false;
  late final AnimationController _coverRotation;
  late final PlayerTransition _transition;
  int _pullGeneration = 0;
  double? _settleTarget;
  bool _settledExpanded = false;
  bool _dragFromPlayer = false;
  double _dragStartProgress = 0;
  String _underlayPlaylistBack = '/';
  Timer? _returnToDesktopTimer;
  AppToastHandle? _returnToDesktopToast;

  bool _toolbarScrollSequenceActive = false;
  double _lastToolbarScrollDelta = 0;
  double _toolbarTravelExtent = toolbarDefaultTravelExtent;

  @override
  void initState() {
    super.initState();
    _toolbarRevealController = AnimationController(
      vsync: this,
      value: 1,
      duration: AppMotion.medium,
    );
    final startsOnPlayer = widget.location == '/player';
    _settledExpanded = startsOnPlayer;
    _pull = AnimationController(
      vsync: this,
      value: startsOnPlayer ? 1 : 0,
      duration: AppMotion.medium,
    );
    _playerLayerMounted = startsOnPlayer;
    _playerReturnLocation = normalizedPlayerReturnLocation(
      startsOnPlayer ? widget.playerReturnLocation : widget.routeLocation,
      '/songs',
    );
    _coverRotation = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 24),
    );
    _transition = PlayerTransition(progress: _pull, rotation: _coverRotation);
    if (ref.read(playerControllerProvider).playing) _coverRotation.repeat();
    // Built once: the tear-offs below are stable across builds, so dependents
    // of PlayerPullScope never rebuild.
    _pullGestures = PlayerPullGestures(
      onWarm: _handlePullWarm,
      onStart: _handlePullStart,
      onUpdate: _handlePullUpdate,
      onEnd: _handlePullEnd,
      onCancel: _handlePullCancel,
      onOpen: _handleOpenPlayer,
      onClose: _dismissPlayer,
    );
    _rememberTabLocation();
  }

  @override
  void dispose() {
    _resetTopLevelBack();
    _toolbarRevealController.dispose();
    _transition.dispose();
    _coverRotation.dispose();
    _pull.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant AppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.routeLocation != widget.routeLocation) {
      _rememberTabLocation();
    }
    if (oldWidget.location != widget.location) {
      _resetTopLevelBack();
      _routeMotion = _motionFor(oldWidget.location, widget.location);
      _toolbarScrollSequenceActive = false;
      _lastToolbarScrollDelta = 0;
      // Preserve the underlying toolbar's scroll position during the morph.
      if (!_pullActive && _pull.value == 0) {
        _toolbarRevealController.value = 1;
      }
      if (widget.location == '/player') {
        _underlayPlaylistBack = oldWidget.playlistBackLocation;
        _playerReturnLocation = normalizedPlayerReturnLocation(
          widget.playerReturnLocation,
          oldWidget.routeLocation,
        );
        _playerLayerMounted = true;
        if (_pull.value < 1 && _settleTarget != 1 && !_pullActive) {
          _commitPull();
        }
      } else {
        if (oldWidget.location == '/player') {
          // The dismiss animation has already parked it off screen; this is
          // just a backstop for navigation that bypassed _dismissPlayer.
          _pullGeneration++;
          _settleTarget = null;
          _settledExpanded = false;
          _pull.stop();
          _pull.value = 0;
          _animateToolbarTo(1);
        } else if (oldWidget.location != '/player') {
          _playerReturnLocation = normalizedPlayerReturnLocation(
            widget.location,
            _playerReturnLocation,
          );
        }
      }
      if (widget.location == '/songs/search') {
        FocusManager.instance.primaryFocus?.unfocus();
      } else {
        _releaseRouteFocus();
      }
    }
  }

  double get _pullExtent => _transition.travel;

  String get _contentLocation => widget.location == '/player'
      ? Uri.parse(_playerReturnLocation).path
      : widget.location;

  void _handlePullWarm() {
    _transition.capture();
    if (!_playerLayerMounted) setState(() => _playerLayerMounted = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _transition.capture();
    });
  }

  void _handleOpenPlayer() {
    _releaseRouteFocus();
    _handlePullWarm();
    _pullActive = false;
    _commitPull();
  }

  void _handlePullStart({bool fromPlayer = false}) {
    _pullGeneration++;
    _settleTarget = null;
    _pull.stop();
    _handlePullWarm();
    _pullActive = true;
    _dragFromPlayer = fromPlayer;
    _dragStartProgress = _pull.value;
    _toolbarRevealController.stop();
    _releaseRouteFocus();
  }

  void _handlePullUpdate(double dy) {
    if (!_pullActive || dy == 0) return;
    _pull.value = (_pull.value - dy / _pullExtent).clamp(0.0, 1.0);
  }

  void _handlePullEnd(double velocityDy) {
    if (!_pullActive) return;
    _pullActive = false;
    final reveal = PlayerMotion.shouldExpand(
      progress: _pull.value,
      travel: _pullExtent,
      velocityY: velocityDy,
      wasExpanded: _settledExpanded,
      fromPlayer: _dragFromPlayer,
      startProgress: _dragStartProgress,
    );
    if (reveal) {
      _commitPull(velocityDy: velocityDy);
    } else {
      _settleClosed(velocityDy: velocityDy);
    }
  }

  void _handlePullCancel() {
    if (!_pullActive) return;
    _pullActive = false;
    if (_settledExpanded) {
      _commitPull();
    } else {
      _settleClosed();
    }
  }

  Future<void> _commitPull({double velocityDy = 0}) async {
    final generation = ++_pullGeneration;
    _settleTarget = 1;
    if (!_playerLayerMounted) setState(() => _playerLayerMounted = true);
    // Lay out the real destination before the first visible shared-cover frame.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || generation != _pullGeneration) return;
    _transition.capture();
    // The transparent route keeps the origin alive. Activate the controls
    // immediately instead of waiting through the spring's subpixel tail.
    if (widget.location != '/player') {
      _playerReturnLocation = widget.routeLocation;
      unawaited(context.push<void>('/player', extra: _playerReturnLocation));
    }
    try {
      await _animatePullTo(1, velocityDy: velocityDy).orCancel;
    } on TickerCanceled {
      return;
    }
    if (!mounted || generation != _pullGeneration || _pull.value != 1) return;
    _settledExpanded = true;
    _settleTarget = null;
  }

  Future<void> _dismissPlayer([String? target]) => _settleClosed(
    destination: target,
    velocityDy: -_pull.velocity * _pullExtent,
  );

  Future<void> _settleClosed({
    String? destination,
    double velocityDy = 0,
  }) async {
    final generation = ++_pullGeneration;
    _settleTarget = 0;
    _transition.capture();
    try {
      await _animatePullTo(0, velocityDy: velocityDy).orCancel;
    } on TickerCanceled {
      return;
    }
    if (!mounted || generation != _pullGeneration || _pull.value != 0) return;
    _settledExpanded = false;
    _settleTarget = null;
    if (widget.location == '/player') {
      if (destination == null && GoRouter.of(context).canPop()) {
        context.pop();
      } else {
        context.go(destination ?? _playerReturnLocation);
      }
    }
    _animateToolbarTo(1);
  }

  TickerFuture _animatePullTo(double target, {double velocityDy = 0}) {
    if ((_pull.value - target).abs() < 1e-9 ||
        MediaQuery.disableAnimationsOf(context)) {
      _pull.value = target;
      return TickerFuture.complete();
    }
    return _pull.animateWith(
      PlayerSpringSimulation(
        _pull.value,
        target,
        -velocityDy / _pullExtent,
        distanceTolerance:
            0.01 / (MediaQuery.devicePixelRatioOf(context) * _pullExtent),
      ),
    );
  }

  /// Records the current route (full URI including query) as the last visited
  /// location of its bottom-toolbar tab, so tab taps can restore it later.
  void _rememberTabLocation() {
    final location = widget.location;
    final routeLocation = widget.routeLocation;
    if (location == '/player') return;
    final index = toolbarIndexFor(location);
    if (index == 2) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final memory = ref.read(tabLocationMemoryProvider);
      if (memory[index] == routeLocation) return;
      ref.read(tabLocationMemoryProvider.notifier).state = {
        ...memory,
        index: routeLocation,
      };
    });
  }

  Future<bool> _handleBackButton() async {
    final navigator = Navigator.of(context, rootNavigator: true);
    if (navigator.canPop()) {
      await navigator.maybePop();
      return true;
    }
    if (widget.location == '/player') {
      _pullActive = false;
      unawaited(_dismissPlayer());
      return true;
    }
    // Mid-pull: put the player back where it came from instead of navigating.
    if (_pullActive || (_pull.value > 0 && widget.location != '/player')) {
      _pullActive = false;
      unawaited(_settleClosed());
      return true;
    }
    if (isSongsLibraryLocation(widget.location)) {
      final songsToolbar = ref.read(songsToolbarStateProvider);
      if (songsToolbar.batchMode && songsToolbar.onToggleBatch != null) {
        songsToolbar.onToggleBatch!();
        return true;
      }
    }
    if (isPlaylistDetailLocation(widget.location)) {
      final playlistToolbar = ref.read(playlistDetailToolbarStateProvider);
      if (playlistToolbar.searchMode &&
          playlistToolbar.onToggleSearch != null) {
        playlistToolbar.onToggleSearch!();
        return true;
      }
      if (playlistToolbar.batchMode && playlistToolbar.onToggleBatch != null) {
        playlistToolbar.onToggleBatch!();
        return true;
      }
    }

    _releaseRouteFocus();
    if (_isTopLevelMenuLocation(widget.location)) {
      await _handleTopLevelBack();
    } else if (widget.location == '/downloads' ||
        widget.location == '/songs/search') {
      context.go('/songs');
    } else if (widget.location == '/settings/sources' ||
        widget.location == '/settings/webdav' ||
        widget.location == '/settings/equalizer' ||
        widget.location == '/debug') {
      context.go('/settings');
    } else if (context.canPop()) {
      context.pop();
    } else if (isDiscoveryLocation(widget.location) && widget.location != '/') {
      context.go('/');
    } else if (isPlaylistLocation(widget.location)) {
      context.go(widget.playlistBackLocation);
    } else {
      unawaited(_moveAppTaskToBack());
    }
    return true;
  }

  Future<void> _handleTopLevelBack() async {
    if (_returnToDesktopTimer?.isActive ?? false) {
      _resetTopLevelBack();
      await _moveAppTaskToBack();
      return;
    }

    _resetTopLevelBack();
    _returnToDesktopToast = showAppToast(
      context,
      '再次点击返回键切换到桌面',
      duration: _doubleBackExitWindow,
    );
    _returnToDesktopTimer = Timer(_doubleBackExitWindow, () {
      _returnToDesktopTimer = null;
      _returnToDesktopToast = null;
    });
  }

  void _resetTopLevelBack() {
    _returnToDesktopTimer?.cancel();
    _returnToDesktopTimer = null;
    dismissAppToast(_returnToDesktopToast, showRemoveAnimation: false);
    _returnToDesktopToast = null;
  }

  void _releaseRouteFocus() {
    FocusManager.instance.primaryFocus?.unfocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      FocusManager.instance.primaryFocus?.unfocus();
    });
  }

  bool _handleToolbarScrollNotification(ScrollNotification notification) {
    // While a player pull owns the toolbar reveal, scrolling must not fight it.
    if (_pullActive || ref.read(settingsProvider).useNativeNavigation) {
      return false;
    }
    final songsBatchMode =
        isSongsLibraryLocation(widget.location) &&
        ref.read(songsToolbarStateProvider).batchMode;
    final playlistBatchMode =
        isPlaylistDetailLocation(widget.location) &&
        ref.read(playlistDetailToolbarStateProvider).batchMode;
    if (!ref.read(shellToolbarVisibleProvider) ||
        songsBatchMode ||
        playlistBatchMode) {
      _toolbarScrollSequenceActive = false;
      _lastToolbarScrollDelta = 0;
      _toolbarRevealController.stop(canceled: false);
      return false;
    }
    if (widget.location == '/player' ||
        notification.depth != 0 ||
        notification.metrics.axis != Axis.vertical) {
      return false;
    }

    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _toolbarScrollSequenceActive = true;
      _lastToolbarScrollDelta = 0;
      _toolbarRevealController.stop(canceled: false);
      return false;
    }

    if (notification is ScrollUpdateNotification &&
        notification.dragDetails != null) {
      _toolbarScrollSequenceActive = true;
      _applyToolbarScrollDelta(notification.scrollDelta ?? 0);
      return false;
    }

    if (notification is OverscrollNotification &&
        notification.dragDetails != null) {
      _toolbarScrollSequenceActive = true;
      _applyToolbarScrollDelta(notification.overscroll);
      return false;
    }

    if (notification is ScrollEndNotification) {
      _finishToolbarScrollSequence();
    }
    return false;
  }

  void _finishToolbarScrollSequence() {
    if (!_toolbarScrollSequenceActive) return;
    _toolbarScrollSequenceActive = false;
    _settleToolbarAfterScroll();
  }

  void _applyToolbarScrollDelta(double delta) {
    if (delta.abs() < toolbarScrollDeltaEpsilon) return;
    _lastToolbarScrollDelta = delta;
    _toolbarRevealController.stop(canceled: false);
    _toolbarRevealController.value =
        (_toolbarRevealController.value - delta / _toolbarTravelExtent)
            .clamp(0.0, 1.0)
            .toDouble();
  }

  void _settleToolbarAfterScroll() {
    final reveal = _toolbarRevealController.value;
    final target = switch (_lastToolbarScrollDelta) {
      > toolbarScrollDeltaEpsilon =>
        reveal <= toolbarHideDirectionThreshold ? 0.0 : 1.0,
      < -toolbarScrollDeltaEpsilon =>
        reveal >= toolbarShowDirectionThreshold ? 1.0 : 0.0,
      _ => reveal >= 0.5 ? 1.0 : 0.0,
    };
    _lastToolbarScrollDelta = 0;
    _animateToolbarTo(target);
  }

  void _animateToolbarTo(double target) {
    if (_pullActive) return;
    if ((_toolbarRevealController.value - target).abs() < 0.001) {
      _toolbarRevealController.value = target;
      return;
    }
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _toolbarRevealController.value = target;
      return;
    }
    final remaining = (_toolbarRevealController.value - target).abs();
    _toolbarRevealController.animateTo(
      target,
      duration: Duration(milliseconds: (140 + 180 * remaining).round()),
      curve: AppMotion.emphasized,
    );
  }

  @override
  Widget build(BuildContext context) {
    final contentLocation = _contentLocation;
    final contentRoute = widget.location == '/player'
        ? _playerReturnLocation
        : widget.routeLocation;
    final viewport = MediaQuery.sizeOf(context);
    if (_transition.viewport != viewport) {
      _transition.viewport = viewport;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _transition.capture(refreshSource: true);
      });
    }
    _transition.bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    ref.listen<bool>(playerControllerProvider.select((s) => s.playing), (
      _,
      playing,
    ) {
      if (playing) {
        if (!_coverRotation.isAnimating) _coverRotation.repeat();
      } else {
        _coverRotation.stop(canceled: false);
      }
    });
    final baseScheme = Theme.of(context).colorScheme;
    final scheme = shellSchemeFor(contentLocation, baseScheme);
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    final isPlayer = widget.location == '/player';
    final isImmersivePlaylist = isImmersivePlaylistDetailLocation(
      contentLocation,
    );
    // 发现区各页自绘顶栏（ShellSectionHeader）：导航器高度在「发现 ↔
    // 歌单/榜单详情」之间保持不变，详情页的容器变换展开/收回时下层内容
    // 才不会跳动。
    final hidesShellHeader =
        isImmersivePlaylist || isDiscoveryLocation(contentLocation);
    final toolbarTravelExtent = _bottomToolbarTravelExtent(context);
    _toolbarTravelExtent = toolbarTravelExtent;
    final useNativeNavigation = ref.watch(
      settingsProvider.select((settings) => settings.useNativeNavigation),
    );
    final showNativePlayer =
        useNativeNavigation &&
        ref.watch(
          playerControllerProvider.select(
            (state) => state.hasTrack || state.loading,
          ),
        );
    final nativeControlsVisible =
        useNativeNavigation &&
        MediaQuery.viewInsetsOf(context).bottom == 0 &&
        ref.watch(shellToolbarVisibleProvider) &&
        !(isSongsLibraryLocation(contentLocation) &&
            ref.watch(
              songsToolbarStateProvider.select((state) => state.batchMode),
            )) &&
        !(isPlaylistDetailLocation(contentLocation) &&
            ref.watch(
              playlistDetailToolbarStateProvider.select(
                (state) => state.batchMode,
              ),
            ));
    final nativeBottomExtent = nativeControlsVisible
        ? nativeBottomAreaHeight(context, showPlayer: showNativePlayer)
        : 0.0;
    // The player strip floats over content; only the navigation bar below it
    // pushes the page up.
    final nativeFloatingExtent = nativeControlsVisible && showNativePlayer
        ? nativeFloatingPlayerExtent(context)
        : 0.0;

    ref.listen<bool>(
      settingsProvider.select((settings) => settings.useNativeNavigation),
      (previous, next) {
        _toolbarScrollSequenceActive = false;
        _lastToolbarScrollDelta = 0;
        _toolbarRevealController.stop(canceled: false);
        _toolbarRevealController.value = 1;
      },
    );

    ref.listen<bool>(shellToolbarVisibleProvider, (previous, next) {
      if (next && previous == false) _animateToolbarTo(1);
    });
    ref.listen<SongsToolbarState>(songsToolbarStateProvider, (previous, next) {
      if (!isSongsLibraryLocation(contentLocation)) return;
      if (next.batchMode) {
        _toolbarScrollSequenceActive = false;
        _lastToolbarScrollDelta = 0;
        _toolbarRevealController.stop(canceled: false);
      } else if (previous?.batchMode == true) {
        _animateToolbarTo(1);
      }
    });
    ref.listen<PlaylistDetailToolbarState>(playlistDetailToolbarStateProvider, (
      previous,
      next,
    ) {
      if (!isPlaylistDetailLocation(contentLocation)) return;
      if (next.batchMode) {
        _toolbarScrollSequenceActive = false;
        _lastToolbarScrollDelta = 0;
        _toolbarRevealController.stop(canceled: false);
      } else if (previous?.batchMode == true) {
        _animateToolbarTo(1);
      }
    });

    return BackButtonListener(
      onBackButtonPressed: _handleBackButton,
      child: PlayerTransitionScope(
        transition: _transition,
        child: PlayerPullScope(
          gestures: _pullGestures,
          child: ShellBottomArea(
            nativeNavigation: useNativeNavigation,
            extent: nativeBottomExtent,
            floatingExtent: nativeFloatingExtent,
            child: Scaffold(
              extendBody: true,
              resizeToAvoidBottomInset: true,
              backgroundColor: scheme.appSurface,
              body: Stack(
                key: _transition.rootKey,
                // Every child carries an explicit key so element matching never
                // falls back to list position. The player layer slot below appears
                // and disappears, and without keys that index shift would rebuild
                // the toolbar subtree — killing any in-flight drag recognizer.
                children: [
                  Positioned.fill(
                    key: const ValueKey('shell-content'),
                    child: ColoredBox(
                      color: scheme.appSurface,
                      child: Padding(
                        // The immersive player page fills the whole screen and
                        // handles its own bottom safe area internally.
                        padding: EdgeInsets.only(
                          bottom: useNativeNavigation
                              ? nativeControlsVisible
                                    ? nativeBottomExtent - nativeFloatingExtent
                                    : MediaQuery.paddingOf(context).bottom
                              : math.max(bottomInset, 12),
                        ),
                        child: Column(
                          children: [
                            if (hidesShellHeader)
                              const SizedBox.shrink()
                            else
                              AnimatedSize(
                                duration: AppMotion.short,
                                curve: AppMotion.emphasized,
                                alignment: Alignment.topCenter,
                                child: ShellHeader(
                                  location: contentLocation,
                                  playlistBackLocation: isPlayer
                                      ? _underlayPlaylistBack
                                      : widget.playlistBackLocation,
                                ),
                              ),
                            Expanded(
                              child: RepaintBoundary(
                                child: ClipRect(
                                  child: AnimatedSwitcher(
                                    duration:
                                        isPlayer ||
                                            _routeMotion ==
                                                _ShellRouteMotion.playerExit
                                        ? AppMotion.medium
                                        : AppMotion.long,
                                    switchInCurve:
                                        AppMotion.emphasizedDecelerate,
                                    switchOutCurve:
                                        AppMotion.emphasizedAccelerate,
                                    // A pushed GoRouter route can reuse GlobalKeys
                                    // from the shell child below it. Keeping both
                                    // route trees mounted during the transition
                                    // would therefore trigger duplicate-key errors.
                                    layoutBuilder: (currentChild, _) =>
                                        currentChild ?? const SizedBox.shrink(),
                                    transitionBuilder: _buildRouteTransition,
                                    child: KeyedSubtree(
                                      key: ValueKey(
                                        _shellContentAnimationKey(
                                          contentLocation,
                                        ),
                                      ),
                                      child: Listener(
                                        behavior: HitTestBehavior.translucent,
                                        onPointerUp: (_) =>
                                            _finishToolbarScrollSequence(),
                                        onPointerCancel: (_) =>
                                            _finishToolbarScrollSequence(),
                                        child:
                                            NotificationListener<
                                              ScrollNotification
                                            >(
                                              onNotification:
                                                  _handleToolbarScrollNotification,
                                              child: widget.child,
                                            ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (contentLocation == '/')
                    const Positioned.fill(
                      key: ValueKey('shell-fab'),
                      child: Stack(
                        children: [
                          DiscoveryCategoryFabLayer(),
                          SearchPagingFabLayer(),
                        ],
                      ),
                    ),
                  _buildPlayerLayer(isPlayer),
                  Positioned(
                    key: const ValueKey('shell-toolbar'),
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: AnimatedBuilder(
                      animation: _pull,
                      builder: (context, child) => IgnorePointer(
                        ignoring: _pull.value > 0,
                        child: ExcludeSemantics(
                          excluding: _pull.value > 0,
                          child: child!,
                        ),
                      ),
                      child: useNativeNavigation
                          ? NativeBottomNavigation(
                              location: contentLocation,
                              routeLocation: contentRoute,
                              showPlayer: showNativePlayer,
                              visible: nativeControlsVisible,
                              reveal: _toolbarRevealController,
                            )
                          : BottomToolbar(
                              location: contentLocation,
                              routeLocation: contentRoute,
                              reveal: _toolbarRevealController,
                              travelExtent: toolbarTravelExtent,
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlayerLayer(bool isPlayer) {
    if (!_playerLayerMounted) {
      return const Positioned(
        key: ValueKey('shell-player'),
        left: 0,
        top: 0,
        width: 0,
        height: 0,
        child: SizedBox.shrink(),
      );
    }
    final track = ref.watch(playerControllerProvider.select((s) => s.track));
    final scheme = Theme.of(context).colorScheme;
    final cover = RepaintBoundary(
      child: RotationTransition(
        turns: _coverRotation,
        child: PlayerArtworkImage(
          url: CoverImageSource.normalizeUrl(track?.coverUrl, size: 700),
          bytes: track?.coverBytes,
          animate: false,
          placeholder: ColoredBox(
            color: scheme.surfaceContainerHighest,
            child: const Center(child: Icon(Icons.album_rounded)),
          ),
        ),
      ),
    );
    return Positioned(
      key: const ValueKey('shell-player'),
      left: 0,
      right: 0,
      top: 0,
      height: MediaQuery.sizeOf(context).height,
      child: MediaQuery.removeViewInsets(
        context: context,
        removeBottom: true,
        child: AnimatedBuilder(
          animation: _transition,
          child: PlayerPage(
            returnLocation: _playerReturnLocation,
            progress: _pull,
            active: isPlayer,
            onDismissRequested: _dismissPlayer,
          ),
          builder: (context, child) {
            final p = _pull.value;
            final visible = p > 0 || isPlayer;
            final flight = track == null ? null : _transition.coverRect;
            return IgnorePointer(
              ignoring: !visible,
              child: ExcludeSemantics(
                excluding: !visible,
                child: TickerMode(
                  enabled: visible,
                  child: Opacity(
                    opacity: visible ? 1 : 0,
                    child: PlayerPullHandle(
                      child: Stack(
                        fit: StackFit.expand,
                        clipBehavior: Clip.none,
                        children: [
                          ClipRRect(
                            key: const ValueKey('player-surface-clip'),
                            clipper: _PlayerSurfaceClipper(_transition.surface),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                ColoredBox(color: toolbarCapsuleColor(scheme)),
                                Transform.translate(
                                  key: const ValueKey('player-exit-slide'),
                                  offset: Offset(0, (1 - p) * _pullExtent),
                                  child: child,
                                ),
                              ],
                            ),
                          ),
                          if (flight != null)
                            Positioned.fromRect(
                              key: const ValueKey('player-shared-cover'),
                              rect: flight,
                              child: IgnorePointer(
                                child: ClipOval(child: cover),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildRouteTransition(Widget child, Animation<double> animation) {
    if (_routeMotion == _ShellRouteMotion.playerEnter ||
        _routeMotion == _ShellRouteMotion.playerExit) {
      return child;
    }
    final incoming =
        child.key == ValueKey(_shellContentAnimationKey(_contentLocation));
    final offset =
        Tween<Offset>(begin: _routeOffset(incoming), end: Offset.zero).animate(
          CurvedAnimation(
            parent: animation,
            curve: incoming
                ? AppMotion.emphasizedDecelerate
                : AppMotion.emphasizedAccelerate,
          ),
        );
    final scale = Tween<double>(
      begin: incoming ? 0.992 : 1,
      end: 1,
    ).animate(CurvedAnimation(parent: animation, curve: AppMotion.emphasized));

    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: offset,
        child: ScaleTransition(scale: scale, child: child),
      ),
    );
  }

  Offset _routeOffset(bool incoming) {
    return switch (_routeMotion) {
      _ShellRouteMotion.playerEnter =>
        incoming ? const Offset(0, 0.055) : const Offset(0, -0.025),
      _ShellRouteMotion.playerExit =>
        incoming ? const Offset(0, -0.035) : const Offset(0, 0.08),
      _ShellRouteMotion.forward =>
        incoming ? const Offset(0.045, 0) : const Offset(-0.032, 0),
      _ShellRouteMotion.backward =>
        incoming ? const Offset(-0.045, 0) : const Offset(0.032, 0),
    };
  }
}

enum _ShellRouteMotion { forward, backward, playerEnter, playerExit }

const _doubleBackExitWindow = Duration(seconds: 2);

bool _isTopLevelMenuLocation(String location) {
  return location == '/' || location == '/songs' || location == '/settings';
}

_ShellRouteMotion _motionFor(String from, String to) {
  if (to == '/player') return _ShellRouteMotion.playerEnter;
  if (from == '/player') return _ShellRouteMotion.playerExit;
  return _routeOrder(to) >= _routeOrder(from)
      ? _ShellRouteMotion.forward
      : _ShellRouteMotion.backward;
}

int _routeOrder(String location) {
  if (isPlaylistLocation(location)) return 2;
  if (location.startsWith('/settings')) return 4;
  return switch (location) {
    '/' => 0,
    '/songs' => 1,
    '/songs/search' => 2,
    '/downloads' => 2,
    '/player' => 3,
    '/debug' => 4,
    _ => 0,
  };
}

String _shellContentAnimationKey(String location) {
  return isDiscoveryLocation(location) ? '/' : location;
}

const _appTaskChannel = MethodChannel('cy_shine_music/app_task');

Future<void> _moveAppTaskToBack() async {
  try {
    await _appTaskChannel.invokeMethod<bool>('moveToBack');
  } catch (_) {
    // If the native channel is unavailable, still consume back so Android does
    // not destroy the Flutter route stack.
  }
}

double _bottomToolbarTravelExtent(BuildContext context) {
  final toolbarHeight = toolbarHeightFor(context);
  final safeBottom = math.max(
    MediaQuery.paddingOf(context).bottom,
    toolbarMinimumBottomInset,
  );
  return toolbarHeight + safeBottom;
}

class _PlayerSurfaceClipper extends CustomClipper<RRect> {
  const _PlayerSurfaceClipper(this.surface);
  final RRect surface;
  @override
  RRect getClip(Size size) => surface;
  @override
  bool shouldReclip(_PlayerSurfaceClipper oldClipper) =>
      surface != oldClipper.surface;
}
