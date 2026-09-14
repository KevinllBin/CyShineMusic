import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/app_motion.dart';
import '../player_transition.dart';
import '../shell_navigation.dart';
import 'floating_player_bar.dart';
import 'toolbar_metrics.dart';

// Breathing room above and below the floating player inside the native strip.
const double _playerVerticalPadding = 6;

double miniPlayerHeight(BuildContext context) {
  final scaler = MediaQuery.textScalerOf(context);
  return math.max(
    toolbarHeightFor(context),
    (scaler.scale(13) + scaler.scale(10.5)) * 1.2 + 9,
  );
}

/// Height of the floating player strip. Content scrolls underneath it, so
/// pages add this to their trailing padding instead of the shell reserving it.
double nativeFloatingPlayerExtent(BuildContext context) =>
    miniPlayerHeight(context) + _playerVerticalPadding * 2;

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
                    child: FloatingPlayerBar(
                      routeLocation: routeLocation,
                      width: width,
                      height: miniPlayerHeight(context),
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

