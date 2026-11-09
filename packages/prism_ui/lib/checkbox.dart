import 'package:flutter/widgets.dart';
import 'package:prism_ui/context.dart';
import 'package:prism_ui/press_region.dart';
import 'package:prism_ui/shape.dart';

class Checkbox extends StatelessWidget {
  const Checkbox({
    super.key,
    required this.value,
    required this.onChanged,
    this.isCircle = false,
  });

  final bool? value;
  final ValueChanged<bool?>? onChanged;
  final bool isCircle;

  static const _target = 48.0;
  static const _box = 18.0;
  static const _pressRadius = _target / 2 - 4;
  static const _duration = Duration(milliseconds: 150);

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final onChanged = this.onChanged;
    final enabled = onChanged != null;
    final checked = value ?? true;
    final shape = isCircle ? AppShape.circle : AppShape.all(2);
    final active = enabled
        ? colorScheme.primary
        : colorScheme.onSurface.withValues(alpha: 0.38);
    final idle = enabled
        ? colorScheme.onSurfaceVariant
        : colorScheme.onSurface.withValues(alpha: 0.38);
    return Semantics(
      checked: value == true,
      mixed: value == null,
      enabled: enabled,
      child: SizedBox.square(
        dimension: _target,
        child: Center(
          child: SizedBox.square(
            dimension: _pressRadius * 2,
            child: PressRegion(
              onTap: enabled ? () => onChanged(value != true) : null,
              shape: AppShape.circle,
              excludeFromSemantics: true,
              child: Center(
                child: TweenAnimationBuilder<double>(
                  tween: Tween(end: checked ? 1 : 0),
                  duration: context.motionDuration(_duration),
                  curve: Curves.easeOut,
                  builder: (context, t, _) => CustomPaint(
                    size: const Size.square(_box),
                    painter: _CheckPainter(
                      progress: t,
                      shape: shape,
                      active: active,
                      idle: idle,
                      mark: enabled
                          ? colorScheme.onPrimary
                          : colorScheme.surface,
                      dash: value == null,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CheckPainter extends CustomPainter {
  const _CheckPainter({
    required this.progress,
    required this.shape,
    required this.active,
    required this.idle,
    required this.mark,
    required this.dash,
  });

  final double progress;
  final ShapeBorder shape;
  final Color active;
  final Color idle;
  final Color mark;
  final bool dash;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    if (progress < 1) {
      canvas.drawPath(
        shape.getOuterPath(rect.deflate(1)),
        Paint()
          ..color = idle.withValues(alpha: idle.a * (1 - progress))
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
    if (progress == 0) {
      return;
    }
    shape.paintInterior(
      canvas,
      rect,
      Paint()..color = active.withValues(alpha: active.a * progress),
    );
    final s = size.width;
    final path = dash
        ? (Path()
            ..moveTo(s * 0.25, s * 0.5)
            ..lineTo(s * 0.75, s * 0.5))
        : (Path()
            ..moveTo(s * 0.22, s * 0.52)
            ..lineTo(s * 0.42, s * 0.72)
            ..lineTo(s * 0.78, s * 0.3));
    final metric = path.computeMetrics().first;
    canvas.drawPath(
      metric.extractPath(0, metric.length * progress),
      Paint()
        ..color = mark
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.square,
    );
  }

  @override
  bool shouldRepaint(_CheckPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.shape != shape ||
      oldDelegate.active != active ||
      oldDelegate.idle != idle ||
      oldDelegate.mark != mark ||
      oldDelegate.dash != dash;
}
