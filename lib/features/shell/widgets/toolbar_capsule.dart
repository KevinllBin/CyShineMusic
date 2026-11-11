import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/app_motion.dart';
import '../../player/player_controller.dart';
import '../player_transition.dart';
import 'toolbar_metrics.dart';

/// Shared appearance for the original toolbar and the independent mini player.
class ToolbarCapsule extends StatelessWidget {
  const ToolbarCapsule({
    super.key,
    required this.scheme,
    required this.height,
    required this.child,
  });

  final ColorScheme scheme;
  final double height;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final transition = PlayerTransitionScope.maybeOf(context);
    final surface = _ToolbarProgressBorder(
      color: scheme.primary.withValues(
        alpha: scheme.brightness == Brightness.light ? 0.72 : 0.86,
      ),
      child: RepaintBoundary(
        child: AnimatedContainer(
          duration: AppMotion.long,
          curve: AppMotion.emphasized,
          height: height,
          decoration: BoxDecoration(
            color: toolbarCapsuleColor(scheme),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.52),
            ),
            boxShadow: [
              BoxShadow(
                color: scheme.shadow.withValues(
                  alpha: scheme.brightness == Brightness.light ? 0.08 : 0.18,
                ),
                blurRadius: 28,
                offset: const Offset(0, 10),
              ),
            ],
          ),
        ),
      ),
    );
    Widget layers(double p) => Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: Opacity(
            opacity: 1 - PlayerMotion.interval(p, 0, 0.12),
            child: surface,
          ),
        ),
        Transform.translate(
          offset: Offset(0, -p * (transition?.travel ?? 0)),
          child: Opacity(
            opacity: 1 - PlayerMotion.interval(p, 0, 0.20),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: child,
            ),
          ),
        ),
      ],
    );
    return RepaintBoundary(
      key: transition?.surfaceKey,
      child: SizedBox(
        height: height,
        child: transition == null
            ? layers(0)
            : AnimatedBuilder(
                animation: transition,
                builder: (context, _) => layers(transition.progress.value),
              ),
      ),
    );
  }
}

Color toolbarCapsuleColor(ColorScheme scheme) => Color.alphaBlend(
  scheme.primary.withValues(
    alpha: scheme.brightness == Brightness.light ? 0.025 : 0.04,
  ),
  scheme.surfaceContainerHigh.withValues(alpha: 0.90),
);

/// Position updates rebuild only the border, retaining the capsule subtree.
class _ToolbarProgressBorder extends ConsumerWidget {
  const _ToolbarProgressBorder({required this.color, required this.child});

  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playbackProgress = ref.watch(
      playerControllerProvider.select((state) {
        final durationMs = state.duration.inMilliseconds;
        if (!state.hasTrack || durationMs <= 0) return 0.0;
        return (state.position.inMilliseconds / durationMs)
            .clamp(0.0, 1.0)
            .toDouble();
      }),
    );
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: playbackProgress),
      duration: AppMotion.short,
      curve: AppMotion.emphasized,
      child: child,
      builder: (context, progress, child) => CustomPaint(
        foregroundPainter: _ToolbarProgressBorderPainter(
          progress: progress,
          color: color,
        ),
        child: child,
      ),
    );
  }
}

class _ToolbarProgressBorderPainter extends CustomPainter {
  const _ToolbarProgressBorderPainter({
    required this.progress,
    required this.color,
  });

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final clamped = progress.clamp(0.0, 1.0).toDouble();
    if (clamped <= 0 || size.isEmpty) return;

    final inset = toolbarProgressStrokeWidth / 2;
    final rect =
        Offset(inset, inset) &
        Size(
          size.width - toolbarProgressStrokeWidth,
          size.height - toolbarProgressStrokeWidth,
        );
    final radius = Radius.circular(rect.height / 2);
    final path = Path()
      ..moveTo(rect.left + rect.height / 2, rect.top)
      ..lineTo(rect.right - rect.height / 2, rect.top)
      ..arcToPoint(
        Offset(rect.right - rect.height / 2, rect.bottom),
        radius: radius,
      )
      ..lineTo(rect.left + rect.height / 2, rect.bottom)
      ..arcToPoint(
        Offset(rect.left + rect.height / 2, rect.top),
        radius: radius,
      )
      ..close();
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = toolbarProgressStrokeWidth
      ..strokeCap = StrokeCap.round
      ..color = color;
    for (final metric in path.computeMetrics()) {
      canvas.drawPath(metric.extractPath(0, metric.length * clamped), paint);
      break;
    }
  }

  @override
  bool shouldRepaint(covariant _ToolbarProgressBorderPainter oldDelegate) =>
      progress != oldDelegate.progress || color != oldDelegate.color;
}
