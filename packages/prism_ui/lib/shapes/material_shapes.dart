part of 'shapes.dart';

abstract final class MaterialShapes {
  static const _cornerRound50 = CornerRounding(radius: 0.5);

  static const _negative90Radians = -90 * math.pi / 180;

  static final circle = RoundedPolygon.circle(
    numVertices: 10,
    radius: 0.5,
    centerX: 0.5,
    centerY: 0.5,
  );

  static final cookie6Sided = _customPolygon([
    const _PointNRound(Point(0.723, 0.884), CornerRounding(radius: 0.394)),
    const _PointNRound(Point(0.5, 1.099), CornerRounding(radius: 0.398)),
  ], 6).normalized();

  static final cookie9Sided = RoundedPolygon.star(
    numVerticesPerRadius: 9,
    innerRadius: 0.8,
    rounding: _cornerRound50,
  ).transformed(_rotated(_negative90Radians)).normalized();

  static final cookie12Sided = RoundedPolygon.star(
    numVerticesPerRadius: 12,
    innerRadius: 0.8,
    rounding: _cornerRound50,
  ).transformed(_rotated(_negative90Radians)).normalized();

  static final clover4Leaf = _customPolygon(
    [
      const _PointNRound(Point(0.5, 0.074)),
      const _PointNRound(Point(0.725, -0.099), CornerRounding(radius: 0.476)),
    ],
    4,
    mirroring: true,
  ).normalized();

  static RoundedPolygon _customPolygon(
    List<_PointNRound> pnr,
    int reps, {
    Point center = const Point(0.5, 0.5),
    bool mirroring = false,
  }) {
    final actualPoints = _doRepeat(pnr, reps, center, mirroring);

    final vertices = List<double>.filled(actualPoints.length * 2, 0);
    final perVertexRounding = List<CornerRounding>.filled(
      actualPoints.length,
      CornerRounding.unrounded,
    );

    for (var i = 0; i < actualPoints.length; i++) {
      final ap = actualPoints[i];
      perVertexRounding[i] = ap.r;

      final j = i * 2;
      vertices[j] = ap.p.x;
      vertices[j + 1] = ap.p.y;
    }

    return RoundedPolygon.fromVertices(
      vertices,
      perVertexRounding: perVertexRounding,
      centerX: center.x,
      centerY: center.y,
    );
  }

  static List<_PointNRound> _doRepeat(
    List<_PointNRound> points,
    int reps,
    Point center,
    bool mirroring,
  ) {
    final result = <_PointNRound>[];

    if (mirroring) {
      final measures = List.generate(points.length, (i) {
        final point = points[i];
        final off = point.p - center;
        return (angle: off.angleRadians, distance: off.getDistance());
      });
      final actualReps = reps * 2;
      final sectionAngle = math.pi * 2 / actualReps;

      for (var r = 0; r < actualReps; r++) {
        for (var index = 0; index < points.length; index++) {
          final i = (r.isEven) ? index : points.length - 1 - index;
          if (i > 0 || r.isEven) {
            final a =
                sectionAngle * r +
                ((r.isEven)
                    ? measures[i].angle
                    : sectionAngle - measures[i].angle + 2 * measures[0].angle);

            final finalPoint =
                Point(math.cos(a), math.sin(a)) * measures[i].distance + center;

            result.add(_PointNRound(finalPoint, points[i].r));
          }
        }
      }
    } else {
      final np = points.length;
      for (var i = 0; i < np * reps; i++) {
        final point = points[i % np].p.rotate(
          (i ~/ np) * 360 / reps,
          center: center,
        );
        result.add(_PointNRound(point, points[i % np].r));
      }
    }

    return result;
  }
}

class _PointNRound {
  const _PointNRound(this.p, [this.r = CornerRounding.unrounded]);

  final Point p;

  final CornerRounding r;
}

PointTransformer _rotated(double radians) {
  final cos = math.cos(radians);
  final sin = math.sin(radians);
  return (x, y) => (cos * x - sin * y, sin * x + cos * y);
}
