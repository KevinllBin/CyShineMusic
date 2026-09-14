import 'package:flutter/widgets.dart';

import '../../core/storage/settings_store.dart';

/// Navigation controls reserve space or hover over content depending on [navigationMode].
/// Pages pad their scrollables so the last item can still scroll clear of the controls.
class ShellBottomArea extends InheritedWidget {
  const ShellBottomArea({
    super.key,
    required this.navigationMode,
    required this.extent,
    required this.floatingExtent,
    required super.child,
  });

  final AppNavigationMode navigationMode;
  bool get nativeNavigation => navigationMode == AppNavigationMode.native;

  /// Full height of the bottom controls (navigation bar plus player strip).
  /// Overlays such as FABs stack above this.
  final double extent;

  /// The part of [extent] that overlaps content instead of pushing it up.
  final double floatingExtent;

  static ShellBottomArea? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShellBottomArea>();

  static double contentPadding(BuildContext context, double legacyPadding) {
    final area = maybeOf(context);
    if (area == null) return legacyPadding;
    return switch (area.navigationMode) {
      AppNavigationMode.singleCapsule => legacyPadding,
      AppNavigationMode.native => 16 + area.floatingExtent,
      AppNavigationMode.dualCapsule =>
        area.extent > 0 ? area.extent + 16 : legacyPadding,
    };
  }

  @override
  bool updateShouldNotify(ShellBottomArea oldWidget) =>
      navigationMode != oldWidget.navigationMode ||
      extent != oldWidget.extent ||
      floatingExtent != oldWidget.floatingExtent;
}
