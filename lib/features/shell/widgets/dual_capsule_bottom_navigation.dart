import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/app_motion.dart';
import '../player_transition.dart';
import '../shell_navigation.dart';
import '../shell_route_utils.dart';
import 'floating_player_bar.dart';
import 'toolbar_action.dart';
import 'toolbar_capsule.dart';
import 'toolbar_metrics.dart';

// The navigation capsule is the primary control; the player capsule above it
// is secondary and therefore reads visibly smaller: shorter and narrower.
const double _playerHeightReduction = 12;
const double _playerHorizontalInset = 14;
const double _playerBottomGap = 8;

double dualCapsuleNavBarHeight(BuildContext context) =>
    toolbarHeightFor(context);

double dualCapsulePlayerHeight(BuildContext context) {
  final scaler = MediaQuery.textScalerOf(context);
  return math.max(
    dualCapsuleNavBarHeight(context) - _playerHeightReduction,
    // Two label lines plus breathing room must still fit.
    (scaler.scale(13) + scaler.scale(10.5)) * 1.2 + 9,
  );
}

double dualCapsuleBottomAreaHeight(
  BuildContext context, {
  required bool showPlayer,
}) =>
    dualCapsuleNavBarHeight(context) +
    math.max(MediaQuery.paddingOf(context).bottom, 10) +
    (showPlayer ? dualCapsulePlayerHeight(context) + _playerBottomGap : 0);

class DualCapsuleBottomNavigation extends ConsumerWidget {
  const DualCapsuleBottomNavigation({
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
                    toolbarMaxActionWidthFor(MediaQuery.sizeOf(context)) *
                            toolbarActionCount +
                        10,
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
        SafeArea(
          top: false,
          minimum: const EdgeInsets.fromLTRB(14, 0, 14, 10),
          child: FadeTransition(
            opacity: navOpacity,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = math.min(
                  constraints.maxWidth,
                  toolbarMaxActionWidthFor(MediaQuery.sizeOf(context)) *
                          toolbarActionCount +
                      10,
                );
                return Center(
                  child: _DualCapsuleNavBar(
                    location: location,
                    routeLocation: routeLocation,
                    width: width,
                    height: dualCapsuleNavBarHeight(context),
                    transition: transition,
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );

    final travel = dualCapsuleBottomAreaHeight(context, showPlayer: showPlayer);
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

class _DualCapsuleNavBar extends ConsumerWidget {
  const _DualCapsuleNavBar({
    required this.location,
    required this.routeLocation,
    required this.width,
    required this.height,
    required this.transition,
  });

  final String location;
  final String routeLocation;
  final double width;
  final double height;
  final PlayerTransition? transition;

  int _dualCapsuleIndexFor(String loc) {
    if (isDiscoveryLocation(loc)) return 0;
    if (isSongsLibraryLocation(loc) ||
        loc == '/downloads' ||
        isPlaylistLocation(loc)) {
      return 1;
    }
    if (loc.startsWith('/settings') || loc == '/debug') return 2;
    return 0;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    const actionCount = 3;
    final selectedIndex = _dualCapsuleIndexFor(location);

    return SizedBox(
      width: width,
      height: height,
      child: RepaintBoundary(
        child: AnimatedContainer(
          duration: AppMotion.long,
          curve: AppMotion.emphasized,
          decoration: BoxDecoration(
            color: toolbarCapsuleColor(scheme),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.52),
            ),
            boxShadow: [
              BoxShadow(
                color: scheme.shadow.withValues(
                  alpha: scheme.brightness == Brightness.light ? 0.08 : 0.18,
                ),
                blurRadius: 28,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final actionWidth = constraints.maxWidth / actionCount;
                  final actionHeight = constraints.maxHeight - 8;
                  return Stack(
                    alignment: Alignment.centerLeft,
                    clipBehavior: Clip.none,
                    children: [
                      AnimatedPositioned(
                        left: selectedIndex * actionWidth,
                        top: (constraints.maxHeight - actionHeight) / 2,
                        duration: AppMotion.medium,
                        curve: AppMotion.emphasized,
                        child: ToolbarSlidingIndicator(
                          width: actionWidth,
                          height: actionHeight,
                        ),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: ToolbarAction(
                              tooltip: '发现',
                              label: '发现',
                              icon: Icons.explore_rounded,
                              selected: selectedIndex == 0,
                              width: actionWidth,
                              height: actionHeight,
                              onPressed: () => navigateToShellTab(
                                context,
                                ref,
                                location,
                                routeLocation,
                                '/',
                              ),
                            ),
                          ),
                          Expanded(
                            child: ToolbarAction(
                              tooltip: '歌曲',
                              label: '歌曲',
                              icon: Icons.library_music_rounded,
                              selected: selectedIndex == 1,
                              width: actionWidth,
                              height: actionHeight,
                              onPressed: () => navigateToShellTab(
                                context,
                                ref,
                                location,
                                routeLocation,
                                '/songs',
                              ),
                            ),
                          ),
                          Expanded(
                            child: ToolbarAction(
                              tooltip: '设置',
                              label: '设置',
                              icon: Icons.tune_rounded,
                              selected: selectedIndex == 2,
                              width: actionWidth,
                              height: actionHeight,
                              onPressed: () => navigateToShellTab(
                                context,
                                ref,
                                location,
                                routeLocation,
                                '/settings',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
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
