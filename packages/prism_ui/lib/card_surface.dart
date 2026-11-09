import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:prism_ui/press_sparkle.dart';

/// How a surface shows that it is held down.
enum PressLook {
  /// Lays [CardSurface.inkColor] over the fill while held and, on Android,
  /// sends a sparkle out from where the press landed.
  ink,

  /// Tints the whole surface, as iOS 27 tints a held button.
  tint,
  none,
}

/// The fill, press highlight, focus ring and hit area of a card, laid out as a
/// button: no smaller than [minimum], centred in a [tapTarget] it may grow to.
class CardSurface extends SingleChildRenderObjectWidget {
  const CardSurface({
    super.key,
    required this.shape,
    required this.fill,
    required this.previousFill,
    required this.side,
    required this.previousSide,
    required this.transition,
    required this.pressed,
    this.hover = const Color(0x00000000),
    this.sparkles,
    this.inkColor = const Color(0x00000000),
    required this.look,
    required this.brightness,
    required this.padding,
    required this.minimum,
    required this.tapTarget,
    required this.interactive,
    required this.selected,
    this.childFills = false,
    this.clipsChild = false,
    this.onTap,
    this.onPointerDown,
    this.onPointerEnd,
    this.onHover,
    super.child,
  });

  final OutlinedBorder shape;
  final Color fill;
  final Color previousFill;
  final BorderSide side;
  final BorderSide previousSide;

  /// Runs from the previous fill and side to the current ones.
  final Animation<double> transition;

  /// How far the press highlight shows, from 0 to 1.
  final Animation<double> pressed;

  /// Laid over the fill while a pointer rests on an interactive surface.
  final Color hover;

  final PressSparkles? sparkles;
  final Color inkColor;
  final PressLook look;

  final Brightness brightness;
  final EdgeInsets padding;
  final BoxConstraints minimum;
  final Size tapTarget;
  final bool interactive;
  final bool selected;

  /// Lays the child out to fill the surface, for a background behind it.
  final bool childFills;
  final bool clipsChild;
  final VoidCallback? onTap;
  final ValueChanged<PointerDownEvent>? onPointerDown;
  final ValueChanged<PointerEvent>? onPointerEnd;
  final ValueChanged<bool>? onHover;

  @override
  RenderCardSurface createRenderObject(BuildContext context) =>
      RenderCardSurface(
          shape: shape,
          fill: fill,
          previousFill: previousFill,
          side: side,
          previousSide: previousSide,
          transition: transition,
          pressed: pressed,
          hover: hover,
          sparkles: sparkles,
          inkColor: inkColor,
          look: look,
          brightness: brightness,
          padding: padding,
          minimum: minimum,
          tapTarget: tapTarget,
          interactive: interactive,
          selected: selected,
          childFills: childFills,
          clipsChild: clipsChild,
          textDirection: Directionality.of(context),
        )
        ..onTap = onTap
        ..onPointerDown = onPointerDown
        ..onPointerEnd = onPointerEnd
        ..onHover = onHover;

  @override
  void updateRenderObject(
    BuildContext context,
    RenderCardSurface renderObject,
  ) {
    renderObject
      ..shape = shape
      ..fill = fill
      ..previousFill = previousFill
      ..side = side
      ..previousSide = previousSide
      ..transition = transition
      ..pressed = pressed
      ..hover = hover
      ..sparkles = sparkles
      ..inkColor = inkColor
      ..look = look
      ..brightness = brightness
      ..padding = padding
      ..minimum = minimum
      ..tapTarget = tapTarget
      ..interactive = interactive
      ..selected = selected
      ..childFills = childFills
      ..clipsChild = clipsChild
      ..textDirection = Directionality.of(context)
      ..onTap = onTap
      ..onPointerDown = onPointerDown
      ..onPointerEnd = onPointerEnd
      ..onHover = onHover;
  }
}

class RenderCardSurface extends RenderShiftedBox
    implements MouseTrackerAnnotation {
  RenderCardSurface({
    required OutlinedBorder shape,
    required Color fill,
    required Color previousFill,
    required BorderSide side,
    required BorderSide previousSide,
    required Animation<double> transition,
    required Animation<double> pressed,
    required Color hover,
    required PressSparkles? sparkles,
    required Color inkColor,
    required PressLook look,
    required Brightness brightness,
    required EdgeInsets padding,
    required BoxConstraints minimum,
    required Size tapTarget,
    required bool interactive,
    required bool selected,
    required bool childFills,
    required bool clipsChild,
    required TextDirection textDirection,
  }) : _shape = shape,
       _fill = fill,
       _previousFill = previousFill,
       _side = side,
       _previousSide = previousSide,
       _transition = transition,
       _pressed = pressed,
       _hover = hover,
       _sparkles = sparkles,
       _inkColor = inkColor,
       _look = look,
       _brightness = brightness,
       _padding = padding,
       _minimum = minimum,
       _tapTarget = tapTarget,
       _interactive = interactive,
       _selected = selected,
       _childFills = childFills,
       _clipsChild = clipsChild,
       _textDirection = textDirection,
       _tinting = look == PressLook.tint && pressed.value > 0,
       super(null);

  // iOS 27 fades a held button to three quarters in a light scheme and mixes
  // a fifth of white into it in a dark one.
  static const _tintFade = 0.25;
  static const _tintLift = 0.2;

  VoidCallback? onTap;
  ValueChanged<PointerDownEvent>? onPointerDown;
  ValueChanged<PointerEvent>? onPointerEnd;
  ValueChanged<bool>? onHover;

  Rect _visual = Rect.zero;
  bool _childClaimed = false;
  bool _validForMouseTracker = false;
  bool _tinting;
  final _clip = LayerHandle<ClipPathLayer>();

  OutlinedBorder _shape;

  set shape(OutlinedBorder value) {
    if (_shape == value) {
      return;
    }
    _shape = value;
    markNeedsPaint();
  }

  Color _fill;

  set fill(Color value) {
    if (_fill == value) {
      return;
    }
    _fill = value;
    markNeedsPaint();
  }

  Color _previousFill;

  set previousFill(Color value) {
    if (_previousFill == value) {
      return;
    }
    _previousFill = value;
    markNeedsPaint();
  }

  BorderSide _side;

  set side(BorderSide value) {
    if (_side == value) {
      return;
    }
    _side = value;
    markNeedsPaint();
  }

  BorderSide _previousSide;

  set previousSide(BorderSide value) {
    if (_previousSide == value) {
      return;
    }
    _previousSide = value;
    markNeedsPaint();
  }

  Animation<double> _transition;

  set transition(Animation<double> value) {
    if (_transition == value) {
      return;
    }
    if (attached) {
      _transition.removeListener(markNeedsPaint);
      value.addListener(markNeedsPaint);
    }
    _transition = value;
    markNeedsPaint();
  }

  Animation<double> _pressed;

  set pressed(Animation<double> value) {
    if (_pressed == value) {
      return;
    }
    if (attached) {
      _pressed.removeListener(_handlePress);
      value.addListener(_handlePress);
    }
    _pressed = value;
    _handlePress();
  }

  Color _hover;

  set hover(Color value) {
    if (_hover == value) {
      return;
    }
    _hover = value;
    if (_hovered) {
      markNeedsPaint();
    }
  }

  bool _hovered = false;

  PressSparkles? _sparkles;

  set sparkles(PressSparkles? value) {
    if (_sparkles == value) {
      return;
    }
    if (attached) {
      _sparkles?.removeListener(markNeedsPaint);
      value?.addListener(markNeedsPaint);
    }
    _sparkles = value;
    markNeedsPaint();
  }

  Color _inkColor;

  set inkColor(Color value) {
    if (_inkColor == value) {
      return;
    }
    _inkColor = value;
    markNeedsPaint();
  }

  PressLook _look;

  set look(PressLook value) {
    if (_look == value) {
      return;
    }
    _look = value;
    _handlePress();
  }

  Brightness _brightness;

  set brightness(Brightness value) {
    if (_brightness == value) {
      return;
    }
    _brightness = value;
    markNeedsPaint();
  }

  EdgeInsets _padding;

  set padding(EdgeInsets value) {
    if (_padding == value) {
      return;
    }
    _padding = value;
    markNeedsLayout();
  }

  BoxConstraints _minimum;

  set minimum(BoxConstraints value) {
    if (_minimum == value) {
      return;
    }
    _minimum = value;
    markNeedsLayout();
  }

  Size _tapTarget;

  set tapTarget(Size value) {
    if (_tapTarget == value) {
      return;
    }
    _tapTarget = value;
    markNeedsLayout();
  }

  bool _interactive;

  bool get interactive => _interactive;

  set interactive(bool value) {
    if (_interactive == value) {
      return;
    }
    _interactive = value;
    // Repainting lets the mouse tracker pick up the new cursor.
    markNeedsPaint();
    markNeedsSemanticsUpdate();
  }

  bool _selected;

  set selected(bool value) {
    if (_selected == value) {
      return;
    }
    _selected = value;
    markNeedsSemanticsUpdate();
  }

  bool _childFills;

  set childFills(bool value) {
    if (_childFills == value) {
      return;
    }
    _childFills = value;
    markNeedsLayout();
  }

  bool _clipsChild;

  set clipsChild(bool value) {
    if (_clipsChild == value) {
      return;
    }
    _clipsChild = value;
    markNeedsPaint();
  }

  TextDirection _textDirection;

  set textDirection(TextDirection value) {
    if (_textDirection == value) {
      return;
    }
    _textDirection = value;
    markNeedsPaint();
  }

  @override
  MouseCursor get cursor =>
      _interactive ? SystemMouseCursors.click : SystemMouseCursors.basic;

  @override
  PointerEnterEventListener? get onEnter => _handleEnter;

  @override
  PointerExitEventListener? get onExit => _handleExit;

  void _handleEnter(PointerEnterEvent event) => _setHovered(true);

  void _handleExit(PointerExitEvent event) => _setHovered(false);

  void _setHovered(bool hovered) {
    if (_hovered != hovered) {
      _hovered = hovered;
      if (_hover.a > 0) {
        markNeedsPaint();
      }
    }
    onHover?.call(hovered);
  }

  bool get _tints => _look == PressLook.tint && _pressed.value > 0;

  void _handlePress() {
    final tinting = _tints;
    if (tinting != _tinting) {
      _tinting = tinting;
      markNeedsCompositingBitsUpdate();
    }
    markNeedsPaint();
  }

  @override
  bool get alwaysNeedsCompositing => _tinting;

  @override
  bool get validForMouseTracker => _validForMouseTracker;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _transition.addListener(markNeedsPaint);
    _pressed.addListener(_handlePress);
    _sparkles?.addListener(markNeedsPaint);
    _validForMouseTracker = true;
  }

  @override
  void detach() {
    _transition.removeListener(markNeedsPaint);
    _pressed.removeListener(_handlePress);
    _sparkles?.removeListener(markNeedsPaint);
    _validForMouseTracker = false;
    super.detach();
  }

  @override
  void dispose() {
    _clip.layer = null;
    super.dispose();
  }

  ({Size size, Rect visual, Offset child}) _layout(
    BoxConstraints constraints,
    Size Function(RenderBox child, BoxConstraints constraints) layoutChild,
  ) {
    final outer = _minimum.enforce(constraints);
    final inner = outer.deflate(_padding);
    final child = this.child;
    final childSize = child == null
        ? Size.zero
        : layoutChild(child, _childFills ? inner : inner.loosen());
    final content = inner.constrain(childSize);
    final visual = outer.constrain(
      Size(
        content.width + _padding.horizontal,
        content.height + _padding.vertical,
      ),
    );
    final size = constraints.constrain(
      Size(
        math.max(visual.width, _tapTarget.width),
        math.max(visual.height, _tapTarget.height),
      ),
    );
    final visualOffset = Alignment.center.alongOffset(size - visual as Offset);
    final childOffset =
        visualOffset +
        Offset(_padding.left, _padding.top) +
        Alignment.center.alongOffset(content - childSize as Offset);
    return (size: size, visual: visualOffset & visual, child: childOffset);
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) =>
      _layout(constraints, ChildLayoutHelper.dryLayoutChild).size;

  @override
  double? computeDryBaseline(
    covariant BoxConstraints constraints,
    TextBaseline baseline,
  ) {
    final child = this.child;
    if (child == null) {
      return null;
    }
    final layout = _layout(constraints, ChildLayoutHelper.dryLayoutChild);
    final inner = _minimum.enforce(constraints).deflate(_padding);
    final result = child.getDryBaseline(
      _childFills ? inner : inner.loosen(),
      baseline,
    );
    return result == null ? null : result + layout.child.dy;
  }

  @override
  void performLayout() {
    final layout = _layout(constraints, ChildLayoutHelper.layoutChild);
    size = layout.size;
    _visual = layout.visual;
    if (child case final child?) {
      (child.parentData! as BoxParentData).offset = layout.child;
    }
  }

  double _intrinsic(
    double extent,
    double inset,
    double outerInset,
    double minimum,
    double tapTarget,
    double Function(RenderBox child, double extent) measure,
  ) {
    final child = this.child;
    final content = child == null
        ? 0.0
        : measure(child, math.max(0, extent - outerInset));
    return math.max(math.max(content + inset, minimum), tapTarget);
  }

  @override
  double computeMinIntrinsicWidth(double height) => _intrinsic(
    height,
    _padding.horizontal,
    _padding.vertical,
    _minimum.minWidth,
    _tapTarget.width,
    (child, extent) => child.getMinIntrinsicWidth(extent),
  );

  @override
  double computeMaxIntrinsicWidth(double height) => _intrinsic(
    height,
    _padding.horizontal,
    _padding.vertical,
    _minimum.minWidth,
    _tapTarget.width,
    (child, extent) => child.getMaxIntrinsicWidth(extent),
  );

  @override
  double computeMinIntrinsicHeight(double width) => _intrinsic(
    width,
    _padding.vertical,
    _padding.horizontal,
    _minimum.minHeight,
    _tapTarget.height,
    (child, extent) => child.getMinIntrinsicHeight(extent),
  );

  @override
  double computeMaxIntrinsicHeight(double width) => _intrinsic(
    width,
    _padding.vertical,
    _padding.horizontal,
    _minimum.minHeight,
    _tapTarget.height,
    (child, extent) => child.getMaxIntrinsicHeight(extent),
  );

  static bool _claimsPress(HitTestTarget target) => switch (target) {
    RenderCardSurface(:final interactive) => interactive,
    RenderSemanticsGestureHandler(:final onTap) => onTap != null,
    SemanticsAnnotationsMixin(:final properties) => properties.onTap != null,
    _ => false,
  };

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!size.contains(position)) {
      return false;
    }
    final start = result.path.length;
    if (_visual.contains(position)) {
      hitTestChildren(result, position: position);
    }
    _childClaimed = result.path
        .skip(start)
        .any((entry) => _claimsPress(entry.target));
    result.add(BoxHitTestEntry(this, position));
    return true;
  }

  @override
  void handleEvent(PointerEvent event, BoxHitTestEntry entry) {
    if (event is PointerDownEvent) {
      if (!_childClaimed) {
        onPointerDown?.call(event);
      }
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      onPointerEnd?.call(event);
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (!_tinting) {
      layer = null;
      _paintSurface(context, offset);
      return;
    }
    final press = _pressed.value;
    if (_brightness == Brightness.dark) {
      final lift = _tintLift * press;
      final keep = 1 - lift;
      final white = 255 * lift;
      layer = context.pushColorFilter(
        offset,
        ColorFilter.matrix([
          keep, 0, 0, 0, white, //
          0, keep, 0, 0, white, //
          0, 0, keep, 0, white, //
          0, 0, 0, 1, 0, //
        ]),
        _paintSurface,
        oldLayer: layer is ColorFilterLayer ? layer! as ColorFilterLayer : null,
      );
    } else {
      layer = context.pushOpacity(
        offset,
        Color.getAlphaFromOpacity(1 - _tintFade * press),
        _paintSurface,
        oldLayer: layer is OpacityLayer ? layer! as OpacityLayer : null,
      );
    }
  }

  void _paintSurface(PaintingContext context, Offset offset) {
    final canvas = context.canvas;
    final rect = _visual.shift(offset);
    final progress = _transition.value;
    var fill = Color.lerp(_previousFill, _fill, progress)!;
    if (_hovered && _interactive && _hover.a > 0) {
      fill = Color.alphaBlend(_hover, fill);
    }
    final pressed = _pressed.value;
    if (pressed > 0 && _look == PressLook.ink) {
      fill = Color.alphaBlend(
        _inkColor.withValues(alpha: _inkColor.a * pressed),
        fill,
      );
    }
    if (fill.a > 0) {
      final paint = Paint()..color = fill;
      if (_shape.preferPaintInterior) {
        _shape.paintInterior(
          canvas,
          rect,
          paint,
          textDirection: _textDirection,
        );
      } else {
        canvas.drawPath(
          _shape.getOuterPath(rect, textDirection: _textDirection),
          paint,
        );
      }
    }
    final sparkles = _sparkles;
    if (sparkles != null && !sparkles.isEmpty) {
      canvas
        ..save()
        ..clipPath(_shape.getOuterPath(rect, textDirection: _textDirection));
      sparkles.paint(canvas, rect, offset, _inkColor);
      canvas.restore();
    }
    final side = BorderSide.lerp(_previousSide, _side, progress);
    if (side.style != BorderStyle.none && side.width > 0) {
      _shape
          .copyWith(side: side)
          .paint(canvas, rect, textDirection: _textDirection);
    }
    final child = this.child;
    if (child == null) {
      return;
    }
    final childOffset = (child.parentData! as BoxParentData).offset;
    if (!_clipsChild) {
      _clip.layer = null;
      context.paintChild(child, offset + childOffset);
      return;
    }
    _clip.layer = context.pushClipPath(
      needsCompositing,
      offset,
      Offset.zero & size,
      _shape.getOuterPath(_visual, textDirection: _textDirection),
      (context, offset) => context.paintChild(child, offset + childOffset),
      clipBehavior: Clip.antiAlias,
      oldLayer: _clip.layer,
    );
  }

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    config
      ..isSemanticBoundary = true
      ..isButton = true
      ..isEnabled = _interactive;
    if (_selected) {
      config.isSelected = true;
    }
    if (_interactive && onTap != null) {
      config.onTap = onTap;
    }
  }
}
