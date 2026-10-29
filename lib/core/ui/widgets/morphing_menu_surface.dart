import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'morphing_menu_motion.dart';

/// How far a list menu may contract towards its anchor before the exit stops
/// shrinking — as a fraction of the origin→target lerp. Squeezing the whole
/// menu (text included) into the 44x44 source button reads as mush, so the
/// tail of the exit is a dissolve from a compact rectangle instead.
const double listMenuExitFloor = 0.45;

/// Where in the contraction a list menu's content is fully dissolved. Kept
/// above [listMenuExitFloor] so labels are never seen at tiny scales.
const double listMenuExitContentFloor = 0.55;

/// Opacity of the list menu's exit dissolve, keyed on the contraction value.
///
/// The source button fades back in with `1 - listMenuExitSurfaceOpacity`, so
/// one curve drives both sides of the handoff.
double listMenuExitSurfaceOpacity(double size) =>
    (size / listMenuExitFloor).clamp(0.0, 1.0);

/// The content dissolves while the menu is still large enough to read.
double listMenuExitContentOpacity(double size) =>
    ((size - listMenuExitContentFloor) / (1 - listMenuExitContentFloor)).clamp(
      0.0,
      1.0,
    );

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
        final originWidth = math.min(anchor.width, width);
        final originHeight = math.min(anchor.height, height);
        final origin = Rect.fromLTWH(
          anchor.left.clamp(safe.left, safe.right - originWidth).toDouble(),
          anchor.top.clamp(safe.top, safe.bottom - originHeight).toDouble(),
          originWidth,
          originHeight,
        );
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
            final isToolbar = motionStyle == MorphingMenuMotionStyle.toolbar;
            // A list menu contracts towards its anchor only as far as a
            // compact rectangle and dissolves from there; a toolbar menu
            // keeps morphing all the way home to its button.
            final contract = isToolbar || !reversing
                ? frame.size
                : math.max(frame.size, listMenuExitFloor);
            final rect = isToolbar
                ? _toolbarRect(
                    origin: origin,
                    target: target,
                    frame: frame,
                    safe: safe,
                  )
                : Rect.lerp(origin, target, contract)!.intersect(safe);
            final radius = BorderRadius.circular(
              ui.lerpDouble(origin.shortestSide / 2, 24, frame.size)!,
            );
            final contentBlur = isToolbar ? frame.contentBlur : 0.0;
            final surfaceOpacity = isToolbar
                ? frame.surfaceOpacity
                : reversing
                ? listMenuExitSurfaceOpacity(frame.size)
                : 1.0;
            final contentOpacity = isToolbar
                ? frame.contentOpacity
                : reversing
                ? listMenuExitContentOpacity(frame.size)
                : 1.0;

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
                            if (isToolbar && frame.sourceOpacity > 0)
                              ExcludeSemantics(
                                child: Opacity(
                                  opacity: frame.sourceOpacity,
                                  child: OverflowBox(
                                    minWidth: origin.width,
                                    maxWidth: origin.width,
                                    minHeight: origin.height,
                                    maxHeight: origin.height,
                                    child: Transform.scale(
                                      scaleX: rect.width / origin.width,
                                      scaleY: rect.height / origin.height,
                                      child: SizedBox.fromSize(
                                        size: origin.size,
                                        child: Center(
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
                            OverflowBox(
                              alignment: Alignment.topLeft,
                              minWidth: width,
                              maxWidth: width,
                              minHeight: height,
                              maxHeight: height,
                              child: Transform.scale(
                                alignment: Alignment.topLeft,
                                // Scale both axes into the actual surface;
                                // uniform scaling leaves the group in a corner.
                                scaleX: rect.width / width,
                                scaleY: rect.height / height,
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

  Rect _toolbarRect({
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
