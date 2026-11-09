import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:prism_ui/context.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/null_status.dart';

/// Hands a switcher's transition to an [ActivityIndicator.page] inside it, so
/// the shapes shrink away while the switcher takes the page away.
class ActivityPresence extends InheritedWidget {
  const ActivityPresence({
    super.key,
    required this.animation,
    required super.child,
  });

  final Animation<double> animation;

  static Animation<double>? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ActivityPresence>()?.animation;

  @override
  bool updateShouldNotify(ActivityPresence oldWidget) =>
      oldWidget.animation != animation;
}

class ActivityIndicator extends StatefulWidget {
  const ActivityIndicator({
    super.key,
    this.size,
    this.color,
    this.semanticLabel,
  }) : _page = false;

  const ActivityIndicator.page({super.key, this.color, this.semanticLabel})
    : size = null,
      _page = true;

  static const _pageScale = 0.8;

  final double? size;
  final Color? color;
  final String? semanticLabel;
  final bool _page;

  @override
  State<ActivityIndicator> createState() => _ActivityIndicatorState();
}

class _ActivityIndicatorState extends State<ActivityIndicator>
    with SingleTickerProviderStateMixin {
  // A screen of delay tests runs dozens of these, which only read as one
  // motion if each picks up the same moment instead of starting from zero.
  static final _clock = Stopwatch()..start();

  Duration get _loop => widget._page ? _RelayPainter.loop : _ArcPainter.loop;

  late final AnimationController _progress = AnimationController(
    vsync: this,
    duration: _loop,
    value:
        _clock.elapsedMicroseconds %
        _loop.inMicroseconds /
        _loop.inMicroseconds,
  )..repeat();
  late final Animation<double> _rise = context.disableAnimations
      ? kAlwaysCompleteAnimation
      : _Rise(_progress, _loop);

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? context.colorScheme.primary;
    final still = context.disableAnimations;
    return Semantics(
      label: widget.semanticLabel,
      child: RepaintBoundary(
        child: widget._page
            ? CustomPaint(
                size: Size.square(
                  EmptyIllustration.dimensionOf(context) *
                      ActivityIndicator._pageScale,
                ),
                painter: _RelayPainter(
                  progress: _progress,
                  rise: _rise,
                  presence: ActivityPresence.maybeOf(context),
                  color: color,
                  still: still,
                ),
              )
            : CustomPaint(
                size: Size.square(
                  widget.size ?? IconTheme.of(context).size ?? Glyph.size,
                ),
                painter: _ArcPainter(
                  progress: _progress,
                  color: color,
                  still: still,
                ),
              ),
      ),
    );
  }
}

/// How far a page's indicator has grown in, read off its own loop: a page holds
/// its load until nothing but the one indicator animates, so this cannot run on
/// a ticker of its own.
class _Rise extends Animation<double> with AnimationWithParentMixin<double> {
  _Rise(this.parent, this.loop) : _start = parent.value;

  static const _duration = Duration(milliseconds: 240);

  @override
  final Animation<double> parent;
  final Duration loop;
  final double _start;
  var _done = false;

  @override
  double get value {
    if (_done) {
      return 1;
    }
    final elapsed = (parent.value - _start) % 1 * loop.inMilliseconds;
    if (elapsed >= _duration.inMilliseconds) {
      _done = true;
      return 1;
    }
    return Curves.easeOutCubic.transform(elapsed / _duration.inMilliseconds);
  }
}

const _trackInk = 0.2;

/// A solid arc that stretches and shrinks as it turns over a faint ring.
class _ArcPainter extends CustomPainter {
  _ArcPainter({
    required this.progress,
    required this.color,
    required this.still,
  }) : super(repaint: progress);

  static const loop = Duration(milliseconds: 3200);

  // A glyph keeps its outline within 20 of its 24 grid, so the ring standing
  // in for one reads at the same size.
  static const _liveArea = 20 / 24;
  static const _minStrokeWidth = 1.5;
  static const _maxStrokeWidth = 4.0;
  static const _turns = 3;
  static const _stretches = 2;
  static const _minSweep = 0.1;
  static const _maxSweep = 0.62;
  static const _headLead = 0.14;

  final Animation<double> progress;
  final Color color;
  final bool still;

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide;
    final strokeWidth = ui.clampDouble(
      side / 9,
      _minStrokeWidth,
      _maxStrokeWidth,
    );
    final radius = (side * _liveArea - strokeWidth) / 2;
    if (radius <= 0) {
      return;
    }
    final center = size.center(Offset.zero);
    final t = progress.value;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = color.withValues(alpha: color.a * _trackInk);
    canvas.drawCircle(center, radius, stroke);
    if (still) {
      final breath = 0.5 - 0.5 * math.cos(t * 4 * math.pi);
      canvas.drawCircle(
        center,
        radius,
        stroke..color = color.withValues(alpha: color.a * (0.3 + 0.5 * breath)),
      );
      return;
    }
    final stretch = 0.5 - 0.5 * math.cos(t * _stretches * 2 * math.pi);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      (t * _turns + _headLead * stretch) * 2 * math.pi,
      ui.lerpDouble(_minSweep, _maxSweep, stretch)! * 2 * math.pi,
      false,
      stroke
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_ArcPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.still != still;
  }
}

/// Three of the shapes an empty page's illustration picks from, hopping in turn
/// above their marks on the ground.
class _RelayPainter extends CustomPainter {
  _RelayPainter({
    required this.progress,
    required this.rise,
    required this.presence,
    required this.color,
    required this.still,
  }) : super(repaint: Listenable.merge([progress, rise, ?presence]));

  static const loop = Duration(milliseconds: 1200);

  static const _canvas = 160.0;
  static const _shapeRadius = 20.0;
  static const _spacing = 52.0;
  static const _shapeY = 6.0;
  static const _hop = 30.0;
  static const _hopShare = 0.25;
  static const _stagger = 1 / 6;
  static const _hopCurve = Cubic(0.3, 0, 0.3, 1);
  static const _groundY = 41.0;
  static const _groundSize = Size(44, 6);
  static const _groundInk = 0.4;

  static final _shapes = [
    _outline((_) => 1),
    _outline((angle) => 1 + 0.055 * math.cos(12 * angle)),
    _outline((angle) {
      final c = math.pow(math.cos(angle).abs(), 4.5);
      final s = math.pow(math.sin(angle).abs(), 4.5);
      return 0.92 / math.pow(c + s, 1 / 4.5);
    }),
  ];

  static Path _outline(double Function(double) radius) {
    const points = 96;
    final path = Path();
    for (var i = 0; i < points; i++) {
      final angle = i / points * 2 * math.pi;
      final point = Offset.fromDirection(angle, radius(angle));
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    return path..close();
  }

  final Animation<double> progress;
  final Animation<double> rise;
  final Animation<double>? presence;
  final Color color;
  final bool still;

  double _height(double phase) {
    if (phase >= _hopShare * 2) {
      return 0;
    }
    return phase < _hopShare
        ? _hopCurve.transform(phase / _hopShare)
        : 1 - _hopCurve.transform(phase / _hopShare - 1);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final k = math.min(rise.value, presence?.value ?? 1);
    if (size.shortestSide <= 0 || k <= 0) {
      return;
    }
    final fade = math.min(k * 3, 1.0);
    final t = progress.value;
    final solid = Paint();
    final ground = Paint()
      ..color = color.withValues(alpha: color.a * _groundInk * fade);
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    final scale = size.shortestSide / _canvas * k;
    canvas.scale(scale);
    for (var i = 0; i < _shapes.length; i++) {
      final x = (i - 1) * _spacing;
      final phase = (t - i * _stagger) % 1;
      canvas.drawRSuperellipse(
        RSuperellipse.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(x, _groundY),
            width: _groundSize.width,
            height: _groundSize.height,
          ),
          Radius.circular(_groundSize.height / 2),
        ),
        ground,
      );
      final breath = 0.5 - 0.5 * math.cos(phase * 2 * math.pi);
      solid.color = color.withValues(
        alpha: color.a * fade * (still ? 0.4 + 0.6 * breath : 1),
      );
      canvas.save();
      canvas.translate(x, _shapeY - (still ? 0 : _height(phase) * _hop));
      canvas.scale(_shapeRadius);
      canvas.drawPath(_shapes[i], solid);
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_RelayPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.rise != rise ||
        oldDelegate.presence != presence ||
        oldDelegate.color != color ||
        oldDelegate.still != still;
  }
}

/// The bar under a page's app bar while it works: two solid segments running
/// over a faint track, growing out of the bar's edge on [active] and drawn back
/// in when done.
class LoadingBar extends StatefulWidget {
  const LoadingBar({super.key, required this.active});

  /// How far the bar reaches below the app bar, painted over the page rather
  /// than laid out, so the page does not move when it comes and goes.
  static const extent = 3.0;

  final bool active;

  @override
  State<LoadingBar> createState() => _LoadingBarState();
}

class _LoadingBarState extends State<LoadingBar> with TickerProviderStateMixin {
  late final AnimationController _presence = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
    reverseDuration: const Duration(milliseconds: 200),
    value: widget.active ? 1 : 0,
  )..addStatusListener(_handlePresence);
  late final _height = CurvedAnimation(
    parent: _presence,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInOut,
  );
  late final AnimationController _loop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) {
      _loop.repeat();
    }
  }

  @override
  void didUpdateWidget(LoadingBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active == oldWidget.active) {
      return;
    }
    if (widget.active) {
      _loop.repeat();
      _presence.forward();
    } else {
      _presence.reverse();
    }
  }

  void _handlePresence(AnimationStatus status) {
    if (status.isDismissed) {
      _loop.stop();
      setState(() {});
    }
  }

  @override
  void dispose() {
    _height.dispose();
    _presence.dispose();
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active && _presence.isDismissed) {
      return const SizedBox.shrink();
    }
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          size: const Size(double.infinity, LoadingBar.extent),
          painter: _LoadingBarPainter(
            height: _height,
            loop: _loop,
            color: context.colorScheme.primary,
            still: context.disableAnimations,
          ),
        ),
      ),
    );
  }
}

class _LoadingBarPainter extends CustomPainter {
  _LoadingBarPainter({
    required this.height,
    required this.loop,
    required this.color,
    required this.still,
  }) : super(repaint: Listenable.merge([height, loop]));

  static const _leadEnd = 0.6;
  static const _trailStart = 0.45;
  static const _leadCurve = Cubic(0.65, 0.8, 0.35, 0.95);
  static const _trailCurve = Cubic(0.15, 0.55, 0.5, 1);

  final Animation<double> height;
  final Animation<double> loop;
  final Color color;
  final bool still;

  @override
  void paint(Canvas canvas, Size size) {
    final rise = height.value;
    if (rise <= 0 || size.width <= 0) {
      return;
    }
    final fade = math.min(rise * 4, 1.0);
    final barHeight = size.height * rise;
    final paint = Paint()
      ..color = color.withValues(alpha: color.a * _trackInk * fade);
    canvas.drawRect(Offset.zero & Size(size.width, barHeight), paint);
    final t = loop.value;
    if (still) {
      final breath = 0.5 - 0.5 * math.cos(t * 2 * math.pi);
      paint.color = color.withValues(
        alpha: color.a * fade * (0.3 + 0.5 * breath),
      );
      canvas.drawRect(Offset.zero & Size(size.width, barHeight), paint);
      return;
    }
    paint.color = color.withValues(alpha: color.a * fade);
    final lead = _leadCurve.transform(ui.clampDouble(t / _leadEnd, 0, 1));
    _paintSegment(
      canvas,
      paint,
      size.width,
      barHeight,
      ui.lerpDouble(-0.35, 1, lead)!,
      ui.lerpDouble(0, 1.9, lead)!,
    );
    final trail = _trailCurve.transform(
      ui.clampDouble((t - _trailStart) / (1 - _trailStart), 0, 1),
    );
    _paintSegment(
      canvas,
      paint,
      size.width,
      barHeight,
      ui.lerpDouble(-2, 1.07, trail)!,
      ui.lerpDouble(0, 1.08, trail)!,
    );
  }

  void _paintSegment(
    Canvas canvas,
    Paint paint,
    double width,
    double height,
    double start,
    double end,
  ) {
    final left = ui.clampDouble(start, 0, 1) * width;
    final right = ui.clampDouble(end, 0, 1) * width;
    if (right <= left) {
      return;
    }
    canvas.drawRSuperellipse(
      RSuperellipse.fromRectAndRadius(
        Rect.fromLTRB(left, 0, right, height),
        Radius.circular(height / 2),
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(_LoadingBarPainter oldDelegate) {
    return oldDelegate.height != height ||
        oldDelegate.loop != loop ||
        oldDelegate.color != color ||
        oldDelegate.still != still;
  }
}
