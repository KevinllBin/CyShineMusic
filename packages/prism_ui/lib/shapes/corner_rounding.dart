part of 'shapes.dart';

class CornerRounding {
  static const unrounded = CornerRounding();

  const CornerRounding({this.radius = 0, this.smoothing = 0})
    : assert(radius >= 0, 'radius has to be greater that zero'),
      assert(
        smoothing >= 0 && smoothing <= 1,
        'smoothing has to be in range [0, 1]',
      );

  final double radius;

  final double smoothing;
}
