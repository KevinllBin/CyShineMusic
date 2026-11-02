import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'morphing_menu_motion.dart';

/// A moving Material surface, with independently animated center and size.
class MorphingMenuSurface extends StatelessWidget {
  const MorphingMenuSurface({
    super.key,
    required this.anchorRect,
    required this.animation,
    required this.motion,
    required this.motionStyle,
    required this.preferredWidth,
    required this.sourceIcon,
    required this.itemHeight,
    required this.children,
  });

  final Rect Function() anchorRect;
  final Animation<double> animation;
  final MorphingMenuFrame Function() motion;
  final MorphingMenuMotionStyle motionStyle;
  final double preferredWidth;
  final IconData sourceIcon;
  final double itemHeight;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final media = MediaQuery.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        // Read after the underlying route has laid out, including on rotation.
        final anchor = anchorRect();
        final safe = Rect.fromLTRB(
          media.viewPadding.left + 12,
          media.viewPadding.top + 8,
          constraints.maxWidth - media.viewPadding.right - 12,
          constraints.maxHeight -
              math.max(media.viewPadding.bottom, media.viewInsets.bottom) -
              12,
        );
        final width = math.min(preferredWidth, math.max(0.0, safe.width));
        final height = math.min(
          children.length * itemHeight + 16,
          math.max(0.0, safe.height),
        );
        if (width <= 0 || height <= 0) return const SizedBox.shrink();

        final alignRight = anchor.center.dx >= safe.center.dx;
        final opensDown =
            anchor.top + height <= safe.bottom ||
            anchor.center.dy <= safe.center.dy;
        final isRtl = Directionality.of(context) == TextDirection.rtl;
        final listLeft = isRtl ? anchor.left + 16 : anchor.right - width - 16;
        final left =
            (motionStyle == MorphingMenuMotionStyle.toolbar
                    ? (alignRight ? anchor.right - width : anchor.left)
                    : listLeft)
                .clamp(safe.left, safe.right - width)
                .toDouble();
        final toolbarTop = opensDown ? anchor.top : anchor.bottom - height;
        final listTop = anchor.center.dy - 16;
        final listBottom = listTop + height;
        final listTopIfNeeded = listBottom <= safe.bottom
            ? listTop
            : anchor.center.dy + 16 - height;
        final top =
            (motionStyle == MorphingMenuMotionStyle.toolbar
                    ? toolbarTop
                    : listTopIfNeeded)
                .clamp(safe.top, safe.bottom - height)
                .toDouble();
        final target = Rect.fromLTWH(left, top, width, height);
        final isToolbar = motionStyle == MorphingMenuMotionStyle.toolbar;
        // The Weather source is a horizontal content capsule, not its tap
        // target. Keep the 44dp button in place and transfer its glyph inside
        // a capsule with the reference recording's roughly 2:3 width ratio.
        final originWidth = isToolbar
            ? math.min(anchor.width, width)
            : width * 2 / 3;
        final originHeight = isToolbar
            ? math.min(anchor.height, height)
            : math.min(24.0, height);
        final sourceLeft = isRtl ? anchor.left : anchor.right - originWidth;
        final origin = Rect.fromLTWH(
          (isToolbar ? anchor.left : sourceLeft)
              .clamp(safe.left, safe.right - originWidth)
              .toDouble(),
          (isToolbar ? anchor.top : anchor.center.dy - originHeight / 2)
              .clamp(safe.top, safe.bottom - originHeight)
              .toDouble(),
          originWidth,
          originHeight,
        );
        final pivot = isRtl ? origin.topLeft : origin.topRight;
        // Compensate the wrapper's settled .95 scale so menu width, row height
        // and typography retain their existing final logical dimensions.
        final geometryTarget = isToolbar
            ? target
            : _scaleRect(target, pivot, 1 / 0.95);
        final geometrySafe = isToolbar
            ? safe
            : _scaleRect(safe, pivot, 1 / 0.95);
        return AnimatedBuilder(
          animation: animation,
          child: RepaintBoundary(
            child: Material(
              type: MaterialType.transparency,
              child: SingleChildScrollView(
                primary: false,
                padding: const EdgeInsets.all(8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: children,
                ),
              ),
            ),
          ),
          builder: (context, child) {
            final reversing = animation.status == AnimationStatus.reverse;
            final frame = motion();
            final geometry = _animatedRect(
              origin: origin,
              target: geometryTarget,
              frame: frame,
              safe: geometrySafe,
            );
            final shrinkScale = isToolbar ? 1.0 : 1 - frame.shrink * 0.05;
            final rect = isToolbar
                ? geometry
                : _fitRect(_scaleRect(geometry, pivot, shrinkScale), safe);
            final radius = BorderRadius.circular(
              isToolbar
                  ? ui.lerpDouble(origin.shortestSide / 2, 24, frame.size)!
                  : 24 * shrinkScale,
            );
            final contentBlur = isToolbar
                ? frame.contentBlur
                : 18 * (1 - frame.clarity);
            final surfaceOpacity = isToolbar
                ? frame.surfaceOpacity
                : frame.surface;
            final contentOpacity = isToolbar
                ? frame.contentOpacity
                : Curves.easeIn.transform(frame.reveal.clamp(0.0, 1.0));
            final sourceOpacity = isToolbar
                ? frame.sourceOpacity
                : frame.source;

            return Stack(
              children: [
                Positioned.fromRect(
                  rect: rect,
                  child: IgnorePointer(
                    ignoring: reversing || frame.size < 0.8,
                    child: Opacity(
                      opacity: surfaceOpacity,
                      child: Material(
                        animationDuration: Duration.zero,
                        color: scheme.surfaceContainerHigh,
                        surfaceTintColor: Colors.transparent,
                        elevation: 3 * frame.size.clamp(0.0, 1.0),
                        shadowColor: scheme.shadow.withValues(alpha: 0.24),
                        shape: RoundedRectangleBorder(
                          borderRadius: radius,
                          side: media.highContrast
                              ? BorderSide(color: scheme.outline)
                              : BorderSide.none,
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            // Carry the source glyph with the surface, then
                            // hand it back at the anchor during the last frames.
                            if (sourceOpacity > 0)
                              ExcludeSemantics(
                                child: Opacity(
                                  opacity: sourceOpacity,
                                  child: OverflowBox(
                                    alignment: isToolbar
                                        ? Alignment.center
                                        : Alignment.topLeft,
                                    minWidth: origin.width,
                                    maxWidth: origin.width,
                                    minHeight: origin.height,
                                    maxHeight: origin.height,
                                    child: Transform.scale(
                                      alignment: isToolbar
                                          ? Alignment.center
                                          : Alignment.topLeft,
                                      scaleX: rect.width / origin.width,
                                      scaleY: isToolbar
                                          ? rect.height / origin.height
                                          : rect.width / origin.width,
                                      child: SizedBox.fromSize(
                                        size: origin.size,
                                        child: Padding(
                                          padding: isToolbar
                                              ? EdgeInsets.zero
                                              : const EdgeInsetsDirectional.only(
                                                  end: 11.5,
                                                ),
                                          child: Align(
                                            alignment: isToolbar
                                                ? Alignment.center
                                                : isRtl
                                                ? Alignment.centerLeft
                                                : Alignment.centerRight,
                                            child: Icon(
                                              sourceIcon,
                                              size: 21,
                                              color: scheme.onSurfaceVariant,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            OverflowBox(
                              alignment: Alignment.topLeft,
                              minWidth: width,
                              maxWidth: width,
                              minHeight: height,
                              maxHeight: height,
                              child: Transform.scale(
                                alignment: Alignment.topLeft,
                                // Weather preserves glyph proportions while
                                // the changing rounded mask reveals the rows.
                                scaleX: rect.width / width,
                                scaleY: isToolbar
                                    ? rect.height / height
                                    : rect.width / width,
                                child: Opacity(
                                  opacity: contentOpacity,
                                  child: ImageFiltered(
                                    enabled: contentBlur > 0.01,
                                    imageFilter: ui.ImageFilter.blur(
                                      sigmaX: contentBlur,
                                      sigmaY: contentBlur,
                                    ),
                                    child: child,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Rect _scaleRect(Rect rect, Offset pivot, double scale) => Rect.fromLTWH(
    pivot.dx + (rect.left - pivot.dx) * scale,
    pivot.dy + (rect.top - pivot.dy) * scale,
    rect.width * scale,
    rect.height * scale,
  );

  Rect _fitRect(Rect rect, Rect safe) {
    final width = math.min(rect.width, safe.width);
    final height = math.min(rect.height, safe.height);
    return Rect.fromLTWH(
      rect.left.clamp(safe.left, safe.right - width),
      rect.top.clamp(safe.top, safe.bottom - height),
      width,
      height,
    );
  }

  Rect _animatedRect({
    required Rect origin,
    required Rect target,
    required MorphingMenuFrame frame,
    required Rect safe,
  }) {
    final center = Offset.lerp(origin.center, target.center, frame.position)!;
    final currentWidth = ui
        .lerpDouble(origin.width, target.width, frame.size)!
        .clamp(0.1, safe.width);
    final currentHeight = ui
        .lerpDouble(origin.height, target.height, frame.size)!
        .clamp(0.1, safe.height);
    return Rect.fromLTWH(
      (center.dx - currentWidth / 2).clamp(
        safe.left,
        safe.right - currentWidth,
      ),
      (center.dy - currentHeight / 2).clamp(
        safe.top,
        safe.bottom - currentHeight,
      ),
      currentWidth,
      currentHeight,
    );
  }
}
