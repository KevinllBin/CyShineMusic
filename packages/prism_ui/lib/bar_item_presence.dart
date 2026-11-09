import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/glyph_icon.dart';
import 'package:prism_ui/liquid_glass.dart';
import 'package:prism_ui/navigator.dart';
import 'package:prism_ui/page_transition.dart';

/// SwiftUI's glass toolbar springs an item in from 1.2 and a blur of 10 a
/// frame after its page first moves, which is when a ticker started then
/// first ticks. Only ultra glass blurs: each glyph's takes a layer and its own
/// render passes and textures on every frame of a push or pop.
final _presenceSpring = SpringDescription.withDurationAndBounce(
  duration: const Duration(milliseconds: 416),
  bounce: 0.25,
);
const _absentScale = 1.2;
const _absentBlur = 10.0;
const _swappedGlyphScale = 0.2;

// The items of the page leaving and of the page in overlap as they cross-fade,
// and would each stack a glass level over the other.
const _barItemGlass = Object();

final _titleSpring = SpringDescription.withDurationAndBounce(
  duration: const Duration(milliseconds: 330),
);

/// SwiftUI's swell of a glass container that changes its glyph.
final _pulseUp = SpringSimulation(
  SpringDescription.withDurationAndBounce(
    duration: const Duration(milliseconds: 292),
    bounce: 0.5,
  ),
  0,
  1,
  0,
);
final _pulseDownAcross = SpringSimulation(
  SpringDescription.withDurationAndBounce(
    duration: const Duration(milliseconds: 416),
    bounce: 0.5,
  ),
  0,
  1,
  0,
);
final _pulseDownDown = SpringSimulation(
  SpringDescription.withDurationAndBounce(
    duration: const Duration(milliseconds: 416),
    bounce: 0.416,
  ),
  0,
  1,
  0,
);
const _pulseAcrossLag = 0.142;
const _pulseDownLag = 0.113;
const _pulseSwell = 0.2;
const _pulseLength = Duration(milliseconds: 900);

double _springAt(Simulation spring, double time) =>
    time <= 0 ? 0 : spring.x(time);

({double across, double down}) _pulseAt(double progress) {
  final time =
      progress * _pulseLength.inMicroseconds / Duration.microsecondsPerSecond;
  final up = _springAt(_pulseUp, time);
  return (
    across:
        1 +
        _pulseSwell *
            (up - _springAt(_pulseDownAcross, time - _pulseAcrossLag)),
    down:
        1 +
        _pulseSwell * (up - _springAt(_pulseDownDown, time - _pulseDownLag)),
  );
}

bool _sameGlyph(Widget a, Widget b) =>
    identical(a, b) ||
    (a is GlyphIcon &&
        b is GlyphIcon &&
        a.glyph == b.glyph &&
        a.fill == b.fill &&
        a.size == b.size &&
        a.color == b.color);

/// A bar item that a card route lifts into an overlay where it rests, as iOS's
/// stay out of a zoom and hold still in a push; a covered page's draw in the
/// root overlay the app wraps its navigator in, above the page over it. An
/// item resting where the leaving page's did keeps that glass, as iOS's do.
class BarItemPresence extends StatefulWidget {
  const BarItemPresence({super.key, required this.child})
    : _kind = _PresenceKind.item;

  /// Rests over a zoom out of its page, emptied and fading, as iOS's tab bar.
  const BarItemPresence.held({super.key, required this.child})
    : _kind = _PresenceKind.held;

  /// A title, which slides with its page but fades in place across a zoom.
  const BarItemPresence.title({super.key, required this.child})
    : _kind = _PresenceKind.title;

  /// Glass at a page's foot, riding a push but resting out of a zoom.
  const BarItemPresence.foot({super.key, required this.child})
    : _kind = _PresenceKind.foot;

  final _PresenceKind _kind;

  final Widget child;

  static Animation<double>? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_PresenceScope>()?.presence;

  static ValueListenable<bool>? filledOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_PresenceScope>()?.filled;

  @override
  State<BarItemPresence> createState() => _BarItemPresenceState();
}

class _BarItemPresenceState extends State<BarItemPresence>
    with TickerProviderStateMixin {
  static final _live = <_BarItemPresenceState>{};
  static var _pairingScheduled = false;

  final _itemKey = GlobalKey();
  final _overlay = OverlayPortalController();
  late final _presence = AnimationController.unbounded(vsync: this)
    ..addStatusListener(_handlePresenceStatus);
  late final _swap = AnimationController.unbounded(vsync: this, value: 1)
    ..addStatusListener(_handleSwapStatus);
  late final _pulse = AnimationController(vsync: this, duration: _pulseLength)
    ..addStatusListener(_handlePresenceStatus);
  Widget? _swapped;
  ValueListenable<BarItemsMotion>? _motion;
  Animation<double>? _covering;
  final _filled = ValueNotifier(true);
  CardRouteMixin<Object?>? _route;
  Listenable? _routeMotion;
  double? _target;

  Rect? _rest;
  Size? _slotSize;
  BoxConstraints? _slotConstraints;
  var _overRoutes = false;
  var _liftScheduled = false;
  var _remeasureScheduled = false;

  var _tracking = false;

  bool get _materializes => widget._kind == _PresenceKind.item;

  BarItemsMotion get _now => switch ((widget._kind, _motion?.value)) {
    (_, null) ||
    (
      _PresenceKind.title || _PresenceKind.foot,
      (lifted: false, moving: _, shown: _, tracking: _),
    ) => (lifted: false, moving: false, shown: true, tracking: null),
    (
      _PresenceKind.held,
      (lifted: true, moving: _, :final shown, :final tracking),
    ) =>
      (
        lifted: true,
        moving: false,
        shown: shown,
        tracking: tracking ?? (shown ? null : 1 - (_covering?.value ?? 0)),
      ),
    (_PresenceKind.held, _) => (
      lifted: false,
      moving: false,
      shown: true,
      tracking: null,
    ),
    (_PresenceKind.title || _PresenceKind.foot, final motion?) => (
      lifted: true,
      moving: false,
      shown: motion.shown,
      tracking: motion.tracking,
    ),
    (_PresenceKind.item, final motion?) => motion,
  };

  @override
  void initState() {
    super.initState();
    _live.add(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // A page that goes off stage freezes a fade where nothing shows it.
    if (!TickerMode.valuesOf(context).enabled) {
      _finishMotion();
    }
    final route = switch (ModalRoute.of(context)) {
      final CardRouteMixin<Object?> route => route,
      _ => null,
    };
    if (identical(route, _route) && _target != null) {
      return;
    }
    _motion?.removeListener(_handleMotion);
    _covering?.removeListener(_handleMotion);
    _route = route;
    // A sheet carrying the page moves it too, as when it closes mid-push.
    _routeMotion = route == null
        ? null
        : Listenable.merge([
            for (final carrier in routesCarrying(context)) ...[
              carrier.animation,
              carrier.secondaryAnimation,
            ],
          ]);
    _motion = route?.barItems?..addListener(_handleMotion);
    if (widget._kind == _PresenceKind.held) {
      _covering = route?.secondaryAnimation?..addListener(_handleMotion);
    }
    if (_target == null) {
      final now = _now;
      _target = now.shown && !now.lifted ? 1 : 0;
      _presence.value = _target!;
    }
    _handleMotion();
  }

  @override
  void didUpdateWidget(BarItemPresence oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_rest != null) {
      _scheduleRemeasure();
    }
  }

  @override
  void dispose() {
    _live.remove(this);
    _motion?.removeListener(_handleMotion);
    _covering?.removeListener(_handleMotion);
    _filled.dispose();
    _presence.dispose();
    _swap.dispose();
    _pulse.dispose();
    super.dispose();
  }

  void _finishMotion() {
    if (_presence.isAnimating) {
      _presence.value = _target!;
    }
    if (_swap.isAnimating || _pulse.isAnimating) {
      _endSwap();
    }
    _updateLift();
  }

  void _handleMotion() {
    final now = _now;
    _filled.value = !now.lifted || now.shown || _motion?.value.tracking != null;
    if (now.tracking case final tracking?) {
      _tracking = true;
      _presence.value = tracking;
      _updateLift();
      return;
    }
    final target = now.shown ? 1.0 : 0.0;
    if (_tracking || target != _target) {
      _tracking = false;
      _target = target;
      _settle(target);
    }
    _updateLift();
  }

  void _handlePresenceStatus(AnimationStatus _) => _updateLift();

  void _handleSwapStatus(AnimationStatus _) {
    if (!_swap.isAnimating && _swapped != null) {
      setState(() => _swapped = null);
    }
    _updateLift();
  }

  void _settle(double target) {
    if (widget._kind == _PresenceKind.held) {
      _presence.value = target;
      return;
    }
    final moving = _presence.isAnimating;
    final from = _presence.value;
    if (!moving && from == target) {
      return;
    }
    _presence.animateWith(
      SpringSimulation(
        widget._kind == _PresenceKind.item ? _presenceSpring : _titleSpring,
        from,
        target,
        moving ? _presence.velocity : 0,
        snapToEnd: true,
      ),
    );
    _schedulePairing();
  }

  /// Pairs the items that set off in this frame once both pages' have.
  static void _schedulePairing() {
    if (_pairingScheduled) {
      return;
    }
    _pairingScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _pairingScheduled = false;
      for (final arriving in _live.where((item) => item._arriving).toList()) {
        for (final leaving in _live) {
          if (arriving._sharesSlotWith(leaving)) {
            arriving._takeOver(leaving);
            break;
          }
        }
      }
    });
  }

  bool get _arriving =>
      mounted &&
      _materializes &&
      _target == 1 &&
      _presence.value <= 0.1 &&
      _swapped == null;

  bool get _leaving =>
      mounted && _materializes && _target == 0 && _presence.value >= 0.9;

  bool _sharesSlotWith(_BarItemPresenceState other) {
    final route = _route;
    final otherRoute = other._route;
    if (!other._leaving ||
        route == null ||
        otherRoute == null ||
        identical(route, otherRoute) ||
        !identical(route.navigator, otherRoute.navigator)) {
      return false;
    }
    final rest = _restIn(null);
    final otherRest = other._restIn(null);
    return rest != null &&
        otherRest != null &&
        (rest.topLeft - otherRest.topLeft).distance < 0.5 &&
        (rest.bottomRight - otherRest.bottomRight).distance < 0.5;
  }

  void _takeOver(_BarItemPresenceState leaving) {
    final glyph = _glyph();
    final leavingGlyph = leaving._glyph();
    if (glyph == null || leavingGlyph == null) {
      return;
    }
    final swapped = leaving._swap.isAnimating ? leaving._swap.value : null;
    final pulsed = leaving._pulse.isAnimating ? leaving._pulse.value : null;
    leaving._handOver();
    if (!_sameGlyph(glyph, leavingGlyph)) {
      final from = swapped == null ? 0.0 : 1 - swapped;
      _swap.animateWith(
        SpringSimulation(_presenceSpring, from, 1, 0, snapToEnd: true),
      );
      _pulse.forward(from: pulsed ?? 0);
      setState(() => _swapped = leavingGlyph);
    }
    _presence.value = 1;
    _updateLift();
  }

  void _handOver() {
    _endSwap();
    _presence.value = 0;
    _updateLift();
  }

  void _endSwap() {
    _swap.value = 1;
    _pulse.reset();
    if (_swapped != null) {
      setState(() => _swapped = null);
    }
  }

  /// The one glyph of the item, which another can swap in place of its own.
  Widget? _glyph() {
    final found = <Widget>[];
    void visit(Element element) {
      if (element.widget case BarItemGlyph(:final child)) {
        found.add(child);
      } else {
        element.visitChildren(visit);
      }
    }

    (_itemKey.currentContext as Element?)?.visitChildren(visit);
    return found.length == 1 ? found.single : null;
  }

  // Looked up each time: a page that changes parents while lifted, as a home
  // page does when the window crosses the mobile width, outlives this overlay.
  RenderObject? get _overlayBox => Overlay.maybeOf(
    context,
    rootOverlay: _overRoutes,
  )?.context.findRenderObject();

  bool get _lifts =>
      _now.lifted ||
      _now.moving ||
      _presence.isAnimating ||
      _swap.isAnimating ||
      _pulse.isAnimating ||
      _tracking;

  void _updateLift() {
    if (!mounted) {
      return;
    }
    final lifts = _lifts;
    if (lifts == (_rest != null)) {
      return;
    }
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      if (!_liftScheduled) {
        _liftScheduled = true;
        SchedulerBinding.instance.addPostFrameCallback((_) {
          _liftScheduled = false;
          _updateLift();
        });
      }
      return;
    }
    if (lifts) {
      _lift();
    } else {
      _setRest(null);
    }
  }

  /// Where the item rests, in [ancestor]'s coordinates or the screen's; a page
  /// kept alive off screen, as a tab's is, has its transform zeroed.
  Rect? _restIn(RenderObject? ancestor) => _placeIn(ancestor)?.rect;

  _Placement? _placeIn(RenderObject? ancestor) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || !box.attached) {
      return null;
    }
    final rest = MatrixUtils.transformRect(
      measureAtRest(() => box.getTransformTo(ancestor)),
      Offset.zero & box.size,
    );
    if (!rest.isFinite || rest.isEmpty) {
      return null;
    }
    return (rect: rest, scale: rest.width / box.size.width);
  }

  void _lift() {
    final overRoutes = !(_route?.secondaryAnimation?.isDismissed ?? true);
    final rest = _restIn(
      Overlay.of(context, rootOverlay: overRoutes).context.findRenderObject(),
    );
    if (rest == null) {
      return;
    }
    _overRoutes = overRoutes;
    final shownInSlot = switch (_itemKey.currentContext
        ?.findRenderObject()
        ?.parent) {
      final _RenderPresence presence => presence.painted,
      _ => true,
    };
    _setRest(rest);
    // The page below has taken its snapshot with the item still in it.
    if (shownInSlot) {
      _route?.retakeSnapshot();
    }
  }

  void _setRest(Rect? rest) {
    setState(() {
      _rest = rest;
      _slotSize = rest == null
          ? null
          : (context.findRenderObject()! as RenderBox).size;
    });
    if (rest == null) {
      _overlay.hide();
    } else {
      _overlay.show();
    }
  }

  /// Content that changes size while lifted resizes the slot it left, which
  /// moves where it rests a frame later.
  void _handleLiftedSize(Size size) {
    if (size == _slotSize) {
      return;
    }
    _slotSize = size;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted && _rest != null) {
        setState(() {});
        _scheduleRemeasure();
      }
    });
  }

  void _scheduleRemeasure() {
    if (_remeasureScheduled) {
      return;
    }
    _remeasureScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _remeasureScheduled = false;
      if (!mounted || _rest == null) {
        return;
      }
      final rest = _restIn(_overlayBox);
      if (rest != null && rest != _rest) {
        setState(() => _rest = rest);
      }
    });
  }

  Widget _present(Widget child) {
    final presence = _presence.view;
    return _PresenceScope(
      presence: presence,
      swap: _swap.view,
      swapped: _swapped,
      filled: _filled,
      child: _Presence(
        presence: presence,
        pulse: _pulse.view,
        scales: widget._kind == _PresenceKind.item,
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final item = KeyedSubtree(
      key: _itemKey,
      // The dock's lens must stand a level over the dock to read its glass.
      child: widget._kind == _PresenceKind.held
          ? widget.child
          : LiquidGlassGroup(shared: _barItemGlass, child: widget.child),
    );
    final rest = _rest;
    return OverlayPortal(
      controller: _overlay,
      overlayLocation: _overRoutes
          ? OverlayChildLocation.rootOverlay
          : OverlayChildLocation.nearestOverlay,
      // The item's own tooltips and menus would otherwise target the route
      // Overlay it inherits, which is not a render ancestor once lifted into
      // the root Overlay, and a layout-builder portal asserts on that.
      overlayChildBuilder: (context) => Overlay.wrap(
        child: Positioned.fill(
          child: _LiftedItem(
            rest: _slotSize ?? Size.zero,
            locate: () => _placeIn(_overlayBox),
            follow: _routeMotion,
            slot: _slotConstraints,
            onSize: _handleLiftedSize,
            // Lifted, the item animates over the routes; without a boundary
            // of its own each frame repaints the overlay and all above it.
            child: RepaintBoundary(
              child: ListenableBuilder(
                listenable: _motion ?? const AlwaysStoppedAnimation(0),
                builder: (_, child) => IgnorePointer(
                  ignoring: !_now.shown || !(_route?.isCurrent ?? true),
                  child: child,
                ),
                child: _present(item),
              ),
            ),
          ),
        ),
      ),
      child: _SlotProbe(
        onLayout: (constraints) => _slotConstraints = constraints,
        child: rest == null
            ? _present(item)
            : SizedBox.fromSize(size: _slotSize),
      ),
    );
  }
}

enum _PresenceKind { item, held, title, foot }

class _SlotProbe extends SingleChildRenderObjectWidget {
  const _SlotProbe({required this.onLayout, super.child});

  final ValueChanged<BoxConstraints> onLayout;

  @override
  _RenderSlotProbe createRenderObject(BuildContext context) =>
      _RenderSlotProbe(onLayout);

  @override
  void updateRenderObject(BuildContext context, _RenderSlotProbe renderObject) {
    renderObject.onLayout = onLayout;
  }
}

class _RenderSlotProbe extends RenderProxyBox {
  _RenderSlotProbe(this.onLayout);

  ValueChanged<BoxConstraints> onLayout;

  @override
  void performLayout() {
    onLayout(constraints);
    super.performLayout();
  }
}

typedef _Placement = ({Rect rect, double scale});

/// A lifted item, laid out as its slot would lay it out, so content that
/// changes mid-flight takes its own size rather than the one it lifted with.
///
/// It is placed where its slot rests as it paints, since a sheet resizing
/// with the push moves the slot without laying out the page it is in.
class _LiftedItem extends SingleChildRenderObjectWidget {
  const _LiftedItem({
    required this.rest,
    required this.locate,
    required this.follow,
    required this.slot,
    required this.onSize,
    super.child,
  });

  final Size rest;
  final ValueGetter<_Placement?> locate;
  final Listenable? follow;
  final BoxConstraints? slot;
  final ValueChanged<Size> onSize;

  @override
  _RenderLiftedItem createRenderObject(BuildContext context) =>
      _RenderLiftedItem(
        rest: rest,
        locate: locate,
        follow: follow,
        slot: slot,
        onSize: onSize,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderLiftedItem renderObject,
  ) {
    renderObject
      ..rest = rest
      ..locate = locate
      ..follow = follow
      ..slot = slot
      ..onSize = onSize;
  }
}

class _RenderLiftedItem extends RenderProxyBox {
  _RenderLiftedItem({
    required Size rest,
    required this.locate,
    required Listenable? follow,
    required BoxConstraints? slot,
    required this.onSize,
  }) : _rest = rest,
       _follow = follow,
       _slot = slot;

  ValueGetter<_Placement?> locate;
  ValueChanged<Size> onSize;
  _Placement? _placement;
  final _transformLayer = LayerHandle<TransformLayer>();

  Size get rest => _rest;
  Size _rest;
  set rest(Size value) {
    if (_rest != value) {
      _rest = value;
      markNeedsLayout();
    }
  }

  Listenable? _follow;
  set follow(Listenable? value) {
    if (identical(value, _follow)) {
      return;
    }
    if (attached) {
      _follow?.removeListener(markNeedsPaint);
      value?.addListener(markNeedsPaint);
    }
    _follow = value;
    markNeedsPaint();
  }

  BoxConstraints? get slot => _slot;
  BoxConstraints? _slot;
  set slot(BoxConstraints? value) {
    if (_slot != value) {
      _slot = value;
      markNeedsLayout();
    }
  }

  @override
  bool get isRepaintBoundary => true;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _follow?.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _follow?.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void dispose() {
    _transformLayer.layer = null;
    super.dispose();
  }

  Matrix4 get _transform {
    final (:rect, :scale) = _placement ?? (rect: Rect.zero, scale: 1.0);
    return Matrix4.translationValues(rect.left, rect.top, 0)
      ..scaleByDouble(scale, scale, 1, 1);
  }

  @override
  void performLayout() {
    size = constraints.biggest;
    final child = this.child;
    if (child == null) {
      return;
    }
    child.layout(_slot ?? BoxConstraints.tight(_rest), parentUsesSize: true);
    if (_slot != null) {
      onSize(child.size);
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) {
      return;
    }
    final placement = _placement = locate() ?? _placement;
    if (placement == null || placement.scale == 1) {
      _transformLayer.layer = null;
      context.paintChild(
        child,
        offset + (placement?.rect.topLeft ?? Offset.zero),
      );
      return;
    }
    _transformLayer.layer = context.pushTransform(
      needsCompositing,
      offset,
      _transform,
      (context, offset) => context.paintChild(child, offset),
      oldLayer: _transformLayer.layer,
    );
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final child = this.child;
    if (child == null) {
      return false;
    }
    return result.addWithPaintTransform(
      transform: _transform,
      position: position,
      hitTest: (result, position) => child.hitTest(result, position: position),
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    transform.multiply(_transform);
  }
}

class _PresenceScope extends InheritedWidget {
  const _PresenceScope({
    required this.presence,
    required this.swap,
    required this.swapped,
    required this.filled,
    required super.child,
  });

  final Animation<double> presence;
  final Animation<double> swap;
  final Widget? swapped;
  final ValueListenable<bool> filled;

  @override
  bool updateShouldNotify(_PresenceScope oldWidget) =>
      presence != oldWidget.presence ||
      swap != oldWidget.swap ||
      swapped != oldWidget.swapped ||
      filled != oldWidget.filled;
}

/// The glyph of a bar item, growing out of the glyph it swaps in its
/// container as that one shrinks away.
class BarItemGlyph extends StatefulWidget {
  const BarItemGlyph({super.key, required this.child});

  final Widget child;

  @override
  State<BarItemGlyph> createState() => _BarItemGlyphState();
}

class _BarItemGlyphState extends State<BarItemGlyph> {
  final _own = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final own = KeyedSubtree(key: _own, child: widget.child);
    final scope = context.dependOnInheritedWidgetOfExactType<_PresenceScope>();
    if (scope == null) {
      return own;
    }
    final blurs =
        LiquidGlassScope.of(context) &&
        LiquidGlassScope.qualityOf(context) == LiquidGlassQuality.ultra;
    final swapped = scope.swapped;
    if (swapped == null) {
      if (!blurs) {
        return own;
      }
      return AnimatedBuilder(
        animation: scope.presence,
        builder: (_, child) => _blurAbsent(scope.presence.value, child!),
        child: own,
      );
    }
    return AnimatedBuilder(
      animation: scope.swap,
      builder: (_, child) => Stack(
        alignment: Alignment.center,
        children: [
          _GlyphSwap(shown: 1 - scope.swap.value, blurs: blurs, child: swapped),
          _GlyphSwap(shown: scope.swap.value, blurs: blurs, child: child!),
        ],
      ),
      child: own,
    );
  }
}

Widget _blurAbsent(double shown, Widget child) {
  final sigma = _absentBlur * clampDouble(1 - shown, 0, 1);
  return ImageFiltered(
    enabled: sigma > 0,
    imageFilter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
    child: child,
  );
}

class _GlyphSwap extends StatelessWidget {
  const _GlyphSwap({
    required this.shown,
    required this.blurs,
    required this.child,
  });

  final double shown;
  final bool blurs;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: clampDouble(shown, 0, 1),
      child: Transform.scale(
        scale: _swappedGlyphScale + (1 - _swappedGlyphScale) * shown,
        child: blurs ? _blurAbsent(shown, child) : child,
      ),
    );
  }
}

class _Presence extends SingleChildRenderObjectWidget {
  const _Presence({
    required this.presence,
    required this.pulse,
    required this.scales,
    super.child,
  });

  final Animation<double> presence;
  final Animation<double> pulse;
  final bool scales;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderPresence(presence, pulse, scales: scales);

  @override
  void updateRenderObject(BuildContext context, _RenderPresence renderObject) {
    renderObject
      ..presence = presence
      ..pulse = pulse
      ..scales = scales;
  }
}

/// Paints its child as it is once fully present, so a bar at rest keeps no
/// layer of its own.
class _RenderPresence extends RenderProxyBox {
  _RenderPresence(this._presence, this._pulse, {required bool scales})
    : _scales = scales;

  bool _scales;
  set scales(bool value) {
    if (value != _scales) {
      _scales = value;
      markNeedsPaint();
    }
  }

  Animation<double> _presence;
  set presence(Animation<double> value) {
    if (identical(value, _presence)) {
      return;
    }
    if (attached) {
      _presence.removeListener(_handlePresence);
      value.addListener(_handlePresence);
    }
    _presence = value;
    _handlePresence();
  }

  Animation<double> _pulse;
  set pulse(Animation<double> value) {
    if (identical(value, _pulse)) {
      return;
    }
    if (attached) {
      _pulse.removeListener(_handlePresence);
      value.addListener(_handlePresence);
    }
    _pulse = value;
    _handlePresence();
  }

  final _transformLayer = LayerHandle<TransformLayer>();
  late bool _present = _isPresent;
  late bool _absent = _isAbsent;

  bool get _isPresent =>
      _presence.value == 1 && (_pulse.value == 0 || _pulse.value == 1);

  bool get _isAbsent => _presence.value <= 0;

  var painted = false;

  void _handlePresence() {
    final present = _isPresent;
    if (present != _present) {
      _present = present;
      markNeedsCompositingBitsUpdate();
    }
    final absent = _isAbsent;
    if (absent != _absent) {
      _absent = absent;
      markNeedsSemanticsUpdate();
    }
    markNeedsPaint();
  }

  @override
  bool get alwaysNeedsCompositing => child != null && !_present;

  Matrix4 get _transform {
    final scale = _scales
        ? _absentScale - (_absentScale - 1) * _presence.value
        : 1.0;
    final pulse = _pulseAt(_pulse.value);
    final center = size.center(Offset.zero);
    return Matrix4.translationValues(center.dx, center.dy, 0)
      ..scaleByDouble(scale * pulse.across, scale * pulse.down, 1, 1)
      ..translateByDouble(-center.dx, -center.dy, 0, 1);
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _presence.addListener(_handlePresence);
    _pulse.addListener(_handlePresence);
    _handlePresence();
  }

  @override
  void detach() {
    _presence.removeListener(_handlePresence);
    _pulse.removeListener(_handlePresence);
    super.detach();
  }

  @override
  void dispose() {
    _transformLayer.layer = null;
    super.dispose();
  }

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    if (!_absent) {
      super.visitChildrenForSemantics(visitor);
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    painted = child != null;
    if (child == null || _present) {
      _transformLayer.layer = null;
      super.paint(context, offset);
      return;
    }
    final alpha = Color.getAlphaFromOpacity(clampDouble(_presence.value, 0, 1));
    if (alpha == 0) {
      painted = false;
      _transformLayer.layer = null;
      return;
    }
    _transformLayer.layer = context.pushTransform(
      needsCompositing,
      offset,
      _transform,
      (context, offset) => LiquidGlassFade.push(
        context,
        offset,
        alpha,
        (context, offset) => context.paintChild(child, offset),
      ),
      oldLayer: _transformLayer.layer,
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    if (!_present) {
      transform.multiply(_transform);
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    return result.addWithPaintTransform(
      transform: _present ? null : _transform,
      position: position,
      hitTest: (result, position) =>
          super.hitTestChildren(result, position: position),
    );
  }
}
