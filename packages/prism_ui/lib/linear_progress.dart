import 'package:flutter/widgets.dart';
import 'package:prism_ui/context.dart';
import 'package:prism_ui/shape.dart';

/// A pill that fills with [value], or runs two lines along itself while [value]
/// is null.
class LinearProgressIndicator extends StatefulWidget {
  const LinearProgressIndicator({
    super.key,
    this.value,
    this.backgroundColor,
    this.minHeight = 4,
  });

  final double? value;
  final Color? backgroundColor;
  final double minHeight;

  @override
  State<LinearProgressIndicator> createState() =>
      _LinearProgressIndicatorState();
}

class _LinearProgressIndicatorState extends State<LinearProgressIndicator>
    with SingleTickerProviderStateMixin {
  static const _indeterminate = Duration(milliseconds: 1800);

  late final _controller = AnimationController(
    vsync: this,
    duration: _indeterminate,
  );

  @override
  void initState() {
    super.initState();
    if (widget.value == null) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(LinearProgressIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value == null && !_controller.isAnimating) {
      _controller.repeat();
    } else if (widget.value != null && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final value = widget.value;
    Widget indicator = ConstrainedBox(
      constraints: BoxConstraints(
        minWidth: double.infinity,
        minHeight: widget.minHeight,
      ),
      child: CustomPaint(
        painter: _LinearProgressPainter(
          track: widget.backgroundColor ?? colorScheme.secondaryContainer,
          fill: colorScheme.primary,
          value: value?.clamp(0.0, 1.0),
          textDirection: Directionality.of(context),
          progress: _controller,
        ),
      ),
    );
    if (value == null) {
      indicator = ClipRSuperellipse(
        borderRadius: AppRadius.full,
        child: indicator,
      );
    }
    return Semantics(
      value: value == null ? null : '${(value * 100).round()}%',
      child: RepaintBoundary(child: indicator),
    );
  }
}

class _LinearProgressPainter extends CustomPainter {
  _LinearProgressPainter({
    required this.track,
    required this.fill,
    required this.value,
    required this.textDirection,
    required this.progress,
  }) : super(repaint: value == null ? progress : null);

  final Color track;
  final Color fill;
  final double? value;
  final TextDirection textDirection;
  final Animation<double> progress;

  static const _durationMs = 1800.0;
  static const _line1Head = Interval(
    0,
    750 / _durationMs,
    curve: Cubic(0.2, 0, 0.8, 1),
  );
  static const _line1Tail = Interval(
    333 / _durationMs,
    (333 + 750) / _durationMs,
    curve: Cubic(0.4, 0, 1, 1),
  );
  static const _line2Head = Interval(
    1000 / _durationMs,
    (1000 + 567) / _durationMs,
    curve: Cubic(0, 0, 0.65, 1),
  );
  static const _line2Tail = Interval(
    1267 / _durationMs,
    (1267 + 533) / _durationMs,
    curve: Cubic(0.1, 0, 0.45, 1),
  );

  void _drawPill(Canvas canvas, Size size, double start, double end, Color c) {
    if (end - start <= 0) {
      return;
    }
    final ltr = textDirection == TextDirection.ltr;
    canvas.drawRSuperellipse(
      RSuperellipse.fromRectAndRadius(
        Rect.fromLTRB(
          (ltr ? start : 1 - end) * size.width,
          0,
          (ltr ? end : 1 - start) * size.width,
          size.height,
        ),
        const Radius.circular(AppCorner.full),
      ),
      Paint()..color = c,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    _drawPill(canvas, size, 0, 1, track);
    final value = this.value;
    if (value != null) {
      _drawPill(canvas, size, 0, value, fill);
      return;
    }
    final t = progress.value;
    _drawPill(
      canvas,
      size,
      _line1Tail.transform(t),
      _line1Head.transform(t),
      fill,
    );
    _drawPill(
      canvas,
      size,
      _line2Tail.transform(t),
      _line2Head.transform(t),
      fill,
    );
  }

  @override
  bool shouldRepaint(_LinearProgressPainter oldDelegate) =>
      oldDelegate.track != track ||
      oldDelegate.fill != fill ||
      oldDelegate.value != value ||
      oldDelegate.textDirection != textDirection;
}
