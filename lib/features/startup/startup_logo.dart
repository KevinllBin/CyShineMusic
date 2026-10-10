import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_motion.dart';

class StartupLogo extends StatefulWidget {
  const StartupLogo({super.key, this.size = 112});

  final double size;

  @override
  State<StartupLogo> createState() => _StartupLogoState();
}

class _StartupLogoState extends State<StartupLogo>
    with TickerProviderStateMixin {
  late final AnimationController _entry = AnimationController(
    duration: const Duration(milliseconds: 1200),
    vsync: this,
  );
  late final AnimationController _glow = AnimationController(
    duration: const Duration(milliseconds: 2400),
    vsync: this,
  );

  @override
  void initState() {
    super.initState();
    _entry
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _glow.repeat(reverse: true);
        }
      })
      ..forward();
  }

  @override
  void dispose() {
    _entry.dispose();
    _glow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AnimatedBuilder(
      animation: Listenable.merge([_entry, _glow]),
      builder: (context, child) {
        final draw = _segment(_entry.value, 0.0, 0.65);
        final reveal = _segment(_entry.value, 0.68, 0.96, Curves.easeOutCubic);
        final strokeFade =
            1 - _segment(_entry.value, 0.78, 0.98, Curves.easeOutCubic);
        final breathe = Curves.easeInOutSine.transform(_glow.value);
        final glowAlpha = reveal * (0.08 + 0.05 * breathe);
        final glowBlur = 22.0 + 10.0 * breathe;

        return Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(widget.size * 0.24),
            boxShadow: [
              BoxShadow(
                color: scheme.shadow.withValues(
                  alpha: scheme.brightness == Brightness.light ? 0.16 : 0.34,
                ),
                blurRadius: 22,
                offset: const Offset(0, 12),
              ),
              BoxShadow(
                color: scheme.primary.withValues(alpha: glowAlpha),
                blurRadius: glowBlur,
                spreadRadius: 1,
              ),
              BoxShadow(
                color: scheme.tertiary.withValues(alpha: glowAlpha * 0.7),
                blurRadius: glowBlur * 0.8,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (strokeFade > 0)
                CustomPaint(
                  painter: _LogoStrokePainter(
                    progress: draw,
                    fade: strokeFade,
                    color: const Color(0xFF5B6EDB),
                  ),
                ),
              Opacity(opacity: reveal, child: child),
            ],
          ),
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.size * 0.23),
        child: Image.asset('logo_fg.png', fit: BoxFit.contain),
      ),
    );
  }
}

class _LogoStrokePainter extends CustomPainter {
  const _LogoStrokePainter({
    required this.progress,
    required this.fade,
    required this.color,
  });

  final double progress;
  final double fade;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || fade <= 0) return;

    final frame = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(1.5),
          Radius.circular(size.shortestSide * 0.23),
        ),
      );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = math.max(1.5, size.shortestSide * 0.014)
      ..color = color.withValues(alpha: fade);

    _drawPath(
      canvas,
      frame,
      _segment(progress, 0.0, 0.72, AppMotion.emphasizedDecelerate),
      paint..strokeWidth = math.max(1.5, size.shortestSide * 0.018),
    );
    final waves = _wavePaths(size);
    for (var i = 0; i < waves.length; i++) {
      _drawPath(
        canvas,
        waves[i],
        _segment(progress, 0.02 + i * 0.12, 0.74 + i * 0.08),
        paint..strokeWidth = math.max(1.4, size.shortestSide * 0.014),
      );
    }
    _drawPath(
      canvas,
      _sparklePath(size),
      _segment(progress, 0.42, 1.0, AppMotion.emphasizedDecelerate),
      paint..strokeWidth = math.max(1.4, size.shortestSide * 0.014),
    );
  }

  List<Path> _wavePaths(Size size) {
    // Trace the closed outlines, including the rounded ends, before the fill.
    return [
      Path()
        ..moveToPoint(_assetPoint(size, 374, 250))
        ..cubicToPoints(
          _assetPoint(size, 386, 249),
          _assetPoint(size, 393, 257),
          _assetPoint(size, 395, 271),
        )
        ..cubicToPoints(
          _assetPoint(size, 412, 371),
          _assetPoint(size, 442, 548),
          _assetPoint(size, 481, 749),
        )
        ..cubicToPoints(
          _assetPoint(size, 483, 761),
          _assetPoint(size, 475, 771),
          _assetPoint(size, 462, 774),
        )
        ..cubicToPoints(
          _assetPoint(size, 449, 776),
          _assetPoint(size, 440, 769),
          _assetPoint(size, 438, 756),
        )
        ..cubicToPoints(
          _assetPoint(size, 397, 537),
          _assetPoint(size, 371, 377),
          _assetPoint(size, 351, 278),
        )
        ..cubicToPoints(
          _assetPoint(size, 348, 264),
          _assetPoint(size, 357, 252),
          _assetPoint(size, 374, 250),
        )
        ..close(),
      Path()
        ..moveToPoint(_assetPoint(size, 486, 286))
        ..cubicToPoints(
          _assetPoint(size, 499, 286),
          _assetPoint(size, 505, 295),
          _assetPoint(size, 506, 305),
        )
        ..cubicToPoints(
          _assetPoint(size, 507, 448),
          _assetPoint(size, 555, 494),
          _assetPoint(size, 574, 646),
        )
        ..cubicToPoints(
          _assetPoint(size, 576, 666),
          _assetPoint(size, 579, 685),
          _assetPoint(size, 581, 703),
        )
        ..cubicToPoints(
          _assetPoint(size, 582, 716),
          _assetPoint(size, 575, 723),
          _assetPoint(size, 562, 725),
        )
        ..cubicToPoints(
          _assetPoint(size, 549, 726),
          _assetPoint(size, 539, 718),
          _assetPoint(size, 538, 707),
        )
        ..cubicToPoints(
          _assetPoint(size, 536, 620),
          _assetPoint(size, 509, 555),
          _assetPoint(size, 491, 477),
        )
        ..cubicToPoints(
          _assetPoint(size, 474, 422),
          _assetPoint(size, 468, 366),
          _assetPoint(size, 466, 308),
        )
        ..cubicToPoints(
          _assetPoint(size, 465, 295),
          _assetPoint(size, 475, 286),
          _assetPoint(size, 486, 286),
        )
        ..close(),
      Path()
        ..moveToPoint(_assetPoint(size, 592, 359))
        ..cubicToPoints(
          _assetPoint(size, 604, 359),
          _assetPoint(size, 612, 368),
          _assetPoint(size, 613, 381),
        )
        ..cubicToPoints(
          _assetPoint(size, 615, 457),
          _assetPoint(size, 648, 500),
          _assetPoint(size, 667, 585),
        )
        ..cubicToPoints(
          _assetPoint(size, 671, 601),
          _assetPoint(size, 673, 615),
          _assetPoint(size, 673, 626),
        )
        ..cubicToPoints(
          _assetPoint(size, 673, 637),
          _assetPoint(size, 664, 643),
          _assetPoint(size, 653, 645),
        )
        ..cubicToPoints(
          _assetPoint(size, 640, 645),
          _assetPoint(size, 631, 637),
          _assetPoint(size, 630, 626),
        )
        ..cubicToPoints(
          _assetPoint(size, 627, 575),
          _assetPoint(size, 576, 480),
          _assetPoint(size, 572, 405),
        )
        ..cubicToPoints(
          _assetPoint(size, 570, 395),
          _assetPoint(size, 571, 386),
          _assetPoint(size, 571, 380),
        )
        ..cubicToPoints(
          _assetPoint(size, 571, 368),
          _assetPoint(size, 580, 359),
          _assetPoint(size, 592, 359),
        )
        ..close(),
    ];
  }

  Path _sparklePath(Size size) {
    return Path()
      ..moveToPoint(_assetPoint(size, 635, 265))
      ..cubicToPoints(
        _assetPoint(size, 640, 288),
        _assetPoint(size, 647, 295),
        _assetPoint(size, 668, 299),
      )
      ..cubicToPoints(
        _assetPoint(size, 647, 304),
        _assetPoint(size, 640, 311),
        _assetPoint(size, 635, 333),
      )
      ..cubicToPoints(
        _assetPoint(size, 630, 311),
        _assetPoint(size, 623, 304),
        _assetPoint(size, 601, 299),
      )
      ..cubicToPoints(
        _assetPoint(size, 623, 295),
        _assetPoint(size, 630, 288),
        _assetPoint(size, 635, 265),
      )
      ..close();
  }

  Offset _assetPoint(Size size, double x, double y) {
    return Offset(size.width * x / 1024, size.height * y / 1024);
  }

  void _drawPath(Canvas canvas, Path path, double progress, Paint paint) {
    if (progress <= 0) return;
    for (final metric in path.computeMetrics()) {
      canvas.drawPath(
        metric.extractPath(0, metric.length * progress.clamp(0.0, 1.0)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _LogoStrokePainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.fade != fade ||
        oldDelegate.color != color;
  }
}

extension on Path {
  void moveToPoint(Offset point) => moveTo(point.dx, point.dy);

  void cubicToPoints(Offset control1, Offset control2, Offset end) {
    cubicTo(control1.dx, control1.dy, control2.dx, control2.dy, end.dx, end.dy);
  }
}

double _segment(
  double t,
  double start,
  double end, [
  Curve curve = Curves.easeInOutCubic,
]) {
  return curve.transform(((t - start) / (end - start)).clamp(0.0, 1.0));
}
