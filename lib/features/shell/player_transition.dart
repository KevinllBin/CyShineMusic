import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Salt 12.3's geometry is driven by distance, not by a second time curve.
abstract final class PlayerMotion {
  static const stiffness = 438.64905;
  static const dampingRatio = 1.1;
  static const positionThreshold = 56.0;
  static const velocityThreshold = 125.0;

  static double interval(double p, double start, double end) {
    final t = ((p - start) / (end - start)).clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }

  static RRect surface(Rect start, Size viewport, double progress) {
    final p = progress.clamp(0.0, 1.0);
    final rect = Rect.lerp(start, Offset.zero & viewport, p)!;
    final startDiagonal = math.sqrt(
      start.width * start.width + start.height * start.height,
    );
    final radius = startDiagonal == 0
        ? 0.0
        : start.shortestSide /
              2 /
              startDiagonal *
              (1 - p) *
              math.sqrt(rect.width * rect.width + rect.height * rect.height);
    return RRect.fromRectAndRadius(
      rect,
      Radius.circular(math.min(radius, rect.shortestSide / 2)),
    );
  }

  static Rect cover(Rect start, Rect end, double progress) {
    final p = progress.clamp(0.0, 1.0);
    final horizontal = 1 - (1 - p) * (1 - p);
    final vertical = p * p;
    return Rect.fromCenter(
      center: Offset(
        start.center.dx + (end.center.dx - start.center.dx) * horizontal,
        start.center.dy + (end.center.dy - start.center.dy) * vertical,
      ),
      width: start.width + (end.width - start.width) * vertical,
      height: start.height + (end.height - start.height) * vertical,
    );
  }

  static bool shouldExpand({
    required double progress,
    required double travel,
    required double velocityY,
    required bool wasExpanded,
    required bool fromPlayer,
    required double startProgress,
  }) {
    if (progress <= 0) return false;
    if (progress >= 1) return true;
    if (fromPlayer) {
      if (velocityY != 0) return velocityY < 0;
      final distance = (progress - startProgress) * travel;
      if (distance.abs() >= 32) return distance > 0;
    }
    if (velocityY.abs() >= velocityThreshold) return velocityY < 0;
    return wasExpanded
        ? progress > 1 - positionThreshold / travel
        : progress >= positionThreshold / travel;
  }
}

class PlayerPhase extends Animatable<double> {
  const PlayerPhase(this.start, this.end);
  final double start, end;
  @override
  double transform(double t) => PlayerMotion.interval(t, start, end);
}

/// Analytic overdamped spring, including release velocity and the final tail.
/// The cutoff is supplied in progress units (Salt uses 0.01 physical pixels).
class PlayerSpringSimulation extends Simulation {
  PlayerSpringSimulation(
    double start,
    this.target,
    double velocity, {
    required double distanceTolerance,
  }) {
    final omega = math.sqrt(PlayerMotion.stiffness);
    final decay = PlayerMotion.dampingRatio * omega;
    final split =
        omega *
        math.sqrt(PlayerMotion.dampingRatio * PlayerMotion.dampingRatio - 1);
    _slow = -decay + split;
    _fast = -decay - split;
    _a = (velocity - _fast * (start - target)) / (_slow - _fast);
    _b = start - target - _a;
    // Search after the turning point, so a reverse flick never finishes at
    // its first crossing of the target. Millisecond sampling matches Compose.
    final ratio = -_b * _fast / (_a * _slow);
    final turn = ratio > 0 ? math.log(ratio) / (_slow - _fast) : 0.0;
    var low = turn.isFinite ? math.max(0.0, turn) : 0.0;
    var high = math.max(0.016, low);
    final epsilon = math.max(1e-10, distanceTolerance);
    while (_displacement(high).abs() > epsilon) {
      high *= 2;
    }
    for (var i = 0; i < 40; i++) {
      final mid = (low + high) / 2;
      if (_displacement(mid).abs() > epsilon) {
        low = mid;
      } else {
        high = mid;
      }
    }
    duration = (high * 1000).floorToDouble() / 1000;
  }

  final double target;
  late final double _slow, _fast, _a, _b;
  late final double duration;

  double _displacement(double t) =>
      _a * math.exp(_slow * t) + _b * math.exp(_fast * t);

  @override
  double x(double time) => isDone(time)
      ? target
      : target + _displacement((time * 1000).floorToDouble() / 1000);

  @override
  double dx(double time) {
    if (isDone(time)) return 0;
    final t = (time * 1000).floorToDouble() / 1000;
    return _a * _slow * math.exp(_slow * t) + _b * _fast * math.exp(_fast * t);
  }

  @override
  bool isDone(double time) => time >= duration;
}

/// Measurements belong to the shell. Keys sit outside track switchers, so
/// outgoing artwork cannot register a second copy of an endpoint.
class PlayerTransition extends ChangeNotifier {
  PlayerTransition({required this.progress, required this.rotation}) {
    progress.addListener(notifyListeners);
  }

  final Animation<double> progress;
  final Animation<double> rotation;
  final rootKey = GlobalKey(debugLabel: 'player-transition-root');
  final surfaceKey = GlobalKey(debugLabel: 'player-capsule-anchor');
  final miniCoverKey = GlobalKey(debugLabel: 'player-mini-cover-anchor');
  final fullCoverKey = GlobalKey(debugLabel: 'player-full-cover-anchor');
  final pageKey = GlobalKey(debugLabel: 'player-full-page-anchor');
  Rect? collapsedSurface, miniCover, fullCover;
  Size viewport = Size.zero;
  double bottomInset = 0;

  Rect get sourceSurface =>
      collapsedSurface ??
      Rect.fromLTWH(
        14,
        math.max(0, viewport.height - bottomInset - 64),
        math.max(0, viewport.width - 28),
        56,
      );
  double get travel => math.max(1, sourceSurface.top - 4);
  bool get flying =>
      progress.value > 0 &&
      progress.value < 1 &&
      miniCover != null &&
      fullCover != null;
  RRect get surface =>
      PlayerMotion.surface(sourceSurface, viewport, progress.value);
  Rect? get coverRect => flying
      ? PlayerMotion.cover(miniCover!, fullCover!, progress.value)
      : null;

  void capture({bool refreshSource = false}) {
    final root = rootKey.currentContext?.findRenderObject();
    final page = pageKey.currentContext?.findRenderObject();
    if (root is! RenderBox || !root.hasSize) return;
    if (viewport.isEmpty) viewport = root.size;
    if (progress.value == 0 || refreshSource) {
      final paintedTranslation = progress.value * travel;
      collapsedSurface = _rect(surfaceKey, root);
      miniCover = _rect(miniCoverKey, root)?.translate(0, paintedTranslation);
      if (collapsedSurface != null &&
          !(Offset.zero & viewport).contains(collapsedSurface!.center)) {
        collapsedSurface = null;
        miniCover = null;
      }
    }
    if (page is RenderBox && page.hasSize) {
      final end = _rect(fullCoverKey, page);
      // The horizontal lyrics page may retain an offscreen album endpoint.
      fullCover =
          end != null && end.left >= -0.5 && end.right <= viewport.width + 0.5
          ? end
          : null;
    }
    notifyListeners();
  }

  static Rect? _rect(GlobalKey key, RenderBox ancestor) {
    final box = key.currentContext?.findRenderObject();
    if (box is! RenderBox ||
        !box.attached ||
        !box.hasSize ||
        box.size.isEmpty) {
      return null;
    }
    final top = box.localToGlobal(Offset.zero, ancestor: ancestor);
    final rect = top & box.size;
    return rect.isFinite ? rect : null;
  }

  @override
  void dispose() {
    progress.removeListener(notifyListeners);
    super.dispose();
  }
}

class PlayerTransitionScope extends InheritedWidget {
  const PlayerTransitionScope({
    super.key,
    required this.transition,
    required super.child,
  });
  final PlayerTransition transition;
  static PlayerTransition? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<PlayerTransitionScope>()
      ?.transition;
  @override
  bool updateShouldNotify(PlayerTransitionScope oldWidget) =>
      transition != oldWidget.transition;
}

class PlayerCoverAnchor extends StatelessWidget {
  const PlayerCoverAnchor({
    super.key,
    required this.expanded,
    required this.child,
  });
  final bool expanded;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final transition = PlayerTransitionScope.maybeOf(context);
    if (transition == null) return child;
    return KeyedSubtree(
      key: expanded ? transition.fullCoverKey : transition.miniCoverKey,
      child: AnimatedBuilder(
        animation: transition,
        child: child,
        builder: (context, child) =>
            Opacity(opacity: transition.flying ? 0 : 1, child: child),
      ),
    );
  }
}
