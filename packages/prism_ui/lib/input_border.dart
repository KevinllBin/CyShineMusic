import 'package:flutter/painting.dart';

abstract class InputBorder extends ShapeBorder {
  const InputBorder({this.borderSide = BorderSide.none});

  final BorderSide borderSide;

  bool get isOutline;

  InputBorder copyWith({BorderSide? borderSide});
}

class NoInputBorder extends InputBorder {
  const NoInputBorder();

  @override
  bool get isOutline => false;

  @override
  NoInputBorder copyWith({BorderSide? borderSide}) => const NoInputBorder();

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  NoInputBorder scale(double t) => const NoInputBorder();

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      Path()..addRect(rect);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      Path()..addRect(rect);

  @override
  bool get preferPaintInterior => true;

  @override
  void paintInterior(
    Canvas canvas,
    Rect rect,
    Paint paint, {
    TextDirection? textDirection,
  }) => canvas.drawRect(rect, paint);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {}
}
