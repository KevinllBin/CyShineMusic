import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:prism_ui/deferred_push.dart';
import 'package:prism_ui/drag_back.dart';
import 'package:prism_ui/keyboard_inset_hold.dart';
import 'package:prism_ui/navigator.dart';
import 'package:prism_ui/page_transition.dart';
import 'package:prism_ui/surface.dart';
import 'package:prism_ui/theme_data.dart';

typedef CloseContainerActionCallback<S> = void Function({S? returnValue});
typedef OpenContainerBuilder<S> =
    Widget Function(
      BuildContext context,
      CloseContainerActionCallback<S> action,
    );
typedef CloseContainerBuilder =
    Widget Function(BuildContext context, VoidCallback action);

typedef ClosedCallback<S> = void Function(S data);

/// Lets a declarative router create the zoom route while this widget retains
/// the measured, hideable source tile. The router supplies its Page settings.
typedef OpenContainerRouteFactory<T> =
    Route<T> Function(RouteSettings settings, WidgetBuilder builder);

/// How an [OpenContainer] opens its page.
enum OpenContainerTransition { push, zoom }

/// Whether the card grows to the display's corners, as iOS's does, rather
/// than to square ones; square either way where the platform reports none.
const _roundsToDisplay = false;

@optionalTypeArgs
class OpenContainer<T extends Object?> extends StatefulWidget {
  const OpenContainer({
    super.key,
    this.closedShape,
    this.onClosed,
    required this.closedBuilder,
    this.openBuilder,
    this.clipBehavior = Clip.antiAlias,
    this.transition = OpenContainerTransition.push,
    this.onOpen,
  }) : assert(openBuilder != null || onOpen != null);

  final RoundedSuperellipseBorder? closedShape;
  final ClosedCallback<T?>? onClosed;
  final CloseContainerBuilder closedBuilder;
  final OpenContainerBuilder<T>? openBuilder;
  final Clip clipBehavior;
  final OpenContainerTransition transition;
  final FutureOr<void> Function(OpenContainerRouteFactory<T>)? onOpen;

  @override
  State<OpenContainer<T?>> createState() => _OpenContainerState<T>();
}

class _OpenContainerState<T> extends State<OpenContainer<T?>> {
  final GlobalKey<_HideableState> _hideableKey = GlobalKey<_HideableState>();
  final GlobalKey _closedBuilderKey = GlobalKey();
  bool _openingExternally = false;
  ColorScheme? _colorScheme;
  _OpenContainerRoute<T>? _activeZoom;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scheme = Theme.of(context).colorScheme;
    final changed = _colorScheme != null && _colorScheme != scheme;
    _colorScheme = scheme;
    if (changed) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) _activeZoom?.refreshTheme();
      });
    }
  }

  _OpenContainerRoute<T> _zoomRoute({
    RouteSettings? settings,
    OpenContainerBuilder<T>? openBuilder,
  }) {
    final route = _activeZoom = _OpenContainerRoute<T>(
      settings: settings,
      closedShape: widget.closedShape,
      closedBuilder: widget.closedBuilder,
      openBuilder: openBuilder ?? widget.openBuilder!,
      hideableKey: _hideableKey,
      closedBuilderKey: _closedBuilderKey,
    );
    unawaited(
      route.completed.then((_) {
        if (identical(_activeZoom, route)) _activeZoom = null;
      }),
    );
    return route;
  }

  Route<T> _route() => switch (widget.transition) {
    OpenContainerTransition.push => CardPageRoute<T>(
      builder: (context) => widget.openBuilder!(
        context,
        ({T? returnValue}) => Navigator.of(context).pop(returnValue),
      ),
    ),
    OpenContainerTransition.zoom => _zoomRoute(),
  };

  Future<void> openContainer() async {
    if (widget.onOpen case final onOpen?) {
      if (_openingExternally) return;
      _openingExternally = true;
      try {
        await onOpen(
          (settings, builder) => _zoomRoute(
            settings: settings,
            openBuilder: (context, _) => builder(context),
          ),
        );
      } finally {
        _openingExternally = false;
      }
      return;
    }
    final T? data = await Navigator.of(context).push(_route());
    if (widget.onClosed != null) {
      widget.onClosed!(data);
    }
  }

  @override
  Widget build(BuildContext context) {
    // The tap's ink keeps spreading under the push, and would otherwise
    // repaint every row sharing this one's boundary on each of its frames.
    return _Hideable(
      key: _hideableKey,
      child: RepaintBoundary(
        child: Surface(
          color: Colors.transparent,
          clipBehavior: widget.clipBehavior,
          shape: widget.closedShape,
          child: Builder(
            key: _closedBuilderKey,
            builder: (BuildContext context) {
              return widget.closedBuilder(context, openContainer);
            },
          ),
        ),
      ),
    );
  }
}

class _Hideable extends StatefulWidget {
  const _Hideable({super.key, required this.child});

  final Widget child;

  @override
  State<_Hideable> createState() => _HideableState();
}

class _HideableState extends State<_Hideable> {
  Size? get placeholderSize => _placeholderSize;
  Size? _placeholderSize;

  set placeholderSize(Size? value) {
    if (_placeholderSize == value) {
      return;
    }
    setState(() {
      _placeholderSize = value;
    });
  }

  bool get isVisible => _visible;
  bool _visible = true;

  set isVisible(bool value) {
    if (_visible == value) {
      return;
    }
    setState(() {
      _visible = value;
    });
  }

  bool get isInTree => _placeholderSize == null;

  @override
  Widget build(BuildContext context) {
    if (_placeholderSize != null) {
      return SizedBox.fromSize(size: _placeholderSize);
    }
    return Visibility(
      visible: _visible,
      maintainSize: true,
      maintainState: true,
      maintainAnimation: true,
      child: widget.child,
    );
  }
}

/// iOS 27's zoom, read from UIKit's settings on the simulator: it opens on a
/// critically damped 0.34 s spring set off at 0.016 of its stiffness, and
/// closes from rest on a 0.34 s one with a 0.08 bounce. The card fills in
/// with the progress while the page fades in over the first 65% of the way
/// and the tile fades out over the last 65%, under a shadow that grows to 40%
/// black.
final _openSpring = SpringDescription.withDurationAndBounce(
  duration: const Duration(milliseconds: 340),
);
final _openSpeed = 0.016 * _openSpring.stiffness;
final _closeSpring = SpringDescription.withDurationAndBounce(
  duration: const Duration(milliseconds: 340),
  bounce: 0.08,
);
const _fadeEnd = 0.65;
const _shadowAlpha = 0.4;
const _closedShadowSigma = 3.0;
const _openShadowSigma = 40.0;
const _closedShadowDy = -3.0;
const _openShadowDy = 10.0;

// Short of complete, so TransitionRoute keeps the page below onstage.
const _draggedValue = 1 - 1e-6;

/// iOS 27's interactive zoom dismissal, measured on the simulator. A drag
/// toward the reading end or down sets off past 10 dp and moves the page with
/// the finger, rubber-banded across and past 60% of the way, shrinking it
/// about where the drag set off by 0.4 for each 60% of the way. Let go, it
/// dismisses once the drag and 0.1 s of its velocity reach 150 dp: the page
/// morphs into the tile on a critically damped 0.4 s spring while its scale
/// and place chase the tile's on 0.42 s and 0.45 s ones; short of that it
/// springs back over 0.25 s. The bar items cross-fade with the drag.
const _dismissSlop = 10.0;
const _dismissReach = 0.6;
const _dismissShrink = 0.4;
const _dismissDistance = 150.0;
const _dismissLead = 0.1;
const _rubberStiffness = 0.55;
const _barItemsFade = 0.6;
final _firstFollowSpring = SpringDescription.withDurationAndBounce(
  duration: const Duration(milliseconds: 200),
);
final _morphSpring = SpringDescription.withDurationAndBounce(
  duration: const Duration(milliseconds: 400),
);
final _chaseScaleSpring = SpringDescription.withDurationAndBounce(
  duration: const Duration(milliseconds: 420),
  bounce: 0.2,
);
final _chasePlaceSpring = SpringDescription.withDurationAndBounce(
  duration: const Duration(milliseconds: 450),
  bounce: 0.18,
);
final _returnSpring = SpringDescription.withDurationAndBounce(
  duration: const Duration(milliseconds: 250),
);

// Not a PageRoute: HeroController takes a page route offstage for its first
// frame, which would hide the tile it zooms out of.
class _OpenContainerRoute<T> extends ModalRoute<T>
    with DragBackRouteMixin<T>, DeferredPushRouteMixin<T>, CardRouteMixin<T> {
  _OpenContainerRoute({
    super.settings,
    required RoundedSuperellipseBorder? closedShape,
    required this.closedBuilder,
    required this.openBuilder,
    required this.hideableKey,
    required this.closedBuilderKey,
  }) : closedRadius = closedShape?.borderRadius ?? BorderRadius.zero;

  final BorderRadiusGeometry closedRadius;
  final CloseContainerBuilder closedBuilder;
  final OpenContainerBuilder<T> openBuilder;
  final GlobalKey<_HideableState> hideableKey;
  final GlobalKey closedBuilderKey;

  @override
  SpringDescription get openSpring => _openSpring;

  @override
  SpringDescription get closeSpring => _closeSpring;

  @override
  double get openLaunchSpeed => _openSpeed;

  @override
  double get closeLaunchSpeed => 0;

  @override
  bool get recedesCovered => true;

  @override
  bool get opaque => true;

  @override
  bool get barrierDismissible => false;

  /// The route the tile is in, and whether it shrinks as this route covers it.
  ModalRoute<dynamic>? _source;
  bool _sourceRecedes = false;

  /// Where a drag back has moved the page, toward the reading end and down.
  final _dragged = ValueNotifier(Offset.zero);

  /// The page's scale and place once a drag back lets it go to the tile.
  _DragDismiss? _dismiss;

  // The closed child stays in this route from the push until the route is
  // dismissed, so it moves between its tile and the route twice per cycle
  // rather than at every status change.
  final _closedRect = ValueNotifier<Rect?>(null);
  final _hostsClosed = ValueNotifier<bool>(false);

  /// Kept from the tile's place, so its buttons' implicit theme animations
  /// do not run through the transition for a theme the page overrides.
  final _closedThemes = ValueNotifier<CapturedThemes?>(null);
  late final Listenable _closedChanges = Listenable.merge([
    _closedRect,
    _hostsClosed,
    _closedThemes,
  ]);

  /// The tile only ever shows in the route while it moves, and fades out
  /// over most of the way, so its opacity goes onto one image draw too.
  final _closedSnapshot = SnapshotController(allowSnapshotting: true);
  late final Widget _closedChild = IgnorePointer(
    child: ExcludeFocus(
      child: ExcludeSemantics(
        child: SnapshotWidget(
          controller: _closedSnapshot,
          mode: SnapshotMode.permissive,
          child: Surface.transparent(
            child: Builder(
              key: closedBuilderKey,
              builder: (BuildContext context) {
                // Use dummy "open container" callback
                // since we are in the process of opening.
                return closedBuilder(context, () {});
              },
            ),
          ),
        ),
      ),
    ),
  );

  bool get _settled => animation!.isCompleted;

  /// How far the open page has faded in.
  double get _openOpacity {
    if (_settled) {
      return 1;
    }
    return clampDouble(animation!.value / _fadeEnd, 0, 1);
  }

  /// How much of the tile still shows, all of it until the page is 35% of
  /// the way open.
  double get _closedOpacity {
    if (_settled) {
      return 0;
    }
    return clampDouble((1 - animation!.value) / _fadeEnd, 0, 1);
  }

  /// How far the page below has receded, which follows the latest zoom over
  /// it rather than this one when two overlap.
  double get _sourceCovered => _source?.secondaryAnimation?.value ?? 0;

  /// The tile's rect where the page below shows it now.
  Rect? _closedRectIn(Size size) {
    final rect = _closedRect.value;
    if (rect == null || !_sourceRecedes) {
      return rect;
    }
    return recededRect(rect, size, _sourceCovered);
  }

  /// The tile's rect once the page below has receded by [covered].
  Rect _closedRectAt(Size size, double covered) {
    final rect = _closedRect.value ?? Offset.zero & size;
    return _sourceRecedes ? recededRect(rect, size, covered) : rect;
  }

  double _extentAlong(Size size) => switch (dragBackAxis) {
    Axis.horizontal => size.width,
    Axis.vertical => size.height,
  };

  /// How far along a drag back has taken the page, 1 at 60% of the way.
  double get _dragProgress {
    final along = switch (dragBackAxis) {
      Axis.horizontal => _dragged.value.dx,
      Axis.vertical => _dragged.value.dy,
    };
    return along / (_dismissReach * _extentAlong(dragBackExtent));
  }

  Offset _onScreen(Offset logical, TextDirection textDirection) =>
      switch (textDirection) {
        TextDirection.ltr => logical,
        TextDirection.rtl => Offset(-logical.dx, logical.dy),
      };

  /// The scale and center a drag back holds the page at.
  (double, Offset) _draggedTransform(Size size, TextDirection textDirection) {
    final scale = 1 - _dismissShrink * _dragProgress;
    final center = size.center(Offset.zero);
    return (
      scale,
      center +
          _onScreen(_dragged.value, textDirection) +
          (dragBackOrigin - center) * (1 - scale),
    );
  }

  BorderRadius _openRadiusOf(BuildContext context) {
    if (!_roundsToDisplay) {
      return BorderRadius.zero;
    }
    return switch (_source) {
      final CardRouteMixin<dynamic> source => source.cardRadiusOf(context),
      _ => displayRadiusOf(context),
    };
  }

  /// Scales in place of the page while it zooms, like the page below.
  final _openSnapshot = SnapshotController();

  void _updateOpenSnapshot() {
    _openSnapshot.allowSnapshotting = !_settled;
    updateBarItems();
    if (_source case final CardRouteMixin<dynamic> source) {
      source.updateBarItems();
    }
  }

  void _handleOpenStatus(AnimationStatus _) => _updateOpenSnapshot();

  bool get _followsDrag => isDragBackHeld && _dismiss == null;

  /// The page is a snapshot until it settles, so its bar items stay out of
  /// it, shown from the moment the zoom sets off until it turns back, and
  /// fading out over the first 60% of a drag back.
  @override
  BarItemsMotion computeBarItems() {
    final covered = super.computeBarItems();
    if (_settled) {
      return covered;
    }
    if (_followsDrag) {
      return (
        lifted: true,
        moving: true,
        shown: true,
        tracking: clampDouble(1 - _dragProgress / _barItemsFade, 0, 1),
      );
    }
    return (
      lifted: true,
      moving: true,
      shown: covered.shown && _dismiss == null,
      tracking: null,
    );
  }

  @override
  double? get barItemsUncovering => _followsDrag
      ? clampDouble((_dragProgress - (1 - _barItemsFade)) / _barItemsFade, 0, 1)
      : null;

  @override
  bool get dragBackDownward => true;

  @override
  double dragBackSlopOf(
    PointerDeviceKind kind,
    DeviceGestureSettings? settings,
  ) => _dismissSlop;

  @override
  Offset dragBackTargetOf(Offset translation) {
    final size = dragBackExtent;
    double rubber(double distance) =>
        (1 - 1 / (_rubberStiffness * distance / size.width + 1)) * size.width;
    final horizontal = dragBackAxis == Axis.horizontal;
    final along = horizontal ? translation.dx : translation.dy;
    final across = horizontal ? translation.dy : translation.dx;
    final reach = _dismissReach * _extentAlong(size);
    final moved = along < 0
        ? -rubber(-along)
        : along <= reach
        ? along
        : reach + rubber(along - reach);
    final aside = across.sign * rubber(across.abs());
    return horizontal ? Offset(moved, aside) : Offset(aside, moved);
  }

  @override
  SpringDescription dragBackFollowSpring({required bool first}) =>
      first ? _firstFollowSpring : super.dragBackFollowSpring(first: first);

  @override
  void didFollowDragBack(Offset followed) => _dragged.value = followed;

  @override
  bool dragBackPops(Offset translation, Offset velocity) {
    return switch (dragBackAxis) {
          Axis.horizontal => translation.dx + _dismissLead * velocity.dx,
          Axis.vertical => translation.dy + _dismissLead * velocity.dy,
        } >=
        _dismissDistance;
  }

  @override
  Future<void>? settleDragBack({required bool pops, required Offset velocity}) {
    _updateOpenSnapshot();
    if (!pops) {
      return followDragBackTo(Offset.zero, _returnSpring);
    }
    if (isCurrent) {
      navigator!.pop();
    }
    return whenStopped(controller!);
  }

  /// Lets the page go to the tile from where the drag holds it, carrying on
  /// at the speed it follows the finger.
  void _dismissFromDrag() {
    final size = dragBackExtent;
    final textDirection =
        Directionality.maybeOf(subtreeContext!) ?? TextDirection.ltr;
    final (scale, center) = _draggedTransform(size, textDirection);
    final velocity = dragBackFollowVelocity;
    final alongVelocity = switch (dragBackAxis) {
      Axis.horizontal => velocity.dx,
      Axis.vertical => velocity.dy,
    };
    final scaleVelocity =
        -_dismissShrink * alongVelocity / (_dismissReach * _extentAlong(size));
    final dismiss = _dismiss = _DragDismiss(
      morph: SpringSimulation(_morphSpring, controller!.value, 0, 0),
      scale: scale,
      scaleVelocity: scaleVelocity,
      center: center,
      centerVelocity:
          _onScreen(velocity, textDirection) -
          (dragBackOrigin - size.center(Offset.zero)) * scaleVelocity,
      target: (progress) {
        final tile = _closedRectAt(size, progress);
        return (tile.width / size.width, tile.center);
      },
    );
    controller!.animateBackWith(dismiss);
    _updateOpenSnapshot();
  }

  @override
  void install() {
    super.install();
    _dragged.addListener(_updateOpenSnapshot);
    animation!.addStatusListener(_handleOpenStatus);
  }

  @override
  TickerFuture didPush() {
    final hideable = hideableKey.currentContext!;
    final source = _source = ModalRoute.of(hideable);
    _sourceRecedes = source is CardRouteMixin && source.canTransitionTo(this);
    _takeMeasurements(navigatorContext: hideable);

    animation!.addStatusListener((AnimationStatus status) {
      switch (status) {
        case AnimationStatus.dismissed:
          _returnClosedChild(visible: true);
          break;
        case AnimationStatus.completed:
          if (!_hostsClosed.value) {
            hideableKey.currentState?.isVisible = false;
          }
          break;
        case AnimationStatus.forward:
        case AnimationStatus.reverse:
          break;
      }
    });

    return super.didPush();
  }

  @override
  bool didPop(T? result) {
    _takeMeasurements(
      navigatorContext: subtreeContext!,
      delayForSourceRoute: true,
    );
    final popped = super.didPop(result);
    if (isDragBackActive) {
      _dismissFromDrag();
    }
    return popped;
  }

  @override
  void didStartDragBack() {
    super.didStartDragBack();
    controller!.value = _draggedValue;
    _updateOpenSnapshot();
  }

  @override
  void didEndDragBack() {
    super.didEndDragBack();
    if (isCurrent) {
      _dragged.value = Offset.zero;
      controller!.value = 1;
    }
    _updateOpenSnapshot();
  }

  @override
  void dispose() {
    final hideable = hideableKey.currentState;
    if (hideable != null && (!hideable.isInTree || !hideable.isVisible)) {
      SchedulerBinding.instance.addPostFrameCallback(
        (Duration d) => hideableKey.currentState
          ?..placeholderSize = null
          ..isVisible = true,
      );
    }
    super.dispose();
    animation!
      ..removeListener(updateBarItems)
      ..removeStatusListener(_handleOpenStatus);
    _dragged.dispose();
    _openSnapshot.dispose();
    _closedSnapshot.dispose();
    _closedRect.dispose();
    _hostsClosed.dispose();
    _closedThemes.dispose();
  }

  void _returnClosedChild({required bool visible}) {
    final hideable = hideableKey.currentState;
    if (hideable == null) {
      return;
    }
    hideable
      ..placeholderSize = null
      ..isVisible = visible;
    _hostsClosed.value = false;
    if (_source case final CardRouteMixin<dynamic> source) {
      source.retakeSnapshot();
    }
  }

  void refreshTheme() {
    final context = subtreeContext;
    if (!isActive || context == null) return;
    _takeMeasurements(navigatorContext: context);
    _closedSnapshot.clear();
    _openSnapshot.clear();
    retakeSnapshot();
    if (_source case final CardRouteMixin<dynamic> source) {
      source.retakeSnapshot();
    }
  }

  void _takeMeasurements({
    required BuildContext navigatorContext,
    bool delayForSourceRoute = false,
  }) {
    final navigatorState = Navigator.of(navigatorContext);
    final navigator = navigatorState.context.findRenderObject()! as RenderBox;

    void takeMeasurementsInSourceRoute([Duration? _]) {
      final hideable = hideableKey.currentContext;
      if (!navigator.attached || hideable == null) {
        return;
      }
      var rect = _getRect(hideableKey, navigator);
      if (_sourceRecedes) {
        rect = unrecededRect(rect, navigator.size, _sourceCovered);
      }
      _closedThemes.value = InheritedTheme.capture(
        from: hideable,
        to: navigatorState.context,
      );
      _closedRect.value = rect;
      hideableKey.currentState!.placeholderSize = rect.size;
      _hostsClosed.value = true;
    }

    if (delayForSourceRoute) {
      // A pop from rest dismisses the route before this frame ends, and the
      // tile it handed back must not be taken again.
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!animation!.isDismissed) {
          takeMeasurementsInSourceRoute();
        }
      });
    } else {
      takeMeasurementsInSourceRoute();
    }
  }

  Rect _getRect(GlobalKey key, RenderBox ancestor) {
    assert(key.currentContext != null);
    assert(ancestor.hasSize);
    final RenderBox render =
        key.currentContext!.findRenderObject()! as RenderBox;
    assert(render.hasSize);
    return MatrixUtils.transformRect(
      render.getTransformTo(ancestor),
      Offset.zero & render.size,
    );
  }

  void closeContainer({T? returnValue}) {
    Navigator.of(subtreeContext!).pop(returnValue);
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final theme = Theme.of(context);
    final surface = SurfaceLevel.page.colorOf(theme.colorScheme);
    final open = SnapshotWidget(
      controller: _openSnapshot,
      mode: SnapshotMode.permissive,
      child: RepaintBoundary(
        child: Surface.transparent(
          child: Builder(
            builder: (BuildContext context) {
              return KeyboardInsetHold(
                child: openBuilder(context, closeContainer),
              );
            },
          ),
        ),
      ),
    );
    return ListenableBuilder(
      listenable: _closedChanges,
      builder: (BuildContext context, Widget? open) {
        return _ContainerTransition(
          route: this,
          pageColor: surface,
          settledColor: theme.colorScheme.surface,
          openRadius: _openRadiusOf(context),
          closed: _hostsClosed.value
              ? _closedThemes.value!.wrap(_closedChild)
              : null,
          open: open!,
        );
      },
      child: open,
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return dragBackDetector(
      coveredTransition(context, secondaryAnimation, child),
    );
  }
}

enum _Slot { closed, open }

/// Zooms the page from the closed child's rect to the whole route by painting
/// alone: the open page is laid out once at its final size and scaled to the
/// rect's width under a clip, and the closed child is scaled the same way.
class _ContainerTransition
    extends SlottedMultiChildRenderObjectWidget<_Slot, RenderBox> {
  const _ContainerTransition({
    required this.route,
    required this.pageColor,
    required this.settledColor,
    required this.openRadius,
    required this.closed,
    required this.open,
  });

  final _OpenContainerRoute<dynamic> route;
  final Color pageColor;
  final Color settledColor;
  final BorderRadius openRadius;
  final Widget? closed;
  final Widget open;

  @override
  Iterable<_Slot> get slots => _Slot.values;

  @override
  Widget? childForSlot(_Slot slot) => switch (slot) {
    _Slot.closed => closed,
    _Slot.open => open,
  };

  @override
  _RenderContainerTransition createRenderObject(BuildContext context) {
    return _RenderContainerTransition(
      route: route,
      pageColor: pageColor,
      settledColor: settledColor,
      openRadius: openRadius,
      shadow: Theme.of(context).brightness == Brightness.light,
      textDirection: Directionality.of(context),
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderContainerTransition renderObject,
  ) {
    renderObject
      ..route = route
      ..pageColor = pageColor
      ..settledColor = settledColor
      ..openRadius = openRadius
      ..shadow = Theme.of(context).brightness == Brightness.light
      ..textDirection = Directionality.of(context)
      ..markNeedsLayout();
  }
}

class _RenderContainerTransition extends RenderBox
    with SlottedContainerRenderObjectMixin<_Slot, RenderBox> {
  _RenderContainerTransition({
    required _OpenContainerRoute<dynamic> route,
    required Color pageColor,
    required Color settledColor,
    required BorderRadius openRadius,
    required bool shadow,
    required TextDirection textDirection,
  }) : _route = route,
       _pageColor = pageColor,
       _settledColor = settledColor,
       _openRadius = openRadius,
       _shadow = shadow,
       _textDirection = textDirection;

  _OpenContainerRoute<dynamic> get route => _route;
  _OpenContainerRoute<dynamic> _route;
  set route(_OpenContainerRoute<dynamic> value) {
    if (identical(value, _route)) {
      return;
    }
    if (attached) {
      _unlisten();
    }
    _route = value;
    if (attached) {
      _listen();
    }
    markNeedsPaint();
  }

  Color _pageColor;
  set pageColor(Color value) {
    if (value == _pageColor) {
      return;
    }
    _pageColor = value;
    markNeedsPaint();
  }

  Color _settledColor;
  set settledColor(Color value) {
    if (value == _settledColor) {
      return;
    }
    _settledColor = value;
    markNeedsPaint();
  }

  BorderRadius _openRadius;
  set openRadius(BorderRadius value) {
    if (value == _openRadius) {
      return;
    }
    _openRadius = value;
    markNeedsPaint();
  }

  bool _shadow;
  set shadow(bool value) {
    if (value == _shadow) {
      return;
    }
    _shadow = value;
    markNeedsPaint();
  }

  TextDirection _textDirection;
  set textDirection(TextDirection value) {
    if (value == _textDirection) {
      return;
    }
    _textDirection = value;
    markNeedsPaint();
  }

  RenderBox? get _closed => childForSlot(_Slot.closed);
  RenderBox? get _open => childForSlot(_Slot.open);

  final _clipLayer = LayerHandle<ContainerLayer>();
  final _openTransformLayer = LayerHandle<TransformLayer>();
  final _openOpacityLayer = LayerHandle<OpacityLayer>();
  final _closedTransformLayer = LayerHandle<TransformLayer>();
  final _closedOpacityLayer = LayerHandle<OpacityLayer>();
  bool _showsOpen = false;

  void _handleChange() {
    markNeedsPaint();
    final showsOpen = _route._openOpacity > 0;
    if (showsOpen != _showsOpen) {
      _showsOpen = showsOpen;
      markNeedsSemanticsUpdate();
    }
  }

  void _handleStatus(AnimationStatus status) {
    if (status == AnimationStatus.reverse) {
      _cutOpening();
    }
    _handleChange();
  }

  void _listen() {
    _showsOpen = _route._openOpacity > 0;
    _route.animation!
      ..addListener(_handleChange)
      ..addStatusListener(_handleStatus);
    _route._dragged.addListener(_handleChange);
  }

  void _unlisten() {
    _route.animation!
      ..removeListener(_handleChange)
      ..removeStatusListener(_handleStatus);
    _route._dragged.removeListener(_handleChange);
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _listen();
  }

  @override
  void detach() {
    _unlisten();
    super.detach();
  }

  @override
  void dispose() {
    _clipLayer.layer = null;
    _openTransformLayer.layer = null;
    _openOpacityLayer.layer = null;
    _closedTransformLayer.layer = null;
    _closedOpacityLayer.layer = null;
    super.dispose();
  }

  double get _progress => _route.animation!.value;

  /// Where a close that cut the opening short set off, with the opening's
  /// frame and its own there.
  ({double at, _ZoomFrame opening, _ZoomFrame closing})? _cut;

  /// The container's frame, or null once the route has settled. iOS opens
  /// it in the scale of the page, which the frame's width sets, and closes
  /// it in the screen's; a close that cuts the opening short eases from the
  /// opening's frame into its own.
  _ZoomFrame? get _frame {
    if (_route._settled) {
      return null;
    }
    if (_route._dismiss case final dismiss?) {
      return _dismissFrame(dismiss);
    }
    if (_route.isDragBackActive) {
      return _draggedFrame();
    }
    final (closed, open, closedRadius, openRadius) = _ends;
    final progress = _progress;
    if (_route.animation!.status != AnimationStatus.reverse) {
      return _openingFrame(closed, open, closedRadius, openRadius, progress);
    }
    final frame = _closingFrame(
      closed,
      open,
      closedRadius,
      openRadius,
      progress,
    );
    if (_cut case (:final at, :final opening, :final closing)) {
      return frame.movedBy(closing, opening, progress / at);
    }
    return frame;
  }

  (Rect, Rect, BorderRadius, BorderRadius) get _ends {
    final open = Offset.zero & size;
    final closed = _route._closedRectIn(size) ?? open;
    var closedRadius = _route.closedRadius.resolve(_textDirection);
    if (_route._closedRect.value case final tile? when tile.width > 0) {
      closedRadius *= closed.width / tile.width;
    }
    return (closed, open, closedRadius, _openRadius);
  }

  /// The page scaled whole where a drag back holds it.
  _ZoomFrame _draggedFrame() {
    final (scale, center) = _route._draggedTransform(size, _textDirection);
    return _ZoomFrame(
      rect: Rect.fromCenter(
        center: center,
        width: size.width * scale,
        height: size.height * scale,
      ),
      radius: _openRadius * scale,
      shadowSigma: _openShadowSigma * scale,
      shadowDy: _openShadowDy * scale,
    );
  }

  /// The page morphing into the tile in its own scale, which with its place
  /// chases the tile's.
  _ZoomFrame _dismissFrame(_DragDismiss dismiss) {
    final (closed, _, closedRadius, openRadius) = _ends;
    final progress = _progress;
    final from = closed.width > 0 ? closed.width / size.width : 1.0;
    final scale = dismiss.scale;
    return _ZoomFrame(
      rect: Rect.fromCenter(
        center: dismiss.center,
        width: size.width * scale,
        height:
            lerpDouble(closed.height / from, size.height, progress)! * scale,
      ),
      radius:
          BorderRadius.lerp(closedRadius / from, openRadius, progress)! * scale,
      shadowSigma:
          lerpDouble(_closedShadowSigma / from, _openShadowSigma, progress)! *
          scale,
      shadowDy:
          lerpDouble(_closedShadowDy / from, _openShadowDy, progress)! * scale,
    );
  }

  _ZoomFrame _openingFrame(
    Rect closed,
    Rect open,
    BorderRadius closedRadius,
    BorderRadius openRadius,
    double progress,
  ) {
    if (closed.width <= 0) {
      return _closingFrame(closed, open, closedRadius, openRadius, progress);
    }
    final from = closed.width / open.width;
    final scale = lerpDouble(from, 1, progress)!;
    return _ZoomFrame(
      rect: Rect.fromCenter(
        center: Offset.lerp(closed.center, open.center, progress)!,
        width: open.width * scale,
        height:
            lerpDouble(closed.height / from, open.height, progress)! * scale,
      ),
      radius:
          BorderRadius.lerp(closedRadius / from, openRadius, progress)! * scale,
      shadowSigma:
          lerpDouble(_closedShadowSigma / from, _openShadowSigma, progress)! *
          scale,
      shadowDy:
          lerpDouble(_closedShadowDy / from, _openShadowDy, progress)! * scale,
    );
  }

  _ZoomFrame _closingFrame(
    Rect closed,
    Rect open,
    BorderRadius closedRadius,
    BorderRadius openRadius,
    double progress,
  ) {
    return _ZoomFrame(
      rect: Rect.lerp(closed, open, progress)!,
      radius: BorderRadius.lerp(
        closedRadius,
        openRadius,
        clampDouble(progress, 0, 1),
      )!,
      shadowSigma: lerpDouble(_closedShadowSigma, _openShadowSigma, progress)!,
      shadowDy: lerpDouble(_closedShadowDy, _openShadowDy, progress)!,
    );
  }

  void _cutOpening() {
    final progress = _progress;
    if (!hasSize || progress <= 0 || progress >= 1 || _route._dismiss != null) {
      _cut = null;
      return;
    }
    final (closed, open, closedRadius, openRadius) = _ends;
    _cut = (
      at: progress,
      opening: _openingFrame(closed, open, closedRadius, openRadius, progress),
      closing: _closingFrame(closed, open, closedRadius, openRadius, progress),
    );
  }

  Matrix4 _openTransform(Rect rect) {
    final scale = rect.width / size.width;
    return Matrix4.translationValues(rect.left, rect.top, 0)
      ..scaleByDouble(scale, scale, 1, 1);
  }

  Matrix4? _closedTransform(Rect rect) {
    final closedRect = _route._closedRect.value;
    if (closedRect == null || closedRect.width == 0) {
      return null;
    }
    final scale = rect.width / closedRect.width;
    return Matrix4.translationValues(rect.left, rect.top, 0)
      ..scaleByDouble(scale, scale, 1, 1);
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) {
    return constraints.biggest;
  }

  @override
  void performLayout() {
    size = constraints.biggest;
    _closed?.layout(
      BoxConstraints.tight(_route._closedRect.value?.size ?? Size.zero),
    );
    _open?.layout(BoxConstraints.tight(size));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final frame = _frame;
    if (frame == null) {
      _clipLayer.layer = null;
      _openTransformLayer.layer = null;
      _openOpacityLayer.layer = null;
      _closedTransformLayer.layer = null;
      _closedOpacityLayer.layer = null;
      context.canvas.drawRect(offset & size, Paint()..color = _settledColor);
      context.paintChild(_open!, offset);
      return;
    }
    final _ZoomFrame(:rect, :radius) = frame;
    if (_shadow) {
      _paintShadow(context.canvas, offset, frame);
    }
    final fill = _pageColor.withValues(
      alpha: _pageColor.a * clampDouble(_progress, 0, 1),
    );
    // UIKit fades the view it zooms to in over the one it leaves.
    final closing = _route.animation!.status == AnimationStatus.reverse;
    void paintContents(PaintingContext context, Offset offset) {
      context.canvas.drawRect(rect.shift(offset), Paint()..color = fill);
      if (closing) {
        _paintOpen(context, offset, rect, _route._openOpacity);
        _paintClosed(context, offset, rect, _route._closedOpacity);
      } else {
        _paintClosed(context, offset, rect, _route._closedOpacity);
        _paintOpen(context, offset, rect, _route._openOpacity);
      }
    }

    if (radius == BorderRadius.zero) {
      final oldLayer = _clipLayer.layer;
      _clipLayer.layer = context.pushClipRect(
        needsCompositing,
        offset,
        rect,
        paintContents,
        clipBehavior: Clip.antiAlias,
        oldLayer: oldLayer is ClipRectLayer ? oldLayer : null,
      );
    } else {
      final oldLayer = _clipLayer.layer;
      _clipLayer.layer = context.pushClipRSuperellipse(
        needsCompositing,
        offset,
        rect,
        radius.toRSuperellipse(rect),
        paintContents,
        oldLayer: oldLayer is ClipRSuperellipseLayer ? oldLayer : null,
      );
    }
  }

  // iOS keeps the shadow out of the card, which shows the page below until
  // it fills in.
  void _paintShadow(Canvas canvas, Offset offset, _ZoomFrame frame) {
    final progress = _progress;
    if (progress <= 0) {
      return;
    }
    final _ZoomFrame(:radius, shadowSigma: sigma) = frame;
    final rect = frame.rect.shift(offset);
    final shadow = rect.shift(Offset(0, frame.shadowDy));
    canvas
      ..save()
      ..clipPath(
        Path()
          ..fillType = PathFillType.evenOdd
          ..addRect(shadow.inflate(3 * sigma))
          ..addRSuperellipse(radius.toRSuperellipse(rect)),
      )
      ..drawRSuperellipse(
        radius.toRSuperellipse(shadow),
        Paint()
          ..color = Color.from(
            alpha: _shadowAlpha * progress,
            red: 0,
            green: 0,
            blue: 0,
          )
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, sigma),
      )
      ..restore();
  }

  // The page is a snapshot while it moves, so its opacity goes onto the one
  // image it draws rather than an offscreen pass of the page.
  void _paintOpen(
    PaintingContext context,
    Offset offset,
    Rect rect,
    double opacity,
  ) {
    if (opacity == 0) {
      _openTransformLayer.layer = null;
      _openOpacityLayer.layer = null;
      return;
    }
    // The page fades in on its own fill, hiding the tile under it.
    void paintTransformed(PaintingContext context, Offset offset) {
      context.canvas.drawRect(rect.shift(offset), Paint()..color = _pageColor);
      _openTransformLayer.layer = context.pushTransform(
        needsCompositing,
        offset,
        _openTransform(rect),
        (context, offset) => context.paintChild(_open!, offset),
        oldLayer: _openTransformLayer.layer,
      );
    }

    if (opacity == 1) {
      _openOpacityLayer.layer = null;
      paintTransformed(context, offset);
      return;
    }
    _openOpacityLayer.layer = context.pushOpacity(
      offset,
      Color.getAlphaFromOpacity(opacity),
      paintTransformed,
      oldLayer: _openOpacityLayer.layer,
    );
  }

  void _paintClosed(
    PaintingContext context,
    Offset offset,
    Rect rect,
    double opacity,
  ) {
    final closed = _closed;
    final transform = _closedTransform(rect);
    if (closed == null || transform == null || opacity == 0) {
      _closedTransformLayer.layer = null;
      _closedOpacityLayer.layer = null;
      return;
    }
    void paintTransformed(PaintingContext context, Offset offset) {
      _closedTransformLayer.layer = context.pushTransform(
        closed.needsCompositing,
        offset,
        transform,
        (context, offset) => context.paintChild(closed, offset),
        oldLayer: _closedTransformLayer.layer,
      );
    }

    if (opacity == 1) {
      _closedOpacityLayer.layer = null;
      paintTransformed(context, offset);
      return;
    }
    _closedOpacityLayer.layer = context.pushOpacity(
      offset,
      Color.getAlphaFromOpacity(opacity),
      paintTransformed,
      oldLayer: _closedOpacityLayer.layer,
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    final rect = isMeasuringAtRest ? null : _frame?.rect;
    if (rect == null) {
      return;
    }
    if (identical(child, _closed)) {
      final closedTransform = _closedTransform(rect);
      if (closedTransform != null) {
        transform.multiply(closedTransform);
      }
      return;
    }
    transform.multiply(_openTransform(rect));
  }

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    if (_closed case final closed?) {
      visitor(closed);
    }
    if (_showsOpen) {
      visitor(_open!);
    }
  }

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    final rect = _frame?.rect;
    if (rect != null && !rect.contains(position)) {
      return false;
    }
    return super.hitTest(result, position: position);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    if (_route._openOpacity == 0) {
      return false;
    }
    final rect = _frame?.rect;
    return result.addWithPaintTransform(
      transform: rect == null ? null : _openTransform(rect),
      position: position,
      hitTest: (BoxHitTestResult result, Offset transformed) {
        return _open!.hitTest(result, position: transformed);
      },
    );
  }
}

@immutable
class _ZoomFrame {
  const _ZoomFrame({
    required this.rect,
    required this.radius,
    required this.shadowSigma,
    required this.shadowDy,
  });

  final Rect rect;
  final BorderRadius radius;
  final double shadowSigma;
  final double shadowDy;

  /// This frame moved by [t] of the way [from] one frame [to] another.
  _ZoomFrame movedBy(_ZoomFrame from, _ZoomFrame to, double t) {
    double move(double value, double from, double to) =>
        value + (to - from) * t;
    return _ZoomFrame(
      rect: Rect.fromLTRB(
        move(rect.left, from.rect.left, to.rect.left),
        move(rect.top, from.rect.top, to.rect.top),
        move(rect.right, from.rect.right, to.rect.right),
        move(rect.bottom, from.rect.bottom, to.rect.bottom),
      ),
      radius: radius + (to.radius - from.radius) * t,
      shadowSigma: move(shadowSigma, from.shadowSigma, to.shadowSigma),
      shadowDy: move(shadowDy, from.shadowDy, to.shadowDy),
    );
  }
}

/// The morph of a page let go to its tile, with the page's scale and place
/// chasing the tile's as the page below grows back around it.
class _DragDismiss extends Simulation {
  _DragDismiss({
    required this.morph,
    required this.scale,
    required this.scaleVelocity,
    required this.center,
    required this.centerVelocity,
    required this.target,
  });

  static const _step = 1 / 480;

  final SpringSimulation morph;
  final (double, Offset) Function(double progress) target;
  double scale;
  double scaleVelocity;
  Offset center;
  Offset centerVelocity;
  double _time = 0;

  static double _pull(SpringDescription spring, double offset, double speed) =>
      (-spring.stiffness * offset - spring.damping * speed) / spring.mass;

  void _advance(double time) {
    while (_time < time) {
      final step = math.min(_step, time - _time);
      _time += step;
      final (scaleTarget, centerTarget) = target(morph.x(_time));
      scaleVelocity +=
          _pull(_chaseScaleSpring, scale - scaleTarget, scaleVelocity) * step;
      scale += scaleVelocity * step;
      final offset = center - centerTarget;
      centerVelocity +=
          Offset(
            _pull(_chasePlaceSpring, offset.dx, centerVelocity.dx),
            _pull(_chasePlaceSpring, offset.dy, centerVelocity.dy),
          ) *
          step;
      center += centerVelocity * step;
    }
  }

  @override
  double x(double time) {
    _advance(time);
    return morph.x(time);
  }

  @override
  double dx(double time) => morph.dx(time);

  @override
  bool isDone(double time) {
    _advance(time);
    final (scaleTarget, centerTarget) = target(morph.x(time));
    return morph.isDone(time) &&
        (scale - scaleTarget).abs() < 1e-4 &&
        scaleVelocity.abs() < 1e-3 &&
        (center - centerTarget).distance < 0.05 &&
        centerVelocity.distance < 0.5;
  }
}
