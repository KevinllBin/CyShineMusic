part of 'shapes.dart';

const distanceEpsilon = 1e-5;
const angleEpsilon = 1e-6;

double distance(double x, double y) => math.sqrt(x * x + y * y);

Point directionVector(double x, double y) {
  final d = distance(x, y);
  assert(d > 0, 'Required distance greater than zero.');
  return Point(x / d, y / d);
}

Point directionVectorFromAngle(double angleRadians) =>
    Point(math.cos(angleRadians), math.sin(angleRadians));

Point radialToCartesian(
  double radius,
  double angleRadians, [
  Point center = Point.zero,
]) => directionVectorFromAngle(angleRadians) * radius + center;

double square(double x) => x * x;

double lerp(double start, double stop, double fraction) {
  return start * (1 - fraction) + stop * fraction;
}

double positiveModulo(double num, double mod) => (num % mod + mod) % mod;

bool convex(Point previous, Point current, Point next) {
  return (current - previous).clockwise(next - current);
}

int binarySearchBy<E, K>(
  List<E> sortedList,
  K Function(E element) keyOf,
  int Function(K, K) compare,
  K value, [
  int start = 0,
  int? end,
]) {
  end = RangeError.checkValidRange(start, end, sortedList.length);
  var min = start;
  var max = end;
  final key = value;
  while (min < max) {
    final mid = min + ((max - min) >> 1);
    final element = sortedList[mid];
    final comp = compare(keyOf(element), key);
    if (comp == 0) return mid;
    if (comp < 0) {
      min = mid + 1;
    } else {
      max = mid;
    }
  }
  return -min - 1;
}

extension DoubleCoerceExtensions on double {
  double coerceIn(double minimumValue, double maximumValue) {
    if (this < minimumValue) return minimumValue;
    if (this > maximumValue) return maximumValue;
    return this;
  }
}

extension RoundedPolygonToPathExtension on RoundedPolygon {
  Path toPath() => _pathFromCubics(cubics);
}

extension MorphToPathExtension on Morph {
  Path toPath({required double progress}) =>
      _pathFromCubics(asCubics(progress));
}

Path _pathFromCubics(List<Cubic> cubics) {
  final path = Path()..moveTo(cubics.first.anchor0X, cubics.first.anchor0Y);
  for (final cubic in cubics) {
    path.cubicTo(
      cubic.control0X,
      cubic.control0Y,
      cubic.control1X,
      cubic.control1Y,
      cubic.anchor1X,
      cubic.anchor1Y,
    );
  }
  return path..close();
}
