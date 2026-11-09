import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:prism_ui/color_scheme.dart';
import 'package:prism_ui/context.dart';

const _knobDiameter = 16.5;
const _knobOverlap = 3.0;
const _barWidth = 2.0;
const _knobReach = _knobDiameter - _knobOverlap;

/// The selected text's background, at the opacities iOS 27 gives it.
Color textSelectionColorOf(ColorScheme colorScheme) => colorScheme.primary
    .withValues(alpha: colorScheme.brightness == Brightness.dark ? 0.35 : 0.2);

bool get isDesktopPlatform => switch (defaultTargetPlatform) {
  TargetPlatform.macOS ||
  TargetPlatform.linux ||
  TargetPlatform.windows => true,
  TargetPlatform.android ||
  TargetPlatform.iOS ||
  TargetPlatform.fuchsia => false,
};

TextSelectionControls textSelectionControlsFor(TargetPlatform platform) =>
    switch (platform) {
      TargetPlatform.android ||
      TargetPlatform.iOS ||
      TargetPlatform.fuchsia => _touchTextSelectionControls,
      TargetPlatform.macOS ||
      TargetPlatform.linux ||
      TargetPlatform.windows => _pointerTextSelectionControls,
    };

final TextSelectionControls _touchTextSelectionControls =
    _TouchTextSelectionControls();

final TextSelectionControls _pointerTextSelectionControls =
    _PointerTextSelectionControls();

// With TextSelectionHandleControls, which emptyTextSelectionControls lacks, an
// editable text opens its contextMenuBuilder rather than the controls' toolbar.
class _PointerTextSelectionControls extends TextSelectionControls
    with TextSelectionHandleControls {
  @override
  Size getHandleSize(double textLineHeight) => Size.zero;

  @override
  Widget buildHandle(
    BuildContext context,
    TextSelectionHandleType type,
    double textLineHeight, [
    VoidCallback? onTap,
  ]) => const SizedBox.shrink();

  @override
  Offset getHandleAnchor(TextSelectionHandleType type, double textLineHeight) =>
      Offset.zero;
}

class _TouchTextSelectionControls extends TextSelectionControls
    with TextSelectionHandleControls {
  @override
  Size getHandleSize(double textLineHeight) =>
      Size(_knobDiameter, textLineHeight + _knobReach);

  @override
  Widget buildHandle(
    BuildContext context,
    TextSelectionHandleType type,
    double textLineHeight, [
    VoidCallback? onTap,
  ]) {
    final size = getHandleSize(textLineHeight);
    final handle = SizedBox.fromSize(
      size: size,
      child: CustomPaint(painter: _HandlePainter(context.colorScheme.primary)),
    );
    return switch (type) {
      TextSelectionHandleType.left => handle,
      TextSelectionHandleType.right => Transform.rotate(
        angle: math.pi,
        child: handle,
      ),
      // Nothing to see, but dragging the caret goes through it.
      TextSelectionHandleType.collapsed => SizedBox.fromSize(size: size),
    };
  }

  @override
  Offset getHandleAnchor(TextSelectionHandleType type, double textLineHeight) {
    final size = getHandleSize(textLineHeight);
    return switch (type) {
      TextSelectionHandleType.left => Offset(size.width / 2, size.height),
      TextSelectionHandleType.right => Offset(size.width / 2, textLineHeight),
      TextSelectionHandleType.collapsed => Offset(
        size.width / 2,
        textLineHeight + _knobReach / 2,
      ),
    };
  }
}

class _HandlePainter extends CustomPainter {
  const _HandlePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const center = Offset(_knobDiameter / 2, _knobDiameter / 2);
    canvas
      ..drawCircle(
        center.translate(0, 2),
        _knobDiameter / 2,
        Paint()
          ..color = const Color(0x4D000000)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      )
      ..drawLine(
        center,
        Offset(center.dx, size.height - _barWidth / 2),
        Paint()
          ..color = color
          ..strokeWidth = _barWidth
          ..strokeCap = StrokeCap.round,
      )
      ..drawCircle(center, _knobDiameter / 2, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_HandlePainter oldDelegate) => oldDelegate.color != color;
}
