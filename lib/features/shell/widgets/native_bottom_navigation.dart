import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/app_motion.dart';
import '../../player/player_controller.dart';
import '../player_pull_scope.dart';
import '../player_transition.dart';
import '../shell_navigation.dart';
import 'mini_player_bar.dart';
import 'toolbar_capsule.dart';
import 'toolbar_metrics.dart';

// Breathing room above and below the floating player inside the native strip.
const double _playerVerticalPadding = 6;

double _miniPlayerHeight(BuildContext context) {
  final scaler = MediaQuery.textScalerOf(context);
  return math.max(
    toolbarHeightFor(context),
    (scaler.scale(13) + scaler.scale(10.5)) * 1.2 + 9,
  );
}

/// Height of the floating player strip. Content scrolls underneath it, so
/// pages add this to their trailing padding instead of the shell reserving it.
double nativeFloatingPlayerExtent(BuildContext context) =>
    _miniPlayerHeight(context) + _playerVerticalPadding * 2;

double nativeBottomAreaHeight(
  BuildContext context, {
  required bool showPlayer,
}) =>
    (NavigationBarTheme.of(context).height ?? 80) +
    MediaQuery.paddingOf(context).bottom +
    (showPlayer ? nativeFloatingPlayerExtent(context) : 0);

class NativeBottomNavigation extends ConsumerWidget {
  const NativeBottomNavigation({
    super.key,
    required this.location,
    required this.routeLocation,
    required this.showPlayer,
    required this.visible,
    required this.reveal,
  });

  final String location;
  final String routeLocation;
  final bool showPlayer;
  final bool visible;
  final Animation<double> reveal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transition = PlayerTransitionScope.maybeOf(context);
    final selectedIndex = switch (toolbarIndexFor(location)) {
      0 => 0,
      1 => 1,
      _ => 2,
    };
    final controls = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showPlayer)
          SafeArea(
            top: false,
            bottom: false,
            minimum: const EdgeInsets.symmetric(horizontal: 14),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                vertical: _playerVerticalPadding,
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final width = math.min(
                    constraints.maxWidth,
                    toolbarMaxActionWidthFor(MediaQuery.sizeOf(context)) *
                            toolbarActionCount +
                        10,
                  );
                  return Center(
                    child: _FloatingPlayerBar(
                      routeLocation: routeLocation,
                      width: width,
                      height: _miniPlayerHeight(context),
                    ),
                  );
                },
              ),
            ),
          ),
        // NavigationBar wraps itself in a SafeArea. Pinned to the bottom of
        // the shell stack nothing has consumed the status bar inset yet, so
        // without this it grows by the status bar height and overlaps content
        // that nativeBottomAreaHeight never reserved.
        MediaQuery.removePadding(
          context: context,
          removeTop: true,
          child: FadeTransition(
            opacity: transition == null
                ? const AlwaysStoppedAnimation(1)
                : ReverseAnimation(
                    transition.progress.drive(const PlayerPhase(0, 0.2)),
                  ),
            child: NavigationBar(
              key: const ValueKey('native-navigation-bar'),
              selectedIndex: selectedIndex,
              onDestinationSelected: (index) => navigateToShellTab(
                context,
                ref,
                location,
                routeLocation,
                const ['/', '/songs', '/settings'][index],
              ),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.explore_outlined),
                  selectedIcon: Icon(Icons.explore_rounded),
                  label: '发现',
                ),
                NavigationDestination(
                  icon: Icon(Icons.library_music_outlined),
                  selectedIcon: Icon(Icons.library_music_rounded),
                  label: '歌曲',
                ),
                NavigationDestination(
                  icon: Icon(Icons.settings_outlined),
                  selectedIcon: Icon(Icons.settings_rounded),
                  label: '设置',
                ),
              ],
            ),
          ),
        ),
      ],
    );
    final travel = nativeBottomAreaHeight(context, showPlayer: showPlayer);
    return ExcludeSemantics(
      excluding: !visible,
      child: IgnorePointer(
        ignoring: !visible,
        child: AnimatedSlide(
          offset: visible ? Offset.zero : const Offset(0, 1),
          duration: AppMotion.medium,
          curve: AppMotion.emphasized,
          child: AnimatedOpacity(
            opacity: visible ? 1 : 0,
            duration: AppMotion.short,
            child: AnimatedBuilder(
              animation: reveal,
              child: controls,
              builder: (context, child) {
                final progress = reveal.value.clamp(0.0, 1.0).toDouble();
                return IgnorePointer(
                  ignoring: progress <= toolbarHitTestRevealThreshold,
                  child: Opacity(
                    opacity: toolbarOpacityFor(progress),
                    child: Transform.translate(
                      offset: Offset(0, (1 - progress) * travel),
                      child: child,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _FloatingPlayerBar extends ConsumerStatefulWidget {
  const _FloatingPlayerBar({
    required this.routeLocation,
    required this.width,
    required this.height,
  });

  final String routeLocation;
  final double width;
  final double height;

  @override
  ConsumerState<_FloatingPlayerBar> createState() => _FloatingPlayerBarState();
}

// Swipe-to-skip feedback: the finger scrubs the capsule contents sideways
// with resistance; a committed swipe slides them out and the next track in.
const double _swipeDragResistance = 0.55;
const double _swipeMaxDrag = 44;
const double _swipeBlockedMaxDrag = 14;
const double _swipeExitExtent = 72;
const Duration _swipeExitDuration = Duration(milliseconds: 130);

class _FloatingPlayerBarState extends ConsumerState<_FloatingPlayerBar>
    with SingleTickerProviderStateMixin {
  // Horizontal offset of the capsule contents in logical pixels.
  late final AnimationController _shift = AnimationController.unbounded(
    vsync: this,
  );
  double _horizontalDistance = 0;
  VoidCallback? _pendingSkip;

  @override
  void dispose() {
    _shift.dispose();
    super.dispose();
  }

  bool _canSwitchToward(PlayerState state, double direction) {
    if (!state.hasTrack || state.loading) return false;
    return direction < 0 ? state.canPlayNext : state.canPlayPrevious;
  }

  void _startHorizontalDrag(DragStartDetails details) {
    _horizontalDistance = 0;
    _shift.stop();
    // A new swipe during the exit animation still honours the earlier swipe.
    _pendingSkip?.call();
  }

  void _updateHorizontalDrag(DragUpdateDetails details) {
    final dx = details.delta.dx;
    _horizontalDistance += dx;
    final target = _shift.value + dx * _swipeDragResistance;
    final limit = _canSwitchToward(ref.read(playerControllerProvider), target)
        ? _swipeMaxDrag
        : _swipeBlockedMaxDrag;
    _shift.value = target.clamp(-limit, limit).toDouble();
  }

  void _cancelHorizontalDrag() {
    _horizontalDistance = 0;
    _settle(0);
  }

  void _finishHorizontalDrag(DragEndDetails details) {
    final distance = _horizontalDistance;
    _horizontalDistance = 0;
    final velocity = details.velocity.pixelsPerSecond.dx;
    final fling = distance.abs() >= 12 && velocity.abs() >= 450;
    final direction = fling ? velocity : distance;
    final commit = distance.abs() >= 48 || fling;
    if (!commit ||
        !_canSwitchToward(ref.read(playerControllerProvider), direction)) {
      _settle(velocity * _swipeDragResistance);
      return;
    }
    _runSwitch(direction < 0 ? -1 : 1);
  }

  void _settle(double velocity) {
    _shift.animateWith(
      SpringSimulation(AppMotion.standardSpring, _shift.value, 0, velocity),
    );
  }

  void _runSwitch(int sign) {
    final controller = ref.read(playerControllerProvider.notifier);
    void skip() {
      _pendingSkip = null;
      unawaited(sign < 0 ? controller.playNext() : controller.playPrevious());
    }

    if (MediaQuery.disableAnimationsOf(context)) {
      _shift.value = 0;
      skip();
      return;
    }
    _pendingSkip = skip;
    // TickerFuture never completes when stopped, so an interrupted exit simply
    // leaves the skip to _startHorizontalDrag.
    _shift
        .animateTo(
          sign * _swipeExitExtent,
          duration: _swipeExitDuration,
          curve: AppMotion.emphasizedAccelerate,
        )
        .whenComplete(() {
          if (!mounted || !identical(_pendingSkip, skip)) return;
          skip();
          // The incoming track enters from the opposite side.
          _shift.value = -sign * _swipeExitExtent;
          _shift.animateTo(
            0,
            duration: AppMotion.medium,
            curve: AppMotion.emphasizedDecelerate,
          );
        });
  }

  @override
  Widget build(BuildContext context) {
    final pull = PlayerPullScope.maybeOf(context);
    return SizedBox(
      width: widget.width,
      child: Listener(
        onPointerDown: pull == null ? null : (_) => pull.onWarm(),
        child: GestureDetector(
          key: const ValueKey('native-mini-player'),
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: _startHorizontalDrag,
          onHorizontalDragUpdate: _updateHorizontalDrag,
          onHorizontalDragEnd: _finishHorizontalDrag,
          onHorizontalDragCancel: _cancelHorizontalDrag,
          onVerticalDragStart: pull == null ? null : (_) => pull.onStart(),
          onVerticalDragUpdate: pull == null
              ? null
              : (details) => pull.onUpdate(details.delta.dy),
          onVerticalDragEnd: pull == null
              ? null
              : (details) => pull.onEnd(details.velocity.pixelsPerSecond.dy),
          onVerticalDragCancel: pull?.onCancel,
          child: ToolbarCapsule(
            scheme: Theme.of(context).colorScheme,
            height: widget.height,
            // Keep the sliding contents inside the capsule's rounded ends.
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: AnimatedBuilder(
                animation: _shift,
                child: MiniPlayerBar(
                  width: widget.width - 10,
                  height: widget.height,
                  onOpenPlayer: () =>
                      navigateShellTo(context, widget.routeLocation, '/player'),
                ),
                builder: (context, child) {
                  final progress = (_shift.value.abs() / _swipeExitExtent)
                      .clamp(0.0, 1.0)
                      .toDouble();
                  return Opacity(
                    opacity: 1 - Curves.easeIn.transform(progress) * 0.9,
                    child: Transform.translate(
                      offset: Offset(_shift.value, 0),
                      child: child,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
