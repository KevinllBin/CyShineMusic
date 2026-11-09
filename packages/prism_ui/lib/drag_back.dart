import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:prism_ui/motion.dart';

/// iOS 27's interactive pop, as measured on the simulator: the page trails
/// the finger on a stiff spring, pops when the distance dragged plus the
/// velocity over the 0.35 s left of the transition reaches 0.4665 of the
/// width, and lets go on a spring a flick past 1.5 widths a second speeds
/// up 4.25 times, ramping in from one.
final _followSpring = SpringDescription.withDurationAndBounce(
  duration: const Duration(milliseconds: 80),
  bounce: 0.15,
);
final _releaseSpring = SpringDescription.withDurationAndBounce(
  duration: const Duration(milliseconds: 300),
  bounce: 0.15,
);
const double _popReach = 0.4665;
const double _popLead = 0.35;
const double _flickSpeed = 1.5;
const double _flickRampStart = 1;
const double _flickBoost = 4.25;
const double _touchSlop = 30;
const double _rubberStiffness = 0.55;
const double _rubberReach = 0.5;
const double _dragEdge = 1e-6;

final Animatable<Offset> _slideTween = Tween<Offset>(
  begin: const Offset(1.0, 0.0),
  end: Offset.zero,
);
const Animation<Offset> _noSlide = AlwaysStoppedAnimation(Offset.zero);

/// Lets a press anywhere on the route drag it toward the reading end to pop.
/// A horizontal scrollable, slider or text field under the pointer is deeper
/// in the hit test, so it wins the arena and keeps the drag.
mixin DragBackRouteMixin<T> on ModalRoute<T> {
  bool _dragBackActive = false;
  bool _dragBackHeld = false;
  Offset _dragBackOrigin = Offset.zero;
  Size _dragBackExtent = Size.zero;
  Axis _dragBackAxis = Axis.horizontal;
  Offset _dragBackTranslation = Offset.zero;
  _DragFollower? _follower;
  FocusNode? _focusBeforeDragBack;

  /// While true the route's own transition should follow the finger, through
  /// the release until the route settles.
  bool get isDragBackActive => _dragBackActive;

  @protected
  bool get isDragBackHeld => _dragBackHeld;

  @protected
  Offset get dragBackOrigin => _dragBackOrigin;

  @protected
  Size get dragBackExtent => _dragBackExtent;

  @protected
  Axis get dragBackAxis => _dragBackAxis;

  @protected
  Offset get dragBackFollowVelocity => _follower?.velocity ?? Offset.zero;

  @protected
  AnimationController get dragBackController => controller!;

  /// Whether a drag down dismisses too, locking to the axis it sets off on.
  @protected
  bool get dragBackDownward => false;

  @protected
  double dragBackSlopOf(
    PointerDeviceKind kind,
    DeviceGestureSettings? settings,
  ) {
    return switch (defaultTargetPlatform) {
      TargetPlatform.linux ||
      TargetPlatform.macOS ||
      TargetPlatform.windows => computePanSlop(kind, settings),
      _ when kind == PointerDeviceKind.touch => _touchSlop,
      _ => computeHitSlop(kind, settings),
    };
  }

  /// How far the page has been pulled past where it rests, as a share of the
  /// width; iOS lets a drag toward the leading end stretch it there.
  ValueListenable<double> get dragBackOverdrag => _dragBackOverdrag;
  final _dragBackOverdrag = ValueNotifier(0.0);

  @protected
  Offset dragBackTargetOf(Offset translation) {
    final width = _dragBackExtent.width;
    final reach = _rubberReach * width;
    final dx = translation.dx;
    return Offset(
      dx >= 0
          ? math.min(dx, width)
          : -(1 - 1 / (_rubberStiffness * -dx / reach + 1)) * reach,
      0,
    );
  }

  @protected
  SpringDescription dragBackFollowSpring({required bool first}) =>
      _followSpring;

  @protected
  void didFollowDragBack(Offset followed) {
    if (_dragBackExtent.width == 0) {
      return;
    }
    final value = 1 - followed.dx / _dragBackExtent.width;
    final held = clampDouble(value, _dragEdge, 1 - _dragEdge);
    dragBackController.value = held;
    _dragBackOverdrag.value = math.max(0, value - held);
  }

  @protected
  bool dragBackPops(Offset translation, Offset velocity) {
    return translation.dx + _popLead * velocity.dx >=
        _popReach * _dragBackExtent.width;
  }

  /// Completes once the route rests after the release, or is null if it does.
  @protected
  Future<void>? settleDragBack({required bool pops, required Offset velocity}) {
    final controller = dragBackController;
    final width = _dragBackExtent.width;
    final speed = _releaseSpeedOf(width == 0 ? 0.0 : velocity.dx / width);
    final target = pops ? 0.0 : 1.0;
    if (pops && isCurrent) {
      navigator!.pop();
    }
    final goesPastRest = !pops || _dragBackOverdrag.value > 0;
    if (goesPastRest) {
      controller.stop();
      return _follower!
          .moveTo(
            Offset((1 - target) * width, 0),
            _releaseSpring,
            velocity: Offset(speed * width, 0),
            endsOnArrival: pops,
          )
          .then((_) {
            if (_follower != null) {
              controller.value = target;
            }
          });
    }
    if (!controller.isAnimating) {
      return null;
    }
    controller.animateBackWith(
      ArrivingSimulation(
        SpringSimulation(_releaseSpring, controller.value, target, -speed),
        end: target,
      ),
    );
    return whenStopped(controller);
  }

  double _releaseSpeedOf(double speed) {
    final boost = clampDouble(
      (speed - _flickRampStart) / (_flickSpeed - _flickRampStart),
      0,
      1,
    );
    return speed * (1 + (_flickBoost - 1) * boost);
  }

  @protected
  Future<void>? followDragBackTo(Offset target, SpringDescription spring) {
    return _follower?.moveTo(target, spring);
  }

  /// Completes in the frame [controller] stops in, or is null if it has.
  @protected
  Future<void>? whenStopped(AnimationController controller) {
    if (!controller.isAnimating) {
      return null;
    }
    final stopped = Completer<void>.sync();
    void handleStatus(AnimationStatus status) {
      if (status.isAnimating) {
        return;
      }
      controller.removeStatusListener(handleStatus);
      stopped.complete();
    }

    controller.addStatusListener(handleStatus);
    return stopped.future;
  }

  FocusScopeNode? get _focusScope {
    final context = subtreeContext;
    return context == null
        ? null
        : FocusScope.of(context, createDependency: false);
  }

  @protected
  void didStartDragBack() {}

  /// Called once the route has settled after a drag back, popped or not.
  @protected
  void didEndDragBack() {}

  Widget dragBackDetector(Widget child) {
    return _DragBackDetector(route: this, child: child);
  }

  /// Follows the finger while a drag back is active and stays still
  /// otherwise. A route keeps it in its tree either way: wrapping the page
  /// only once the drag starts would move the page to a new parent, which
  /// rebuilds all of it.
  Widget dragBackSlide(
    BuildContext context,
    Animation<double> animation,
    Widget child,
  ) {
    return SlideTransition(
      position: _dragBackActive ? animation.drive(_slideTween) : _noSlide,
      textDirection: Directionality.of(context),
      child: child,
    );
  }

  @override
  void dispose() {
    final follower = _follower;
    _follower = null;
    follower?.dispose();
    _dragBackOverdrag.dispose();
    super.dispose();
  }

  // popGestureEnabled no longer waits for the route to be fully uncovered or
  // for another drag back to settle, and NavigatorResizable would settle on
  // a pop still running under the drag.
  bool get _canDragBack =>
      isCurrent &&
      popGestureEnabled &&
      secondaryAnimation!.isDismissed &&
      !popGestureInProgress;

  void _startDragBack(Offset origin, Size extent, Axis axis) {
    _dragBackActive = true;
    _dragBackHeld = true;
    _dragBackOrigin = origin;
    _dragBackExtent = extent;
    _dragBackAxis = axis;
    _dragBackTranslation = Offset.zero;
    (_follower ??= _DragFollower(navigator!, _handleFollow)).reset();
    _focusBeforeDragBack = (_focusScope?.hasFocus ?? false)
        ? FocusManager.instance.primaryFocus
        : null;
    didStartDragBack();
    navigator!.didStartUserGesture();
  }

  void _handleFollow() => didFollowDragBack(_follower!.value);

  void _updateDragBack(Offset delta) {
    final follower = _follower!;
    final first = _dragBackTranslation == Offset.zero && !follower.isMoving;
    _dragBackTranslation += delta;
    follower.moveTo(
      dragBackTargetOf(_dragBackTranslation),
      dragBackFollowSpring(first: first),
    );
  }

  void _endDragBack(Offset velocity) {
    final navigator = this.navigator!;
    _dragBackHeld = false;
    _follower!.stop();
    final pops = isCurrent
        ? dragBackPops(_dragBackTranslation, velocity)
        : !isActive;
    final settled = settleDragBack(pops: pops, velocity: velocity);
    if (settled == null) {
      _finishDragBack(navigator);
    } else {
      settled.whenComplete(() => _finishDragBack(navigator));
    }
  }

  void _finishDragBack(NavigatorState navigator) {
    if (!_dragBackActive) {
      return;
    }
    _dragBackActive = false;
    _dragBackOverdrag.value = 0;
    didEndDragBack();
    navigator.didStopUserGesture();
    _refocusAfterDragBack();
  }

  // ModalRoute unfocuses a route under a user gesture and refocuses nothing.
  void _refocusAfterDragBack() {
    final focus = _focusBeforeDragBack;
    _focusBeforeDragBack = null;
    if (focus == null) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (isCurrent &&
          !(_focusScope?.hasFocus ?? false) &&
          (focus.context?.mounted ?? false)) {
        focus.requestFocus();
      }
    });
  }

  void _abortDragBack() {
    final navigator = this.navigator;
    if (!_dragBackActive || navigator == null) {
      return;
    }
    _follower?.stop();
    _dragBackActive = false;
    _dragBackHeld = false;
    _dragBackOverdrag.value = 0;
    _focusBeforeDragBack = null;
    didEndDragBack();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (navigator.mounted) {
        navigator.didStopUserGesture();
      }
    });
  }
}

class _DragBackDetector extends StatefulWidget {
  const _DragBackDetector({required this.route, required this.child});

  final DragBackRouteMixin<dynamic> route;
  final Widget child;

  @override
  State<_DragBackDetector> createState() => _DragBackDetectorState();
}

class _DragBackDetectorState extends State<_DragBackDetector> {
  late final DragGestureRecognizer _recognizer;
  late final _DragBackRecognizer _directed;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    final route = widget.route;
    final DragGestureRecognizer recognizer;
    if (route.dragBackDownward) {
      final dismiss = _DismissGestureRecognizer(route: route, debugOwner: this);
      _directed = dismiss;
      recognizer = dismiss;
    } else {
      final back = _DragBackGestureRecognizer(route: route, debugOwner: this);
      _directed = back;
      recognizer = back;
    }
    _recognizer = recognizer
      ..onStart = _handleDragStart
      ..onUpdate = _handleDragUpdate
      ..onEnd = _handleDragEnd
      ..onCancel = _handleDragCancel;
  }

  @override
  void dispose() {
    _recognizer.dispose();
    if (_dragging) {
      widget.route._abortDragBack();
    }
    super.dispose();
  }

  double get _towardEnd => switch (Directionality.of(context)) {
    TextDirection.rtl => -1,
    TextDirection.ltr => 1,
  };

  Offset _toLogical(Offset value) => Offset(value.dx * _towardEnd, value.dy);

  void _handlePointerDown(PointerDownEvent event) {
    if (widget.route._canDragBack) {
      _directed.towardEnd = _towardEnd;
      _recognizer.addPointer(event);
    }
  }

  void _handleDragStart(DragStartDetails details) {
    _dragging = true;
    widget.route._startDragBack(
      details.localPosition,
      context.size!,
      _directed.axis!,
    );
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    if (!_dragging) {
      return;
    }
    widget.route._updateDragBack(_toLogical(details.delta));
  }

  void _handleDragEnd(DragEndDetails details) {
    if (!_dragging) {
      return;
    }
    _dragging = false;
    widget.route._endDragBack(_toLogical(details.velocity.pixelsPerSecond));
  }

  void _handleDragCancel() {
    if (!_dragging) {
      return;
    }
    _dragging = false;
    widget.route._endDragBack(Offset.zero);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _handlePointerDown,
      behavior: HitTestBehavior.translucent,
      child: widget.child,
    );
  }
}

mixin _DragBackRecognizer on GestureRecognizer {
  double towardEnd = 1;

  Axis? get axis;
}

// Desktop text fields select with a pan, which accepts past the pan slop.
class _DragBackGestureRecognizer extends HorizontalDragGestureRecognizer
    with _DragBackRecognizer {
  _DragBackGestureRecognizer({required this.route, super.debugOwner}) {
    // Alone in the arena, it would win by default and start at once.
    onlyAcceptDragOnThreshold = true;
  }

  final DragBackRouteMixin<dynamic> route;

  @override
  Axis get axis => Axis.horizontal;

  @override
  bool hasSufficientGlobalDistanceToAccept(
    PointerDeviceKind pointerDeviceKind,
    double? deviceTouchSlop,
  ) {
    return globalDistanceMoved * towardEnd >
        route.dragBackSlopOf(pointerDeviceKind, gestureSettings);
  }
}

/// iOS's zoom dismisses on a drag toward the reading end or down that keeps
/// within about 22° of its axis, and never on one with any upward part.
class _DismissGestureRecognizer extends PanGestureRecognizer
    with _DragBackRecognizer {
  _DismissGestureRecognizer({required this.route, super.debugOwner}) {
    onlyAcceptDragOnThreshold = true;
  }

  static const _lockSlope = 0.4;

  final DragBackRouteMixin<dynamic> route;
  @override
  Axis? axis;
  Offset? _down;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    _down = event.position;
    axis = null;
    super.addAllowedPointer(event);
  }

  Axis? _lockOf(Offset moved) {
    final along = moved.dx * towardEnd;
    if (moved.dy < 0) {
      return null;
    }
    if (along > 0 && moved.dy <= along * _lockSlope) {
      return Axis.horizontal;
    }
    if (moved.dy > 0 && moved.dx.abs() <= moved.dy * _lockSlope) {
      return Axis.vertical;
    }
    return null;
  }

  @override
  void handleEvent(PointerEvent event) {
    final down = _down;
    if (event is PointerMoveEvent && axis == null && down != null) {
      final moved = event.position - down;
      if (moved.distance > route.dragBackSlopOf(event.kind, gestureSettings)) {
        axis = _lockOf(moved);
        if (axis == null) {
          _down = null;
          resolve(GestureDisposition.rejected);
          return;
        }
      }
    }
    super.handleEvent(event);
  }

  @override
  bool hasSufficientGlobalDistanceToAccept(
    PointerDeviceKind pointerDeviceKind,
    double? deviceTouchSlop,
  ) => axis != null;
}

/// Trails a target on springs, on a ticker that keeps running so that a
/// target moved every frame still advances.
class _DragFollower {
  _DragFollower(this._navigator, this._onChanged) {
    _ticker = _navigator.createTicker(_tick);
  }

  final NavigatorState _navigator;
  final VoidCallback _onChanged;
  late final Ticker _ticker;
  Offset _value = Offset.zero;
  Offset _velocity = Offset.zero;
  SpringSimulation? _x;
  SpringSimulation? _y;
  Duration _now = Duration.zero;
  Duration _setOff = Duration.zero;
  double? _arrival;
  Completer<void>? _rest;

  Offset get value => _value;
  Offset get velocity => _velocity;
  bool get isMoving => _ticker.isActive;

  void reset() {
    stop();
    _value = Offset.zero;
    _velocity = Offset.zero;
  }

  Future<void> moveTo(
    Offset target,
    SpringDescription spring, {
    Offset? velocity,
    bool endsOnArrival = false,
  }) {
    final from = velocity ?? _velocity;
    _arrival = endsOnArrival && target.dx != _value.dx ? target.dx : null;
    _x = SpringSimulation(
      spring,
      _value.dx,
      target.dx,
      from.dx,
      snapToEnd: true,
    );
    _y = SpringSimulation(
      spring,
      _value.dy,
      target.dy,
      from.dy,
      snapToEnd: true,
    );
    if (_ticker.isActive) {
      _setOff = _now;
    } else {
      _now = Duration.zero;
      _setOff = Duration.zero;
      _ticker.start();
    }
    return (_rest ??= Completer<void>.sync()).future;
  }

  void stop() {
    _ticker.stop();
    _x = null;
    _y = null;
    _settle();
  }

  void _settle() {
    final rest = _rest;
    _rest = null;
    rest?.complete();
  }

  void _tick(Duration elapsed) {
    if (elapsed == Duration.zero) {
      _setOff = -frameIntervalOf(_navigator.context);
    }
    _now = elapsed;
    final x = _x!;
    final y = _y!;
    final time =
        (elapsed - _setOff).inMicroseconds / Duration.microsecondsPerSecond;
    final from = _value.dx;
    _value = Offset(x.x(time), y.x(time));
    _velocity = Offset(x.dx(time), y.dx(time));
    final arrival = _arrival;
    final arrived =
        arrival != null && (_value.dx - arrival) * (from - arrival) <= 0;
    if (arrived) {
      _value = Offset(arrival, _value.dy);
    }
    if (arrived || (x.isDone(time) && y.isDone(time))) {
      _velocity = Offset.zero;
      _ticker.stop();
      _onChanged();
      _settle();
      return;
    }
    _onChanged();
  }

  void dispose() {
    _ticker.dispose();
    _settle();
  }
}
