import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// An opt-in viewport for low-density car screens. All routes and overlays
/// share the same layout, paint and hit-test transform.
class CarDisplayViewport extends StatelessWidget {
  const CarDisplayViewport({
    super.key,
    required this.enabled,
    required this.sizeFactor,
    required this.child,
  });

  final bool enabled;
  final double sizeFactor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        // Use the full window, not the keyboard-reduced content height, so
        // opening the keyboard never changes the interface scale.
        final available = Size(
          size.width - media.viewPadding.horizontal,
          size.height - media.viewPadding.vertical,
        );
        final baseline = math
            .min(available.width / 1280, available.height / 720)
            .clamp(1.0, 3.0);
        final limit = math
            .min(available.width / 800, available.height / 480)
            .clamp(1.0, 3.0);
        final scale = enabled ? (baseline * sizeFactor).clamp(1.0, limit) : 1.0;
        final viewport = size / scale;
        final adjustedMedia = scale == 1
            ? media
            : media.copyWith(
                size: viewport,
                devicePixelRatio: media.devicePixelRatio * scale,
                padding: media.padding / scale,
                viewPadding: media.viewPadding / scale,
                viewInsets: media.viewInsets / scale,
                systemGestureInsets: media.systemGestureInsets / scale,
                displayFeatures: [
                  for (final feature in media.displayFeatures)
                    ui.DisplayFeature(
                      bounds: Rect.fromLTRB(
                        feature.bounds.left / scale,
                        feature.bounds.top / scale,
                        feature.bounds.right / scale,
                        feature.bounds.bottom / scale,
                      ),
                      type: feature.type,
                      state: feature.state,
                    ),
                ],
              );
        return FittedBox(
          fit: BoxFit.fill,
          child: SizedBox(
            width: viewport.width,
            height: viewport.height,
            child: MediaQuery(
              data: adjustedMedia,
              child: CarDisplayLayout(
                enabled: enabled,
                wide:
                    enabled &&
                    viewport.width >= 840 &&
                    viewport.width > viewport.height,
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }
}

class CarDisplayLayout extends InheritedWidget {
  const CarDisplayLayout({
    super.key,
    required this.enabled,
    required this.wide,
    required super.child,
  });

  final bool enabled;
  final bool wide;

  static bool enabledOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CarDisplayLayout>()?.enabled ??
      false;

  static bool wideOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CarDisplayLayout>()?.wide ??
      false;

  static BoxConstraints contentConstraints(
    BuildContext context, {
    required double maxWidth,
  }) =>
      BoxConstraints(maxWidth: enabledOf(context) ? double.infinity : maxWidth);

  @override
  bool updateShouldNotify(CarDisplayLayout oldWidget) =>
      enabled != oldWidget.enabled || wide != oldWidget.wide;
}
