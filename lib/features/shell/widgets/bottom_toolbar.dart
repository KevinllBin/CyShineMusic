import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/app_motion.dart';
import '../../player/player_controller.dart';
import '../../playlists/playlist_detail_toolbar_state.dart';
import '../../songs/songs_toolbar_state.dart';
import '../player_pull_scope.dart';
import '../shell_navigation.dart';
import '../shell_route_utils.dart';
import '../shell_toolbar_visibility.dart';
import 'mini_player_bar.dart';
import 'toolbar_action.dart';
import 'toolbar_capsule.dart';
import 'toolbar_metrics.dart';

class BottomToolbar extends ConsumerWidget {
  const BottomToolbar({
    super.key,
    required this.location,
    required this.routeLocation,
    required this.reveal,
    required this.travelExtent,
  });

  final String location;
  final String routeLocation;
  final Animation<double> reveal;
  final double travelExtent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = shellSchemeFor(location, Theme.of(context).colorScheme);
    final shellVisible = ref.watch(shellToolbarVisibleProvider);
    final playerHasContent = ref.watch(
      playerControllerProvider.select(
        (state) => state.hasTrack || state.loading,
      ),
    );
    final songsBatchMode =
        isSongsLibraryLocation(location) &&
        ref.watch(songsToolbarStateProvider.select((state) => state.batchMode));
    final playlistBatchMode =
        isPlaylistDetailLocation(location) &&
        ref.watch(
          playlistDetailToolbarStateProvider.select((state) => state.batchMode),
        );
    final visible =
        shellVisible &&
        !songsBatchMode &&
        !playlistBatchMode &&
        (location != '/player' || !playerHasContent);
    final toolbar = SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final viewport = MediaQuery.sizeOf(context);
          final actionWidth = math.max(
            toolbarMinActionWidth,
            math.min(
              toolbarMaxActionWidthFor(viewport),
              (constraints.maxWidth - toolbarHorizontalPadding) /
                  toolbarActionCount,
            ),
          );
          final toolbarHeight = toolbarHeightFor(context);
          final actionHeight = toolbarHeight - 8;
          return Center(
            child: AnimatedSize(
              duration: AppMotion.medium,
              curve: AppMotion.emphasized,
              child: ToolbarCapsule(
                scheme: scheme,
                height: toolbarHeight,
                child: _ToolbarPager(
                  location: location,
                  routeLocation: routeLocation,
                  actionWidth: actionWidth,
                  actionHeight: actionHeight,
                  toolbarHeight: toolbarHeight,
                ),
              ),
            ),
          );
        },
      ),
    );

    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedSlide(
        offset: visible ? Offset.zero : const Offset(0, 1.25),
        duration: AppMotion.medium,
        curve: AppMotion.emphasized,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: AppMotion.short,
          curve: AppMotion.emphasized,
          child: AnimatedBuilder(
            animation: reveal,
            child: toolbar,
            builder: (context, child) {
              final progress = reveal.value.clamp(0.0, 1.0).toDouble();
              final opacity = toolbarOpacityFor(progress);
              final translated = Transform.translate(
                offset: Offset(0, (1 - progress) * travelExtent),
                child: child,
              );
              return IgnorePointer(
                ignoring: progress <= toolbarHitTestRevealThreshold,
                // Kept unconditional: swapping this Opacity in and out re-slots
                // the whole capsule subtree, which would dispose the pager's
                // drag recognizers mid-gesture. RenderOpacity already skips the
                // layer at full opacity, so there is nothing to save here.
                child: Opacity(opacity: opacity, child: translated),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Hosts the two capsule pages — nav toolbar and mini player bar — and pages
/// between them with a horizontal swipe: the drag scrubs a cross-fade
/// directly, release settles it with the same direction-biased thresholds and
/// timing as the AppShell scroll reveal state machine.
class _ToolbarPager extends StatefulWidget {
  const _ToolbarPager({
    required this.location,
    required this.routeLocation,
    required this.actionWidth,
    required this.actionHeight,
    required this.toolbarHeight,
  });

  final String location;
  final String routeLocation;
  final double actionWidth;
  final double actionHeight;
  final double toolbarHeight;

  @override
  State<_ToolbarPager> createState() => _ToolbarPagerState();
}

class _ToolbarPagerState extends State<_ToolbarPager>
    with SingleTickerProviderStateMixin {
  /// 0 shows [_page] fully, 1 shows the other page fully. Once a switch
  /// settles at 1 the pages are swapped and the value snaps back to 0.
  late final AnimationController _switch;
  int _page = 0; // 0 = nav toolbar, 1 = mini player bar.
  double _dragSign = 0;
  double _lastDragDelta = 0;

  @override
  void initState() {
    super.initState();
    _switch = AnimationController(vsync: this);
  }

  @override
  void dispose() {
    _switch.dispose();
    super.dispose();
  }

  void _handleDragStart(DragStartDetails details) {
    _switch.stop(canceled: false);
    _dragSign = 0;
    _lastDragDelta = 0;
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    final dx = details.delta.dx;
    if (dx == 0) return;
    if (_dragSign == 0) _dragSign = dx.sign;
    _lastDragDelta = dx;
    final step =
        (dx.sign == _dragSign ? 1 : -1) * dx.abs() / toolbarPageDragExtent;
    _switch.value = (_switch.value + step).clamp(0.0, 1.0);
  }

  void _settleAfterDrag() {
    final value = _switch.value;
    // Positive = the last finger movement kept pushing towards the other
    // page; negative = it was heading back. Same direction bias as
    // _settleToolbarAfterScroll in app_shell.dart.
    final lastStep = _dragSign == 0 ? 0.0 : _lastDragDelta * _dragSign;
    final target = switch (lastStep) {
      > 0 => value >= toolbarShowDirectionThreshold ? 1.0 : 0.0,
      < 0 => value <= toolbarHideDirectionThreshold ? 0.0 : 1.0,
      _ => value >= 0.5 ? 1.0 : 0.0,
    };
    _lastDragDelta = 0;
    _animateSwitchTo(target);
  }

  void _animateSwitchTo(double target) {
    if ((_switch.value - target).abs() < 0.001 ||
        (MediaQuery.maybeDisableAnimationsOf(context) ?? false)) {
      _switch.value = target;
      _finishSwitchIfNeeded();
      return;
    }
    final remaining = (_switch.value - target).abs();
    _switch
        .animateTo(
          target,
          duration: Duration(milliseconds: (140 + 180 * remaining).round()),
          curve: AppMotion.emphasized,
        )
        .whenCompleteOrCancel(_finishSwitchIfNeeded);
  }

  void _finishSwitchIfNeeded() {
    if (!mounted || _switch.value != 1.0) return;
    setState(() {
      _page = 1 - _page;
      _switch.value = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final pageSize = Size(
      widget.actionWidth * toolbarActionCount,
      widget.toolbarHeight,
    );
    final navPage = _MainToolbar(
      location: widget.location,
      routeLocation: widget.routeLocation,
      actionWidth: widget.actionWidth,
      actionHeight: widget.actionHeight,
      toolbarHeight: widget.toolbarHeight,
    );
    final miniPage = SizedBox.fromSize(
      size: pageSize,
      child: MiniPlayerBar(
        width: pageSize.width,
        height: pageSize.height,
        onOpenPlayer: () =>
            navigateShellTo(context, widget.routeLocation, '/player'),
      ),
    );
    final pull = PlayerPullScope.maybeOf(context);
    return Listener(
      // Fires before the drag clears the touch slop, giving the player layer a
      // head start on mounting and rendering its backdrop off screen.
      onPointerDown: pull == null ? null : (_) => pull.onWarm(),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: _handleDragStart,
        onHorizontalDragUpdate: _handleDragUpdate,
        onHorizontalDragEnd: (_) => _settleAfterDrag(),
        onHorizontalDragCancel: _settleAfterDrag,
        // Vertical and horizontal recognizers share the arena: whichever axis
        // clears the slop first wins, and the vertical one is registered first
        // so a diagonal drag resolves to pulling the player up.
        onVerticalDragStart: pull == null ? null : (_) => pull.onStart(),
        onVerticalDragUpdate: pull == null
            ? null
            : (details) => pull.onUpdate(details.delta.dy),
        onVerticalDragEnd: pull == null
            ? null
            : (details) => pull.onEnd(details.velocity.pixelsPerSecond.dy),
        onVerticalDragCancel: pull?.onCancel,
        // Transform.translate paints outside the capsule during the switch;
        // Stack only clips layout overflow, so clip explicitly.
        child: ClipRect(
          child: AnimatedBuilder(
            animation: _switch,
            builder: (context, _) {
              final v = _switch.value;
              final sign = _dragSign == 0 ? -1.0 : _dragSign;
              final current = _page == 0 ? navPage : miniPage;
              final other = _page == 0 ? miniPage : navPage;
              return Stack(
                alignment: Alignment.center,
                children: [
                  if (v < 1)
                    IgnorePointer(
                      ignoring: v >= 0.5,
                      child: ExcludeSemantics(
                        excluding: v >= 0.5,
                        child: Opacity(
                          opacity: 1 - v,
                          child: Transform.translate(
                            offset: Offset(
                              sign * toolbarPageSlideExtent * v,
                              0,
                            ),
                            child: current,
                          ),
                        ),
                      ),
                    ),
                  if (v > 0)
                    IgnorePointer(
                      ignoring: v < 0.5,
                      child: ExcludeSemantics(
                        excluding: v < 0.5,
                        child: Opacity(
                          opacity: v,
                          child: Transform.translate(
                            offset: Offset(
                              -sign * toolbarPageSlideExtent * (1 - v),
                              0,
                            ),
                            child: other,
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _MainToolbar extends ConsumerWidget {
  const _MainToolbar({
    required this.location,
    required this.routeLocation,
    required this.actionWidth,
    required this.actionHeight,
    required this.toolbarHeight,
  });

  final String location;
  final String routeLocation;
  final double actionWidth;
  final double actionHeight;
  final double toolbarHeight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedIndex = toolbarIndexFor(location);
    final playerPlaying = ref.watch(
      playerControllerProvider.select(
        (state) => state.hasTrack && state.playing,
      ),
    );
    return SizedBox(
      width: actionWidth * toolbarActionCount,
      height: toolbarHeight,
      child: Stack(
        alignment: Alignment.centerLeft,
        clipBehavior: Clip.none,
        children: [
          AnimatedPositioned(
            left: selectedIndex * actionWidth,
            top: (toolbarHeight - actionHeight) / 2,
            duration: AppMotion.medium,
            curve: AppMotion.emphasized,
            child: ToolbarSlidingIndicator(
              width: actionWidth,
              height: actionHeight,
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ToolbarAction(
                tooltip: '发现',
                label: '发现',
                icon: Icons.explore_rounded,
                selected: isDiscoveryLocation(location),
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
              ToolbarAction(
                tooltip: '歌曲',
                label: '歌曲',
                icon: Icons.library_music_rounded,
                selected:
                    isSongsLibraryLocation(location) ||
                    location == '/downloads' ||
                    isPlaylistLocation(location),
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
              ToolbarAction(
                tooltip: '播放页',
                label: '播放',
                icon: Icons.graphic_eq_rounded,
                selected: location == '/player',
                animatedPlayback: playerPlaying,
                width: actionWidth,
                height: actionHeight,
                onPressed: () =>
                    navigateShellTo(context, routeLocation, '/player'),
              ),
              ToolbarAction(
                tooltip: '设置',
                label: '设置',
                icon: Icons.tune_rounded,
                selected:
                    location.startsWith('/settings') || location == '/debug',
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
            ],
          ),
        ],
      ),
    );
  }
}
