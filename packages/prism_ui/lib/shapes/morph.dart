part of 'shapes.dart';

class Morph {
  Morph(RoundedPolygon start, RoundedPolygon end)
    : _morphMatch = _match(start, end);

  final List<(Cubic, Cubic)> _morphMatch;

  static List<(Cubic, Cubic)> _match(RoundedPolygon p1, RoundedPolygon p2) {
    final measuredPolygon1 = MeasuredPolygon.measurePolygon(
      const LengthMeasurer(),
      p1,
    );
    final measuredPolygon2 = MeasuredPolygon.measurePolygon(
      const LengthMeasurer(),
      p2,
    );

    final features1 = measuredPolygon1.features;
    final features2 = measuredPolygon2.features;

    final doubleMapper = featureMapper(features1, features2);

    final polygon2CutPoint = doubleMapper.map(0);

    final bs1 = measuredPolygon1;
    final bs2 = measuredPolygon2.cutAndShift(polygon2CutPoint);

    final ret = <(Cubic, Cubic)>[];
    var i1 = 0;
    var i2 = 0;
    var b1 = bs1.getOrNull(i1++);
    var b2 = bs2.getOrNull(i2++);
    while (b1 != null && b2 != null) {
      final b1a = (i1 == bs1.length) ? 1.0 : b1.endOutlineProgress;
      final b2a = (i2 == bs2.length)
          ? 1.0
          : doubleMapper.mapBack(
              positiveModulo(b2.endOutlineProgress + polygon2CutPoint, 1),
            );
      final minb = math.min(b1a, b2a);
      final (seg1, newb1) = (b1a > minb + angleEpsilon)
          ? b1.cutAtProgress(minb)
          : (b1, bs1.getOrNull(i1++));

      final (seg2, newb2) = (b2a > minb + angleEpsilon)
          ? b2.cutAtProgress(
              positiveModulo(doubleMapper.map(minb) - polygon2CutPoint, 1),
            )
          : (b2, bs2.getOrNull(i2++));

      ret.add((seg1.cubic, seg2.cubic));
      b1 = newb1;
      b2 = newb2;
    }

    assert(
      b1 == null && b2 == null,
      "Expected both Polygon's Cubic to be fully matched",
    );

    return ret;
  }

  List<Cubic> asCubics(double progress) {
    final result = <Cubic>[];

    Cubic? firstCubic;
    Cubic? lastCubic;

    for (var i = 0; i < _morphMatch.length; i++) {
      final cubic = Cubic._raw(
        List<double>.generate(8, (j) {
          return lerp(
            _morphMatch[i].$1.points[j],
            _morphMatch[i].$2.points[j],
            progress,
          );
        }),
      );

      firstCubic ??= cubic;
      if (lastCubic != null) {
        result.add(lastCubic);
      }
      lastCubic = cubic;
    }

    if (lastCubic != null && firstCubic != null) {
      result.add(
        Cubic(
          lastCubic.anchor0X,
          lastCubic.anchor0Y,
          lastCubic.control0X,
          lastCubic.control0Y,
          lastCubic.control1X,
          lastCubic.control1Y,
          firstCubic.anchor0X,
          firstCubic.anchor0Y,
        ),
      );
    }

    return result;
  }
}
