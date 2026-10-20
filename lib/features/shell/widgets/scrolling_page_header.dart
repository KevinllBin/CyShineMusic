import 'dart:ui';

import 'package:flutter/material.dart';

/// Keeps the list viewport stable while its title scrolls behind floating controls.
class ScrollingPageHeader extends StatefulWidget {
  const ScrollingPageHeader({
    super.key,
    required this.child,
    required this.headerBuilder,
    required this.topInset,
    this.maxScrollDepth = 0,
  });

  final Widget child;
  final Widget Function(BuildContext context, double scrollOffset)
  headerBuilder;
  final double topInset;
  final int maxScrollDepth;

  @override
  State<ScrollingPageHeader> createState() => _ScrollingPageHeaderState();
}

class _ScrollingPageHeaderState extends State<ScrollingPageHeader> {
  final _offset = ValueNotifier<double>(0);

  void _updateOffset(ScrollMetrics metrics, int depth) {
    if (depth > widget.maxScrollDepth || metrics.axis != Axis.vertical) return;
    final next = (metrics.pixels - metrics.minScrollExtent).clamp(
      0.0,
      double.infinity,
    );
    if (_offset.value != next) _offset.value = next;
  }

  @override
  void dispose() {
    _offset.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (notification) {
        _updateOffset(notification.metrics, notification.depth);
        return false;
      },
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          _updateOffset(notification.metrics, notification.depth);
          return false;
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            ScrollHeaderInset(extent: widget.topInset, child: widget.child),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: ValueListenableBuilder<double>(
                valueListenable: _offset,
                builder: (context, offset, _) =>
                    widget.headerBuilder(context, offset),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ScrollHeaderInset extends InheritedWidget {
  const ScrollHeaderInset({
    super.key,
    required this.extent,
    required super.child,
  });

  final double extent;

  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ScrollHeaderInset>()?.extent ??
      0;

  @override
  bool updateShouldNotify(ScrollHeaderInset oldWidget) =>
      extent != oldWidget.extent;
}

class ScrollHeaderSpacer extends StatelessWidget {
  const ScrollHeaderSpacer({super.key});

  @override
  Widget build(BuildContext context) =>
      SizedBox(height: ScrollHeaderInset.of(context));
}

class FloatingHeaderSurface extends StatelessWidget {
  const FloatingHeaderSurface({
    super.key,
    required this.child,
    this.onImage = false,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final bool onImage;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fill = onImage
        ? Colors.black.withValues(alpha: 0.18)
        : scheme.surfaceContainerLow.withValues(alpha: 0.86);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: onImage ? 0.10 : 0.04),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Material(
            color: fill,
            shape: StadiumBorder(
              side: BorderSide(
                color: onImage
                    ? Colors.white.withValues(alpha: 0.22)
                    : scheme.outlineVariant.withValues(alpha: 0.28),
              ),
            ),
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}
