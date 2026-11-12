import 'dart:math' as math;

import 'package:flutter/material.dart';

enum EmptyStateKind {
  library,
  playlist,
  search,
  downloads,
  history,
  cloud,
  logs,
}

/// Small line glyphs on the page itself, with no enclosing surface.
class AnimatedEmptyState extends StatefulWidget {
  const AnimatedEmptyState({
    super.key,
    required this.kind,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.bottomPadding = 0,
    this.compact = false,
  });

  final EmptyStateKind kind;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final double bottomPadding;
  final bool compact;

  @override
  State<AnimatedEmptyState> createState() => _AnimatedEmptyStateState();
}

class _AnimatedEmptyStateState extends State<AnimatedEmptyState>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool? _reduceMotion;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (reduceMotion == _reduceMotion) return;
    _reduceMotion = reduceMotion;
    if (reduceMotion) {
      _controller.stop();
      _controller.value = 0;
    } else {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final glyphSize = widget.compact ? 36.0 : 44.0;
    final content = Padding(
      padding: EdgeInsets.fromLTRB(
        28,
        widget.compact ? 20 : 24,
        28,
        widget.bottomPadding + (widget.compact ? 20 : 0),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 280),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RepaintBoundary(
              child: CustomPaint(
                size: Size.square(glyphSize),
                painter: _EmptyStatePainter(
                  kind: widget.kind,
                  animation: _controller,
                  ink: scheme.onSurfaceVariant,
                  accent: scheme.onSurfaceVariant.withValues(alpha: 0.56),
                ),
              ),
            ),
            SizedBox(height: widget.compact ? 12 : 16),
            Text(
              widget.title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: scheme.onSurface.withValues(alpha: 0.86),
                fontSize: widget.compact ? 13 : 14,
                fontWeight: FontWeight.w500,
                height: 1.5,
                letterSpacing: 0.2,
              ),
            ),
            if (widget.message.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                widget.message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  height: 1.65,
                ),
              ),
            ],
            if (widget.actionLabel != null && widget.onAction != null) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: widget.onAction,
                style: TextButton.styleFrom(
                  foregroundColor: scheme.primary,
                  backgroundColor: Colors.transparent,
                  side: BorderSide.none,
                  minimumSize: const Size(64, 48),
                  textStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                child: Text(widget.actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );

    return Semantics(
      container: true,
      liveRegion: true,
      child: Center(
        // Allow long error messages and short viewports without clipping.
        child: SingleChildScrollView(
          primary: false,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: _reduceMotion == true
                ? Duration.zero
                : const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
            builder: (context, value, child) => Opacity(
              opacity: value,
              child: Transform.translate(
                offset: Offset(0, (1 - value) * 4),
                child: child,
              ),
            ),
            child: content,
          ),
        ),
      ),
    );
  }
}

/// Only the glyph repaints during the loop; text and layout stay still.
class _EmptyStatePainter extends CustomPainter {
  _EmptyStatePainter({
    required this.kind,
    required this.animation,
    required this.ink,
    required this.accent,
  }) : super(repaint: animation);

  final EmptyStateKind kind;
  final Animation<double> animation;
  final Color ink;
  final Color accent;

  Paint _stroke(Color color, {double width = 4.2}) => Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    // Approved empty-state glyphs use the preview's 64-unit grid.
    final designSize = switch (kind) {
      EmptyStateKind.library ||
      EmptyStateKind.playlist ||
      EmptyStateKind.search ||
      EmptyStateKind.downloads ||
      EmptyStateKind.history => 64.0,
      _ => 48.0,
    };
    canvas.scale(size.width / designSize, size.height / designSize);
    final line = _stroke(ink, width: designSize == 64 ? 4.2 : 2.7);
    final detail = _stroke(accent, width: 2.7);
    // A closed cosine cycle has zero velocity at both ends: no loop seam.
    final breath = (1 - math.cos(animation.value * math.pi * 2)) / 2;
    switch (kind) {
      case EmptyStateKind.library:
        _library(canvas, line, breath);
      case EmptyStateKind.playlist:
        _playlist(canvas, line, breath);
      case EmptyStateKind.search:
        _search(canvas, line, breath);
      case EmptyStateKind.downloads:
        _downloads(canvas, line, breath);
      case EmptyStateKind.history:
        _history(canvas, line, breath);
      case EmptyStateKind.cloud:
        _cloud(canvas, line, detail, breath);
      case EmptyStateKind.logs:
        _logs(canvas, line, detail, breath);
    }
    canvas.restore();
  }

  void _library(Canvas canvas, Paint line, double breath) {
    canvas.drawPath(
      Path()
        ..moveTo(33, 53)
        ..lineTo(14, 53)
        ..quadraticBezierTo(8, 53, 8, 47)
        ..lineTo(8, 17)
        ..quadraticBezierTo(8, 12, 13, 12)
        ..lineTo(23, 12)
        ..lineTo(29, 18)
        ..lineTo(49, 18)
        ..quadraticBezierTo(54, 18, 54, 23)
        ..lineTo(54, 29),
      line,
    );
    _zero(canvas, breath);
  }

  void _playlist(Canvas canvas, Paint line, double breath) {
    canvas.drawPath(
      Path()
        ..moveTo(33, 54)
        ..lineTo(15, 54)
        ..quadraticBezierTo(10, 54, 10, 49)
        ..lineTo(10, 15)
        ..quadraticBezierTo(10, 10, 15, 10)
        ..lineTo(43, 10)
        ..quadraticBezierTo(48, 10, 48, 15)
        ..lineTo(48, 28),
      line,
    );
    final placeholder = _stroke(accent, width: 3.2);
    for (final (y, end) in [(22.0, 37.0), (32.0, 32.0), (42.0, 29.0)]) {
      for (var x = 20.0; x < end; x += 8) {
        canvas.drawLine(
          Offset(x, y),
          Offset(math.min(x + 2.5, end), y),
          placeholder,
        );
      }
    }
    _zero(canvas, breath);
  }

  void _search(Canvas canvas, Paint line, double breath) {
    canvas.drawCircle(const Offset(26, 26), 17, line);
    canvas.drawLine(
      const Offset(39, 39),
      const Offset(53, 53),
      _stroke(ink, width: 5.6),
    );
    canvas.drawPath(
      Path()
        ..moveTo(21, 21)
        ..lineTo(31, 31)
        ..moveTo(31, 21)
        ..lineTo(21, 31),
      _stroke(ink.withValues(alpha: 1 - breath * 0.13), width: 3.8),
    );
  }

  void _downloads(Canvas canvas, Paint line, double breath) {
    canvas.drawPath(
      Path()
        ..moveTo(10, 33)
        ..lineTo(17, 22)
        ..lineTo(45, 22)
        ..lineTo(52, 33),
      _stroke(accent, width: 3.6),
    );
    canvas.drawPath(
      Path()
        ..moveTo(10, 33)
        ..lineTo(22, 33)
        ..lineTo(26, 39)
        ..lineTo(36, 39)
        ..lineTo(40, 33)
        ..lineTo(52, 33)
        ..lineTo(52, 47)
        ..quadraticBezierTo(52, 53, 46, 53)
        ..lineTo(16, 53)
        ..quadraticBezierTo(10, 53, 10, 47)
        ..close(),
      line,
    );
    canvas.save();
    canvas.translate(0, -breath * 1.2);
    canvas.drawPath(
      Path()
        ..moveTo(31, 9)
        ..lineTo(31, 13)
        ..moveTo(18, 12)
        ..lineTo(20, 15)
        ..moveTo(44, 12)
        ..lineTo(42, 15),
      _stroke(accent, width: 3.1),
    );
    canvas.restore();
  }

  void _zero(Canvas canvas, double breath) {
    canvas.drawPath(
      Path()
        ..moveTo(47, 36)
        ..cubicTo(40, 36, 40, 42, 40, 47)
        ..cubicTo(40, 52, 40, 58, 47, 58)
        ..cubicTo(54, 58, 54, 52, 54, 47)
        ..cubicTo(54, 42, 54, 36, 47, 36)
        ..close(),
      _stroke(ink.withValues(alpha: 1 - breath * 0.13), width: 4.5),
    );
  }

  void _history(Canvas canvas, Paint line, double breath) {
    canvas.drawPath(
      Path()
        ..moveTo(29, 52)
        ..cubicTo(17.4, 52, 8, 42.6, 8, 31)
        ..cubicTo(8, 19.4, 17.4, 10, 29, 10)
        ..cubicTo(40.6, 10, 50, 19.4, 50, 31),
      line,
    );
    canvas.drawPath(
      Path()
        ..moveTo(29, 20)
        ..lineTo(29, 31)
        ..lineTo(35, 35),
      _stroke(accent, width: 3.8),
    );
    canvas.drawPath(
      Path()
        ..moveTo(48, 37)
        ..cubicTo(41.5, 37, 41.5, 43, 41.5, 48)
        ..cubicTo(41.5, 53, 41.5, 58.5, 48, 58.5)
        ..cubicTo(54.5, 58.5, 54.5, 53, 54.5, 48)
        ..cubicTo(54.5, 43, 54.5, 37, 48, 37)
        ..close(),
      _stroke(ink.withValues(alpha: 1 - breath * 0.13), width: 4.5),
    );
  }

  void _cloud(Canvas canvas, Paint line, Paint detail, double breath) {
    canvas.drawPath(
      Path()
        ..moveTo(16, 32)
        ..lineTo(13, 32)
        ..cubicTo(3, 32, 3, 18, 13, 18)
        ..cubicTo(15, 6, 32, 6, 35, 19)
        ..cubicTo(45, 18, 46, 32, 36, 32)
        ..lineTo(32, 32),
      line,
    );
    canvas.drawLine(Offset(22 - breath, 32), Offset(26 + breath, 32), detail);
  }

  void _logs(Canvas canvas, Paint line, Paint detail, double breath) {
    canvas.drawPath(
      Path()
        ..moveTo(10, 16)
        ..lineTo(17, 23)
        ..lineTo(10, 30),
      line,
    );
    canvas.drawLine(const Offset(25, 16), const Offset(38, 16), line);
    canvas.drawLine(const Offset(25, 23), const Offset(34, 23), line);
    canvas.drawLine(const Offset(25, 32), Offset(32 + breath * 2, 32), detail);
  }

  @override
  bool shouldRepaint(covariant _EmptyStatePainter oldDelegate) =>
      oldDelegate.kind != kind ||
      oldDelegate.animation != animation ||
      oldDelegate.ink != ink ||
      oldDelegate.accent != accent;
}
