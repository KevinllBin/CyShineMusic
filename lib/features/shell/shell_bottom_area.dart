import 'package:flutter/widgets.dart';

/// Native navigation reserves the navigation bar in AppShell, while its
/// floating player hovers over content like the legacy toolbar does. Pages
/// therefore pad their scrollables by [floatingExtent] so the last item can
/// still scroll clear of the player. Legacy pages keep their existing padding.
class ShellBottomArea extends InheritedWidget {
  const ShellBottomArea({
    super.key,
    required this.nativeNavigation,
    required this.extent,
    required this.floatingExtent,
    required super.child,
  });

  final bool nativeNavigation;

  /// Full height of the bottom controls (navigation bar plus player strip).
  /// Overlays such as FABs stack above this.
  final double extent;

  /// The part of [extent] that overlaps content instead of pushing it up.
  final double floatingExtent;

  static ShellBottomArea? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShellBottomArea>();

  static double contentPadding(BuildContext context, double legacyPadding) {
    final area = maybeOf(context);
    if (area?.nativeNavigation != true) return legacyPadding;
    return 16 + area!.floatingExtent;
  }

  @override
  bool updateShouldNotify(ShellBottomArea oldWidget) =>
      nativeNavigation != oldWidget.nativeNavigation ||
      extent != oldWidget.extent ||
      floatingExtent != oldWidget.floatingExtent;
}
