import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:prism_ui/form_sheet.dart';
import 'package:prism_ui/deferred_push.dart';
import 'package:prism_ui/drag_back.dart';
import 'package:prism_ui/inherited.dart';
import 'package:prism_ui/navigator_resizable.dart';
import 'package:prism_ui/page_transition.dart';
import 'package:prism_ui/pop_scope.dart';
import 'package:prism_ui/shape.dart';
import 'package:prism_ui/sheet_header.dart';
import 'package:prism_ui/sheet.dart';
import 'package:prism_ui/sheet_navigator.dart';
import 'package:prism_ui/surface.dart';
import 'package:prism_ui/theme_data.dart';

Color _sheetColorOf(BuildContext context) =>
    SurfaceLevel.page.colorOf(ColorScheme.of(context));

class PagedSheetRoute<T> extends PageRoute<T>
    with
        DragBackRouteMixin<T>,
        ResizableNavigatorRouteMixin<T>,
        DeferredPushRouteMixin<T>,
        CardRouteMixin<T> {
  PagedSheetRoute({required this.builder});

  final WidgetBuilder builder;

  ScrollController? _sheetScroll;

  @override
  void dispose() {
    _sheetScroll?.dispose();
    super.dispose();
  }

  /// The corners of the sheet the page moves in, never the display's.
  @override
  BorderRadius cardRadiusOf(BuildContext context) {
    return switch (SheetProvider.of(context)?.type) {
      SheetType.bottomSheet =>
        SheetCornersScope.maybeOf(context) ?? bottomSheetRadiusOf(context),
      SheetType.formSheet => switch (formSheetShape) {
        RoundedSuperellipseBorder(:final borderRadius) => borderRadius.resolve(
          Directionality.of(context),
        ),
        _ => BorderRadius.zero,
      },
      _ => BorderRadius.zero,
    };
  }

  @override
  Color settledFillOf(Color surface) => Colors.transparent;

  // The sheet resizes with a push, so an item lifted to hold still would drift
  // off its slot; the items ride the page with no motion of their own.
  @override
  BarItemsMotion computeBarItems() =>
      (lifted: false, moving: false, shown: true, tracking: null);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final createSheetScroll = SheetScrollScope.of(context);
    if (createSheetScroll != null) {
      _sheetScroll ??= createSheetScroll();
    }
    final sheetScroll = _sheetScroll;
    final page = builder(context);
    return Semantics(
      scopesRoute: true,
      explicitChildNodes: true,
      child: resizableContent(
        sheetScroll == null
            ? page
            : PrimaryScrollController(
                controller: sheetScroll,
                automaticallyInheritForPlatforms: TargetPlatform.values.toSet(),
                child: page,
              ),
      ),
    );
  }
}

class PagedSheet extends StatelessWidget {
  const PagedSheet({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final type = SheetProvider.of(context)?.type;
    final pages = NavigatorResizable(child: child);
    return Surface(
      color: _sheetColorOf(context),
      shape: type == SheetType.bottomSheet
          ? RoundedSuperellipseBorder(
              borderRadius: bottomSheetRadiusOf(context),
            )
          : AppShape.none,
      clipBehavior: Clip.antiAlias,
      child: type == SheetType.bottomSheet
          ? Stack(
              children: [
                pages,
                const Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: SheetDragHandle(),
                    ),
                  ),
                ),
              ],
            )
          : pages,
    );
  }
}

/// Pushes the page into the sheet [context] is a page of, and opens a sheet
/// for it anywhere else.
Future<T?> showInSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) {
  if (isSheetPage(context)) {
    return Navigator.of(context).push(PagedSheetRoute<T>(builder: builder));
  }
  return showSheet<T>(context: context, builder: builder);
}

const nestedPagedSheetProps = SheetProps(backgroundColor: Colors.transparent);

/// Opened with [nestedPagedSheetProps]. [onDismiss] is told whether a page is
/// pushed over the root; with no callbacks, back on the root and a tap outside
/// close the sheet.
class NestedPagedSheet extends StatefulWidget {
  const NestedPagedSheet({
    super.key,
    required this.builder,
    this.onExit,
    this.onDismiss,
  });

  final WidgetBuilder builder;
  final VoidCallback? onExit;
  final FutureOr<void> Function(bool hasPushedPages)? onDismiss;

  @override
  State<NestedPagedSheet> createState() => _NestedPagedSheetState();
}

class _NestedPagedSheetState extends State<NestedPagedSheet> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey();
  ValueNotifier<SheetDismissHandler?>? _dismissHandler;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final handler = SheetDismissScope.of(context);
    if (identical(handler, _dismissHandler)) {
      return;
    }
    _releaseDismiss();
    _dismissHandler = handler?..value = _handleDismiss;
  }

  @override
  void dispose() {
    _releaseDismiss();
    super.dispose();
  }

  void _releaseDismiss() {
    final handler = _dismissHandler;
    if (handler != null && handler.value == _handleDismiss) {
      handler.value = null;
    }
    _dismissHandler = null;
  }

  bool get _hasPushedPages => _navigatorKey.currentState?.canPop() ?? false;

  void _close() => Navigator.of(context).pop();

  void _popSheet([Object? result]) => Navigator.of(context).pop(result);

  void _handlePop() {
    if (_hasPushedPages) {
      _navigatorKey.currentState!.pop();
      return;
    }
    (widget.onExit ?? _close)();
  }

  Future<void> _handleDismiss() async {
    final onDismiss = widget.onDismiss;
    if (onDismiss == null) {
      _close();
      return;
    }
    await onDismiss(_hasPushedPages);
  }

  @override
  Widget build(BuildContext context) {
    final sheetProvider = SheetProvider.of(context)!;
    final sheet = PagedSheet(
      child: SheetPagesNavigator(
        key: _navigatorKey,
        onGenerateInitialRoutes: (_, _) => [
          PagedSheetRoute(builder: widget.builder),
        ],
      ),
    );
    return PopGuard(
      onPop: (_) async {
        _handlePop();
        return false;
      },
      child: sheetProvider.copyWith(
        nestedNavigatorPop: _popSheet,
        onClose: _handlePop,
        // A compact sheet's route takes the taps outside it and the drag away.
        child: sheetProvider.type.isCompact
            ? sheet
            : SizedBox(
                height: double.infinity,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: GestureDetector(
                        onTap: () => unawaited(_handleDismiss()),
                      ),
                    ),
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: SizedBox(
                        width: double.infinity,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          child: sheet,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
