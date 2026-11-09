import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:prism_ui/item_position.dart';
import 'package:prism_ui/scroll_behavior.dart';
import 'package:prism_ui/sheet.dart';

class PageActivityScope extends InheritedWidget {
  final bool isActive;

  const PageActivityScope({
    super.key,
    required this.isActive,
    required super.child,
  });

  static bool isActiveOf(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<PageActivityScope>()
            ?.isActive ??
        true;
  }

  @override
  bool updateShouldNotify(PageActivityScope oldWidget) {
    return isActive != oldWidget.isActive;
  }
}

class BottomInsetScope extends InheritedWidget {
  static const double dockedSearchHeight = 48;
  static const double dockedSearchMargin = 16;
  static const double dockedSearchInset =
      dockedSearchMargin + dockedSearchHeight;

  final double inset;

  const BottomInsetScope({
    super.key,
    required this.inset,
    required super.child,
  });

  static double of(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<BottomInsetScope>()
            ?.inset ??
        0;
  }

  @override
  bool updateShouldNotify(BottomInsetScope oldWidget) {
    return inset != oldWidget.inset;
  }
}

/// The room content still has to leave at its top, where the scaffold has
/// already placed something of its own there.
class TopInsetScope extends InheritedWidget {
  final double? inset;

  const TopInsetScope({super.key, required this.inset, required super.child});

  static double? of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<TopInsetScope>()?.inset;
  }

  @override
  bool updateShouldNotify(TopInsetScope oldWidget) {
    return inset != oldWidget.inset;
  }
}

/// How far a page's app bar reaches over the body floating under it.
class FloatingBarScope extends InheritedWidget {
  final double inset;

  const FloatingBarScope({
    super.key,
    required this.inset,
    required super.child,
  });

  static double? of(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<FloatingBarScope>()
        ?.inset;
  }

  @override
  bool updateShouldNotify(FloatingBarScope oldWidget) {
    return inset != oldWidget.inset;
  }
}

class ItemPositionProvider extends InheritedWidget {
  final ItemPosition position;

  const ItemPositionProvider({
    super.key,
    required this.position,
    required super.child,
  });

  static ItemPositionProvider? of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<ItemPositionProvider>();
  }

  @override
  bool updateShouldNotify(ItemPositionProvider oldWidget) =>
      position != oldWidget.position;
}

class ProxyDecoratorProvider extends InheritedWidget {
  final bool isProxyDecorator;
  final double lift;

  const ProxyDecoratorProvider({
    super.key,
    required this.isProxyDecorator,
    required this.lift,
    required super.child,
  });

  static ProxyDecoratorProvider? of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<ProxyDecoratorProvider>();
  }

  @override
  bool updateShouldNotify(ProxyDecoratorProvider oldWidget) =>
      isProxyDecorator != oldWidget.isProxyDecorator || lift != oldWidget.lift;
}

class SheetProvider<T> extends InheritedWidget {
  final SheetType type;
  final void Function([T? result])? nestedNavigatorPop;

  /// The close button's way out of the sheet; [nestedNavigatorPop] only pops.
  final VoidCallback? onClose;

  const SheetProvider({
    super.key,
    required super.child,
    required this.type,
    this.nestedNavigatorPop,
    this.onClose,
  });

  SheetProvider copyWith({
    SheetType? type,
    void Function([T? result])? nestedNavigatorPop,
    VoidCallback? onClose,
    required Widget child,
  }) {
    return SheetProvider<T>(
      type: type ?? this.type,
      nestedNavigatorPop: nestedNavigatorPop ?? this.nestedNavigatorPop,
      onClose: onClose ?? this.onClose,
      child: child,
    );
  }

  static SheetProvider? of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<SheetProvider>();
  }

  @override
  bool updateShouldNotify(SheetProvider oldWidget) =>
      type != oldWidget.type ||
      nestedNavigatorPop != oldWidget.nestedNavigatorPop ||
      onClose != oldWidget.onClose;
}

/// How far a sheet's content hangs below the screen at its current detent.
class SheetOverhangScope extends InheritedWidget {
  final ValueListenable<double> overhang;
  final bool fitsContent;

  const SheetOverhangScope({
    super.key,
    required this.overhang,
    this.fitsContent = false,
    required super.child,
  });

  static ValueListenable<double>? of(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<SheetOverhangScope>()
        ?.overhang;
  }

  static bool fillsDetentOf(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<SheetOverhangScope>();
    return scope != null && !scope.fitsContent;
  }

  @override
  bool updateShouldNotify(SheetOverhangScope oldWidget) =>
      overhang != oldWidget.overhang || fitsContent != oldWidget.fitsContent;
}

/// Resolves once the content has closed the sheet or decided to keep it.
typedef SheetDismissHandler = Future<void> Function();

/// Lets a sheet's content take over what a drag away or a tap outside does.
class SheetDismissScope extends InheritedWidget {
  final ValueNotifier<SheetDismissHandler?> handler;

  const SheetDismissScope({
    super.key,
    required this.handler,
    required super.child,
  });

  static ValueNotifier<SheetDismissHandler?>? of(BuildContext context) {
    return context.getInheritedWidgetOfExactType<SheetDismissScope>()?.handler;
  }

  @override
  bool updateShouldNotify(SheetDismissScope oldWidget) =>
      handler != oldWidget.handler;
}

/// Makes a scroll controller that hands drags to the sheet, one per route
/// inside it: a controller shared by pages kept alive together fails the
/// scrollbar's single position check.
class SheetScrollScope extends InheritedWidget {
  final SheetScrollControllerFactory createController;

  const SheetScrollScope({
    super.key,
    required this.createController,
    required super.child,
  });

  static SheetScrollControllerFactory? of(BuildContext context) {
    return context
        .getInheritedWidgetOfExactType<SheetScrollScope>()
        ?.createController;
  }

  @override
  bool updateShouldNotify(SheetScrollScope oldWidget) =>
      createController != oldWidget.createController;
}

typedef SheetScrollControllerFactory =
    ScrollController Function({double initialScrollOffset});

ScrollController sheetScrollController(
  BuildContext context, {
  double initialScrollOffset = 0.0,
}) {
  final createController = SheetScrollScope.of(context);
  if (createController == null) {
    return _PageScrollController(initialScrollOffset: initialScrollOffset);
  }
  return createController(initialScrollOffset: initialScrollOffset);
}

class _PageScrollController extends ScrollController {
  _PageScrollController({super.initialScrollOffset});

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) {
    return _PageScrollPosition(
      physics: physics,
      context: context,
      initialPixels: initialScrollOffset,
      keepScrollOffset: keepScrollOffset,
      oldPosition: oldPosition,
      debugLabel: debugLabel,
    );
  }
}

class _PageScrollPosition extends ScrollPositionWithSingleContext
    with InitialPixelsInRange {
  _PageScrollPosition({
    required super.physics,
    required super.context,
    super.initialPixels,
    super.keepScrollOffset,
    super.oldPosition,
    super.debugLabel,
  });
}
