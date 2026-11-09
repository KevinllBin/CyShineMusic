import 'package:flutter/material.dart';
import 'package:prism_ui/prism_ui.dart' as prism;

import '../../../theme/app_motion.dart';

/// Shared surface for discovery's elevated interactive content. Keeping the
/// glass treatment in one place makes cards and filters feel like one Prism
/// scene and still gives the app a clean outlined surface when glass is off.
///
/// Discovery surfaces sit on the plain page background, where live glass has
/// nothing to bend: each pane would still re-capture and blur its backdrop on
/// every scrolled frame. They therefore paint the glass look statically — the
/// pane's tint plus its rim — and leave live glass to controls that float
/// over moving content.
class DiscoveryPrismSurface extends StatelessWidget {
  const DiscoveryPrismSurface({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(18)),
    this.padding,
    this.tint,
    this.shadows = const <BoxShadow>[],
  });

  final Widget child;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry? padding;
  final Color? tint;
  final List<BoxShadow> shadows;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final content = padding == null
        ? child
        : Padding(padding: padding!, child: child);
    if (!prism.LiquidGlassScope.of(context)) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: tint ?? scheme.surfaceContainer,
          borderRadius: borderRadius,
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.28),
          ),
          boxShadow: shadows,
        ),
        child: content,
      );
    }

    final glass = prism.LiquidGlassStyle.regular(
      prism.Theme.of(context).colorScheme,
    );
    final dark = scheme.brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: glass.tint,
        borderRadius: borderRadius,
        boxShadow: shadows,
      ),
      position: DecorationPosition.background,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: (tint ?? scheme.surfaceContainer).withValues(alpha: 0.18),
          borderRadius: borderRadius,
          border: Border.all(color: scheme.outline.withValues(alpha: 0.14)),
        ),
        child: CustomPaint(
          foregroundPainter: _GlassRimPainter(
            borderRadius: borderRadius,
            light: Colors.white.withValues(alpha: dark ? 0.16 : 0.62),
          ),
          child: content,
        ),
      ),
    );
  }
}

/// The glass rim, lit from the top left and catching a little light again at
/// the bottom right.
class _GlassRimPainter extends CustomPainter {
  const _GlassRimPainter({required this.borderRadius, required this.light});

  final BorderRadius borderRadius;
  final Color light;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        stops: const [0, 0.38, 0.72, 1],
        colors: [
          light,
          light.withValues(alpha: 0),
          light.withValues(alpha: 0),
          light.withValues(alpha: light.a * 0.45),
        ],
      ).createShader(rect);
    canvas.drawRRect(borderRadius.toRRect(rect.deflate(0.6)), paint);
  }

  @override
  bool shouldRepaint(_GlassRimPainter oldDelegate) =>
      oldDelegate.borderRadius != borderRadius || oldDelegate.light != light;
}

/// Small entrance motion used by discovery sections and cards.
class DiscoveryReveal extends StatelessWidget {
  const DiscoveryReveal({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.enabled = true,
  });

  final Widget child;
  final Duration delay;

  /// false 时直接出现。只在首次构建时生效：动画途中改为 false 会照常播完。
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: enabled ? 0 : 1, end: 1),
      duration: AppMotion.medium + delay,
      curve: AppMotion.emphasizedDecelerate,
      child: child,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 12 * (1 - value)),
          child: child,
        ),
      ),
    );
  }
}
