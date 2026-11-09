part of 'shapes.dart';

typedef PointTransformer = (double, double) Function(double x, double y);

class Point {
  static const zero = Point(0, 0);

  const Point(this.x, this.y);

  final double x;

  final double y;

  Point rotate90() => Point(-y, x);

  Point rotate(double degrees, {Point center = Point.zero}) {
    final radians = degrees * math.pi / 180;
    final off = this - center;
    final cos = math.cos(radians);
    final sin = math.sin(radians);
    return Point(off.x * cos - off.y * sin, off.x * sin + off.y * cos) + center;
  }

  double get angleRadians => math.atan2(y, x);

  double getDistance() => math.sqrt(x * x + y * y);

  double getDistanceSquared() => x * x + y * y;

  double dotProduct(Point other) => x * other.x + y * other.y;

  double dotProductXY(double otherX, double otherY) => x * otherX + y * otherY;

  bool clockwise(Point other) => (x * other.y - y * other.x) > 0;

  Point getDirection() {
    final d = getDistance();
    assert(d > 0, "Can't get the direction of a 0-length vector");
    return this / d;
  }

  Point operator -() => Point(-x, -y);

  Point operator -(Point operand) => Point(x - operand.x, y - operand.y);

  Point operator +(Point operand) => Point(x + operand.x, y + operand.y);

  Point operator *(double operand) => Point(x * operand, y * operand);

  Point operator /(double operand) => Point(x / operand, y / operand);

  Point operator %(double operand) => Point(x % operand, y % operand);

  Point transformed(PointTransformer f) {
    final result = f(x, y);
    return Point(result.$1, result.$2);
  }
}

Point interpolate(Point start, Point stop, double fraction) {
  return Point(
    lerp(start.x, stop.x, fraction),
    lerp(start.y, stop.y, fraction),
  );
}
