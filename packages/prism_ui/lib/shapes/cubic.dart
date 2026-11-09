part of 'shapes.dart';

class Cubic {
  Cubic(
    double anchor0X,
    double anchor0Y,
    double control0X,
    double control0Y,
    double control1X,
    double control1Y,
    double anchor1X,
    double anchor1Y,
  ) : this._raw([
        anchor0X,
        anchor0Y,
        control0X,
        control0Y,
        control1X,
        control1Y,
        anchor1X,
        anchor1Y,
      ]);

  const Cubic._raw(List<double> points)
    : assert(points.length == 8, 'Points array size should be 8.'),
      _points = points;

  Cubic.fromPoints(Point anchor0, Point control0, Point control1, Point anchor1)
    : this._raw([
        anchor0.x,
        anchor0.y,
        control0.x,
        control0.y,
        control1.x,
        control1.y,
        anchor1.x,
        anchor1.y,
      ]);

  factory Cubic.straightLine(double x0, double y0, double x1, double y1) {
    return Cubic._raw([
      x0,
      y0,
      lerp(x0, x1, 1 / 3),
      lerp(y0, y1, 1 / 3),
      lerp(x0, x1, 2 / 3),
      lerp(y0, y1, 2 / 3),
      x1,
      y1,
    ]);
  }

  factory Cubic.circularArc(
    double centerX,
    double centerY,
    double x0,
    double y0,
    double x1,
    double y1,
  ) {
    final p0d = directionVector(x0 - centerX, y0 - centerY);
    final p1d = directionVector(x1 - centerX, y1 - centerY);
    final rotatedP0 = p0d.rotate90();
    final rotatedP1 = p1d.rotate90();
    final clockwise = rotatedP0.dotProductXY(x1 - centerX, y1 - centerY) >= 0;
    final cosa = p0d.dotProduct(p1d);

    if (cosa > 0.999) {
      return Cubic.straightLine(x0, y0, x1, y1);
    }

    final k =
        distance(x0 - centerX, y0 - centerY) *
        4 /
        3 *
        (math.sqrt(2 * (1 - cosa)) - math.sqrt(1 - cosa * cosa)) /
        (1 - cosa) *
        (clockwise ? 1 : -1);

    return Cubic(
      x0,
      y0,
      x0 + rotatedP0.x * k,
      y0 + rotatedP0.y * k,
      x1 - rotatedP1.x * k,
      y1 - rotatedP1.y * k,
      x1,
      y1,
    );
  }

  Cubic.empty(double x0, double y0)
    : this._raw([x0, y0, x0, y0, x0, y0, x0, y0]);

  final List<double> _points;

  List<double> get points => UnmodifiableListView(_points);

  double get anchor0X => _points[0];

  double get anchor0Y => _points[1];

  double get control0X => _points[2];

  double get control0Y => _points[3];

  double get control1X => _points[4];

  double get control1Y => _points[5];

  double get anchor1X => _points[6];

  double get anchor1Y => _points[7];

  Point pointOnCurve(double t) {
    final u = 1 - t;
    return Point(
      anchor0X * (u * u * u) +
          control0X * (3 * t * u * u) +
          control1X * (3 * t * t * u) +
          anchor1X * (t * t * t),
      anchor0Y * (u * u * u) +
          control0Y * (3 * t * u * u) +
          control1Y * (3 * t * t * u) +
          anchor1Y * (t * t * t),
    );
  }

  bool zeroLength() =>
      (anchor0X - anchor1X).abs() < distanceEpsilon &&
      (anchor0Y - anchor1Y).abs() < distanceEpsilon;

  bool _zeroIsh(double value) => value.abs() < distanceEpsilon;

  void calculateBounds(List<double> bounds, {bool approximate = false}) {
    assert(bounds.length == 4, 'Bounds array size should be 4.');

    if (zeroLength()) {
      bounds[0] = anchor0X;
      bounds[1] = anchor0Y;
      bounds[2] = anchor0X;
      bounds[3] = anchor0Y;
      return;
    }

    var minX = math.min(anchor0X, anchor1X);
    var minY = math.min(anchor0Y, anchor1Y);
    var maxX = math.max(anchor0X, anchor1X);
    var maxY = math.max(anchor0Y, anchor1Y);

    if (approximate) {
      bounds[0] = math.min(minX, math.min(control0X, control1X));
      bounds[1] = math.min(minY, math.min(control0Y, control1Y));
      bounds[2] = math.max(maxX, math.max(control0X, control1X));
      bounds[3] = math.max(maxY, math.max(control0Y, control1Y));
      return;
    }

    final xa = -anchor0X + 3 * control0X - 3 * control1X + anchor1X;
    final xb = 2 * anchor0X - 4 * control0X + 2 * control1X;
    final xc = -anchor0X + control0X;

    if (_zeroIsh(xa)) {
      if (xb != 0) {
        final t = 2 * xc / (-2 * xb);
        if (t >= 0 && t <= 1) {
          final x = pointOnCurve(t).x;
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
        }
      }
    } else {
      final xs = xb * xb - 4 * xa * xc;
      if (xs >= 0) {
        final t1 = (-xb + math.sqrt(xs)) / (2 * xa);
        if (t1 >= 0 && t1 <= 1) {
          final x = pointOnCurve(t1).x;
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
        }

        final t2 = (-xb - math.sqrt(xs)) / (2 * xa);
        if (t2 >= 0 && t2 <= 1) {
          final x = pointOnCurve(t2).x;
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
        }
      }
    }

    final ya = -anchor0Y + 3 * control0Y - 3 * control1Y + anchor1Y;
    final yb = 2 * anchor0Y - 4 * control0Y + 2 * control1Y;
    final yc = -anchor0Y + control0Y;

    if (_zeroIsh(ya)) {
      if (yb != 0) {
        final t = 2 * yc / (-2 * yb);
        if (t >= 0 && t <= 1) {
          final y = pointOnCurve(t).y;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
        }
      }
    } else {
      final ys = yb * yb - 4 * ya * yc;
      if (ys >= 0) {
        final t1 = (-yb + math.sqrt(ys)) / (2 * ya);
        if (t1 >= 0 && t1 <= 1) {
          final y = pointOnCurve(t1).y;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
        }

        final t2 = (-yb - math.sqrt(ys)) / (2 * ya);
        if (t2 >= 0 && t2 <= 1) {
          final y = pointOnCurve(t2).y;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
        }
      }
    }

    bounds[0] = minX;
    bounds[1] = minY;
    bounds[2] = maxX;
    bounds[3] = maxY;
  }

  (Cubic, Cubic) split(double t) {
    final u = 1 - t;
    final point = pointOnCurve(t);

    return (
      Cubic(
        anchor0X,
        anchor0Y,
        anchor0X * u + control0X * t,
        anchor0Y * u + control0Y * t,
        anchor0X * (u * u) + control0X * (2 * u * t) + control1X * (t * t),
        anchor0Y * (u * u) + control0Y * (2 * u * t) + control1Y * (t * t),
        point.x,
        point.y,
      ),
      Cubic(
        point.x,
        point.y,
        control0X * (u * u) + control1X * (2 * u * t) + anchor1X * (t * t),
        control0Y * (u * u) + control1Y * (2 * u * t) + anchor1Y * (t * t),
        control1X * u + anchor1X * t,
        control1Y * u + anchor1Y * t,
        anchor1X,
        anchor1Y,
      ),
    );
  }

  Cubic reverse() => Cubic(
    anchor1X,
    anchor1Y,
    control1X,
    control1Y,
    control0X,
    control0Y,
    anchor0X,
    anchor0Y,
  );

  Cubic operator +(Cubic o) =>
      Cubic._raw(List.generate(8, (i) => _points[i] + o._points[i]));

  Cubic operator *(double x) =>
      Cubic._raw(List.generate(8, (i) => _points[i] * x));

  Cubic operator /(double x) => this * (1.0 / x);

  Cubic transformed(PointTransformer f) {
    final newCubic = _MutableCubic();
    for (var i = 0; i < 8; i++) {
      newCubic._points[i] = _points[i];
    }
    newCubic.transform(f);
    return newCubic;
  }
}

class _MutableCubic extends Cubic {
  _MutableCubic() : super._raw(List.filled(8, 0));

  void _transformOnePoint(PointTransformer f, int ix) {
    final result = f(_points[ix], _points[ix + 1]);
    _points[ix] = result.$1;
    _points[ix + 1] = result.$2;
  }

  void transform(PointTransformer f) {
    _transformOnePoint(f, 0);
    _transformOnePoint(f, 2);
    _transformOnePoint(f, 4);
    _transformOnePoint(f, 6);
  }

  void interpolate(Cubic c1, Cubic c2, double progress) {
    for (var i = 0; i < 8; i++) {
      _points[i] = lerp(c1._points[i], c2._points[i], progress);
    }
  }
}
