import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_ui/prism_ui.dart' as prism;
import 'package:prism_ui/icons/prism_glyphs.dart' as prism_glyphs;

import '../../../core/ui/music_action_glyphs.dart';
import '../../../theme/app_motion.dart';
import '../player_transition.dart';
import '../shell_navigation.dart';
import 'floating_player_bar.dart';
import 'toolbar_metrics.dart';

// The player capsule above the dock is secondary and therefore reads visibly
// smaller: shorter and narrower. The dock itself is Prism UI's liquid,
// draggable navigation surface from prism_ui.
const double _playerHorizontalInset = 38;
const double _playerBottomGap = 8;
const double _navigationDockShadowRoom = 8;
const double _floatingDockMaxWidth = 360;

double floatingCapsuleNavBarHeight(BuildContext context) =>
    _navigationDockShadowRoom + prism.NavigationDock.insetOf(context);

// Legacy helper name retained for callers outside the shell.
double dualCapsuleNavBarHeight(BuildContext context) =>
    floatingCapsuleNavBarHeight(context);

double dualCapsulePlayerHeight(BuildContext context) {
  final scaler = MediaQuery.textScalerOf(context);
  return math.max(
    // Keep enough room for the mini player's title and artist at large text
    // scales while the dock remains visually compact.
    44,
    (scaler.scale(13) + scaler.scale(10.5)) * 1.2 + 9,
  );
}

double floatingCapsuleBottomAreaHeight(
  BuildContext context, {
  required bool showPlayer,
}) =>
    floatingCapsuleNavBarHeight(context) +
    (showPlayer ? dualCapsulePlayerHeight(context) + _playerBottomGap : 0);

// Legacy helper name retained while downstream callers migrate.
double dualCapsuleBottomAreaHeight(
  BuildContext context, {
  required bool showPlayer,
}) => floatingCapsuleBottomAreaHeight(context, showPlayer: showPlayer);

class FloatingCapsuleBottomNavigation extends ConsumerWidget {
  const FloatingCapsuleBottomNavigation({
    super.key,
    required this.location,
    required this.routeLocation,
    required this.showPlayer,
    required this.visible,
    required this.reveal,
    this.isPlayer = false,
  });

  final String location;
  final String routeLocation;
  final bool showPlayer;
  final bool visible;
  final Animation<double> reveal;
  final bool isPlayer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transition = PlayerTransitionScope.maybeOf(context);
    final navOpacity = transition == null
        ? AlwaysStoppedAnimation(isPlayer ? 0.0 : 1.0)
        : ReverseAnimation(
            transition.progress.drive(const PlayerPhase(0, 0.2)),
          );
    final controls = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showPlayer)
          SafeArea(
            top: false,
            bottom: false,
            minimum: const EdgeInsets.symmetric(horizontal: 14),
            child: Padding(
              padding: const EdgeInsets.only(bottom: _playerBottomGap),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final navWidth = math.min(
                    constraints.maxWidth,
                    _floatingDockMaxWidth,
                  );
                  return Center(
                    child: FloatingPlayerBar(
                      routeLocation: routeLocation,
                      width: navWidth - _playerHorizontalInset * 2,
                      height: dualCapsulePlayerHeight(context),
                    ),
                  );
                },
              ),
            ),
          ),
        FadeTransition(
          opacity: navOpacity,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = math.min(
                constraints.maxWidth,
                _floatingDockMaxWidth,
              );
              return Center(
                child: _FloatingCapsuleNavBar(
                  location: location,
                  routeLocation: routeLocation,
                  width: width,
                  height: floatingCapsuleNavBarHeight(context),
                ),
              );
            },
          ),
        ),
      ],
    );

    final travel = floatingCapsuleBottomAreaHeight(
      context,
      showPlayer: showPlayer,
    );
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

// Source compatibility for code written before the single/double capsule
// modes were consolidated into the Prism UI-style floating dock.
typedef DualCapsuleBottomNavigation = FloatingCapsuleBottomNavigation;

class _FloatingCapsuleNavBar extends ConsumerWidget {
  const _FloatingCapsuleNavBar({
    required this.location,
    required this.routeLocation,
    required this.width,
    required this.height,
  });

  final String location;
  final String routeLocation;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedIndex = switch (toolbarIndexFor(location)) {
      0 => 0,
      1 => 1,
      _ => 2,
    };
    const destinations = [
      prism.NavigationDockDestination(
        glyph: prism_glyphs.AppGlyphs.dashboard,
        label: '发现',
      ),
      prism.NavigationDockDestination(
        glyph: MusicActionGlyphs.musicLibrary,
        label: '歌曲',
      ),
      prism.NavigationDockDestination(
        glyph: prism_glyphs.AppGlyphs.settings,
        label: '设置',
      ),
    ];
    return SizedBox(
      width: width,
      height: height,
      child: prism.NavigationDock(
        key: const ValueKey('floating-navigation-dock'),
        maxWidth: width,
        destinations: destinations,
        selectedIndex: selectedIndex,
        onSelected: (index) => navigateToShellTab(
          context,
          ref,
          location,
          routeLocation,
          const ['/', '/songs', '/settings'][index],
        ),
      ),
    );
  }
}
