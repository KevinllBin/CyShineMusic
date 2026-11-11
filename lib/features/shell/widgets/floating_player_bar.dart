import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/app_motion.dart';
import '../../player/player_controller.dart';
import '../player_pull_scope.dart';
import '../shell_navigation.dart';
import 'mini_player_bar.dart';
import 'toolbar_capsule.dart';

// Swipe-to-skip feedback: the finger scrubs the capsule contents sideways
// with resistance; a committed swipe slides them out and the next track in.
const double _swipeDragResistance = 0.55;
const double _swipeMaxDrag = 44;
const double _swipeBlockedMaxDrag = 14;
const double _swipeExitExtent = 72;
const double _swipeCommitOffset = 48 * _swipeDragResistance;
const double _swipeFlingOffset = 12 * _swipeDragResistance;
const Duration _swipeExitDuration = Duration(milliseconds: 130);

class FloatingPlayerBar extends ConsumerStatefulWidget {
  const FloatingPlayerBar({
    super.key,
    required this.routeLocation,
    required this.width,
    required this.height,
  });

  final String routeLocation;
  final double width;
  final double height;

  @override
  ConsumerState<FloatingPlayerBar> createState() => _FloatingPlayerBarState();
}

class _FloatingPlayerBarState extends ConsumerState<FloatingPlayerBar>
    with SingleTickerProviderStateMixin {
  // Horizontal offset of the capsule contents in logical pixels.
  late final AnimationController _shift = AnimationController.unbounded(
    vsync: this,
  );
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
    _shift.stop();
    // A new swipe during the exit animation still honours the earlier swipe.
    _pendingSkip?.call();
  }

  void _updateHorizontalDrag(DragUpdateDetails details) {
    final dx = details.delta.dx;
    final target = _shift.value + dx * _swipeDragResistance;
    final limit = _canSwitchToward(ref.read(playerControllerProvider), target)
        ? _swipeMaxDrag
        : _swipeBlockedMaxDrag;
    _shift.value = target.clamp(-limit, limit).toDouble();
  }

  void _cancelHorizontalDrag() {
    _settle(0);
  }

  void _finishHorizontalDrag(DragEndDetails details) {
    final offset = _shift.value;
    final velocity = details.velocity.pixelsPerSecond.dx;
    final fling =
        offset.abs() >= _swipeFlingOffset &&
        velocity.abs() >= 450 &&
        velocity.sign == offset.sign;
    final direction = fling ? velocity : offset;
    final commit = offset.abs() >= _swipeCommitOffset || fling;
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
