import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cy_shine_music/features/shell/player_transition.dart';

void main() {
  test('cover bends across before growing and lands on measured endpoints', () {
    const small = Rect.fromLTWH(25, 727, 34, 34);
    const large = Rect.fromLTWH(32, 152, 296, 296);
    expect(PlayerMotion.cover(small, large, 0), small);
    expect(PlayerMotion.cover(small, large, 1), large);
    final half = PlayerMotion.cover(small, large, 0.5);
    expect(half.center.dx, 145.5);
    expect(half.center.dy, 633);
    expect(half.size, const Size(99.5, 99.5));
  });

  test('surface radius follows diagonal ratio and remains valid', () {
    const small = Rect.fromLTWH(80, 1510, 200, 56);
    const screen = Size(360, 1600);
    expect(PlayerMotion.surface(small, screen, 0).outerRect, small);
    expect(PlayerMotion.surface(small, screen, 0).tlRadiusX, 28);
    expect(PlayerMotion.surface(small, screen, 0.3).tlRadiusX, greaterThan(28));
    expect(
      PlayerMotion.surface(small, screen, 1),
      RRect.fromRectAndRadius(Offset.zero & screen, Radius.zero),
    );
    for (var i = 0; i <= 100; i++) {
      final surface = PlayerMotion.surface(small, screen, i / 100);
      expect(surface.tlRadiusX * 2, lessThanOrEqualTo(surface.shortestSide));
      expect(surface.isFinite, isTrue);
    }
  });

  test('background, mini controls and full controls have separate windows', () {
    expect(PlayerMotion.interval(0.06, 0, 0.12), 0.5);
    expect(PlayerMotion.interval(0.12, 0, 0.12), 1);
    expect(PlayerMotion.interval(0.2, 0, 0.2), 1);
    expect(PlayerMotion.interval(0.33, 0.33, 0.86), 0);
    expect(PlayerMotion.interval(0.5, 0.33, 0.86), closeTo(0.243, 0.001));
    expect(PlayerMotion.interval(0.86, 0.33, 0.86), 1);
  });

  bool settle(
    double p,
    double velocity, {
    bool expanded = false,
    bool nested = false,
    double start = 0,
  }) => PlayerMotion.shouldExpand(
    progress: p,
    travel: 700,
    velocityY: velocity,
    wasExpanded: expanded,
    fromPlayer: nested,
    startProgress: start,
  );

  test('mini drag uses 56dp displacement or a directional 125dp/s fling', () {
    expect(settle(55 / 700, 0), isFalse);
    expect(settle(56 / 700, 0), isTrue);
    expect(settle(10 / 700, -125), isTrue);
    expect(settle(0, -1000), isFalse);
    expect(settle(1 - 55 / 700, 0, expanded: true), isTrue);
    expect(settle(1 - 56 / 700, 0, expanded: true), isFalse);
  });

  test('player drag gives direction priority and uses 32dp at rest', () {
    expect(settle(.98, 1, expanded: true, nested: true, start: 1), isFalse);
    expect(settle(.7, -1, expanded: true, nested: true, start: 1), isTrue);
    expect(
      settle(1 - 33 / 700, 0, expanded: true, nested: true, start: 1),
      isFalse,
    );
    expect(
      settle(1 - 20 / 700, 0, expanded: true, nested: true, start: 1),
      isTrue,
    );
  });

  test('spring keeps its velocity on interruption and has a gentle tail', () {
    final open = PlayerSpringSimulation(0, 1, 0, distanceTolerance: .01 / 2100);
    expect(open.x(0), closeTo(0, 1e-12));
    expect(open.x(.1), closeTo(.58340, .00002));
    expect(open.x(.3), closeTo(.96989, .00002));
    expect(open.isDone(.3), isFalse);
    expect(open.x(open.duration), 1);
    final reverse = PlayerSpringSimulation(
      open.x(.15),
      0,
      open.dx(.15),
      distanceTolerance: .01 / 2100,
    );
    expect(reverse.x(0), closeTo(open.x(.15), 1e-12));
    expect(reverse.dx(0), closeTo(open.dx(.15), 1e-10));
    expect(reverse.x(.01), greaterThan(reverse.x(0)));
    expect(reverse.x(reverse.duration), 0);
    expect(reverse.dx(reverse.duration), 0);
  });
}
