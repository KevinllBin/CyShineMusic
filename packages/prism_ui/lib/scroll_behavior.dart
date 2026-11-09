import 'dart:math';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:prism_ui/scroll.dart';
import 'package:prism_ui/theme_data.dart';

bool isTouchPlatform(TargetPlatform platform) => switch (platform) {
  TargetPlatform.android ||
  TargetPlatform.iOS ||
  TargetPlatform.fuchsia => true,
  TargetPlatform.linux ||
  TargetPlatform.macOS ||
  TargetPlatform.windows => false,
};

class BaseScrollBehavior extends ScrollBehavior {
  const BaseScrollBehavior({this.scrollbarPadding = EdgeInsets.zero});

  final EdgeInsets scrollbarPadding;

  @override
  TargetPlatform getPlatform(BuildContext context) =>
      Theme.of(context).platform;

  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.stylus,
    PointerDeviceKind.invertedStylus,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.mouse,
    PointerDeviceKind.unknown,
  };

  bool showScrollbar(BuildContext context) =>
      !isTouchPlatform(getPlatform(context));

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    if (axisDirectionToAxis(details.direction) == Axis.horizontal ||
        !showScrollbar(context)) {
      return child;
    }
    return Scrollbar.ambient(
      controller: details.controller,
      padding: scrollbarPadding,
      child: child,
    );
  }

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return switch (getPlatform(context)) {
      TargetPlatform.android => StretchingOverscrollIndicator(
        axisDirection: details.direction,
        clipBehavior: details.decorationClipBehavior ?? Clip.hardEdge,
        child: child,
      ),
      TargetPlatform.fuchsia => GlowingOverscrollIndicator(
        axisDirection: details.direction,
        color: Theme.of(context).colorScheme.secondary,
        child: child,
      ),
      TargetPlatform.iOS ||
      TargetPlatform.linux ||
      TargetPlatform.macOS ||
      TargetPlatform.windows => child,
    };
  }

  @override
  bool shouldNotify(covariant BaseScrollBehavior oldDelegate) {
    return oldDelegate.scrollbarPadding != scrollbarPadding;
  }
}

class HiddenBarScrollBehavior extends BaseScrollBehavior {
  const HiddenBarScrollBehavior();

  @override
  bool showScrollbar(BuildContext context) => false;
}

class ShowBarScrollBehavior extends BaseScrollBehavior {
  const ShowBarScrollBehavior({super.scrollbarPadding});

  @override
  bool showScrollbar(BuildContext context) => true;
}

class NextClampingScrollPhysics extends ClampingScrollPhysics {
  const NextClampingScrollPhysics({super.parent});

  @override
  NextClampingScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return NextClampingScrollPhysics(parent: buildParent(ancestor));
  }

  // iOS momentum is sized for its friction fling; a clamping one multiplies it.
  @override
  double carriedMomentum(double existingVelocity) => 0;

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    final Tolerance tolerance = toleranceFor(position);
    if (position.outOfRange) {
      double? end;
      if (position.pixels > position.maxScrollExtent) {
        end = position.maxScrollExtent;
      }
      if (position.pixels < position.minScrollExtent) {
        end = position.minScrollExtent;
      }
      assert(end != null);
      return ScrollSpringSimulation(
        spring,
        end!,
        end,
        min(0.0, velocity),
        tolerance: tolerance,
      );
    }
    if (velocity.abs() < tolerance.velocity) {
      return null;
    }
    if (velocity > 0.0 && position.pixels >= position.maxScrollExtent) {
      return null;
    }
    if (velocity < 0.0 && position.pixels <= position.minScrollExtent) {
      return null;
    }
    return ClampingScrollSimulation(
      position: position.pixels,
      velocity: velocity,
      tolerance: tolerance,
    );
  }
}

class FollowEndScrollPhysics extends NextClampingScrollPhysics {
  const FollowEndScrollPhysics({required this.isFollowing, super.parent});

  final ValueGetter<bool> isFollowing;

  static bool isAtEnd(ScrollMetrics metrics) =>
      metrics.pixels >= metrics.maxScrollExtent - precisionErrorTolerance;

  @override
  FollowEndScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return FollowEndScrollPhysics(
      isFollowing: isFollowing,
      parent: buildParent(ancestor),
    );
  }

  @override
  double adjustPositionForNewDimensions({
    required ScrollMetrics oldPosition,
    required ScrollMetrics newPosition,
    required bool isScrolling,
    required double velocity,
  }) {
    if (isFollowing() && isAtEnd(oldPosition)) {
      return newPosition.maxScrollExtent;
    }
    return super.adjustPositionForNewDimensions(
      oldPosition: oldPosition,
      newPosition: newPosition,
      isScrolling: isScrolling,
      velocity: velocity,
    );
  }
}

mixin ScrubbableScrollPosition on ScrollPosition {
  bool isScrubbing = false;
}

/// Lays a list out in its first frame at an offset given past its end, as
/// one opening at its newest item asks with double.maxFinite. Flutter keeps
/// that offset through the first layout, which builds no item, and springs
/// back to the end a frame later, the first frame a pushed page moves in.
mixin InitialPixelsInRange on ScrollPosition {
  @override
  bool applyContentDimensions(double minScrollExtent, double maxScrollExtent) {
    if (!hasContentDimensions && hasPixels) {
      final inRange = clampDouble(pixels, minScrollExtent, maxScrollExtent);
      if (inRange != pixels) {
        correctPixels(inRange);
        return false;
      }
    }
    return super.applyContentDimensions(minScrollExtent, maxScrollExtent);
  }
}

/// Drags move the sheet until it opens fully, so a scrollbar hides till then.
mixin SheetScrollController on ScrollController {
  ValueListenable<bool> get sheetOpen;
}
