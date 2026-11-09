import 'package:flutter/widgets.dart';
import 'package:prism_ui/typography.dart';
import 'package:prism_ui/context.dart';
import 'package:flutter/rendering.dart';
import 'package:prism_ui/theme_data.dart';
import 'package:prism_ui/color.dart';

/// `.agents/surfaces.md` explains the levels and why dark mode never steps
/// back down.
enum SurfaceLevel {
  page,
  card,
  block,
  inset;

  static SurfaceLevel floatingOf(ColorScheme colorScheme) =>
      colorScheme.brightness == Brightness.dark ? block : card;

  SurfaceLevel get next => switch (this) {
    page => card,
    card => block,
    block || inset => inset,
  };

  Color colorOf(ColorScheme colorScheme) {
    final dark = colorScheme.brightness == Brightness.dark;
    return switch (this) {
      page => dark ? colorScheme.surface : colorScheme.surfaceContainer,
      card => dark ? colorScheme.surfaceContainer : colorScheme.surfaceBright,
      block =>
        dark ? colorScheme.surfaceContainerHigh : colorScheme.surfaceContainer,
      inset => colorScheme.surfaceContainerHighest,
    };
  }
}

class SurfaceScope extends StatelessWidget {
  const SurfaceScope({super.key, required this.level, required this.child});

  final SurfaceLevel level;
  final Widget child;

  static SurfaceLevel of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_SurfaceLevelScope>()?.level ??
      SurfaceLevel.page;

  @override
  Widget build(BuildContext context) {
    return _SurfaceLevelScope(level: level, child: child);
  }
}

class _SurfaceLevelScope extends InheritedWidget {
  const _SurfaceLevelScope({required this.level, required super.child});

  final SurfaceLevel level;

  @override
  bool updateShouldNotify(_SurfaceLevelScope oldWidget) =>
      level != oldWidget.level;
}

extension SurfaceContext on BuildContext {
  SurfaceLevel get surfaceLevel => SurfaceScope.of(this);

  SurfaceLevel get raisedSurfaceLevel => surfaceLevel.next;
}

extension ChromeSurfaceExt on ColorScheme {
  Color get chromeSurface => brightness == Brightness.dark
      ? surfaceContainerLow
      : surfaceContainerHighest;
}

extension ElevatedSurfaceExt on ColorScheme {
  ColorScheme get elevated {
    if (brightness != Brightness.dark) {
      return this;
    }
    final lift = surfaceContainer.tone - surface.tone;
    Color raise(Color color) => color.shiftTone(lift);
    return copyWith(
      surface: surfaceContainer,
      surfaceDim: raise(surfaceDim),
      surfaceBright: raise(surfaceBright),
      surfaceContainerLowest: raise(surfaceContainerLowest),
      surfaceContainerLow: raise(surfaceContainerLow),
      surfaceContainer: surfaceContainerHigh,
      surfaceContainerHigh: surfaceContainerHighest,
      surfaceContainerHighest: surfaceContainerHighest.shiftTone(
        surfaceContainerHighest.tone - surfaceContainerHigh.tone,
      ),
    );
  }
}

class ElevatedSurfaceTheme extends StatelessWidget {
  const ElevatedSurfaceTheme({super.key, required this.child});

  final Widget child;

  static bool isIn(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_ElevatedSurfaceScope>() != null;

  @override
  Widget build(BuildContext context) {
    return _ElevatedSurfaceScope(
      child: Theme(data: Theme.of(context).elevated, child: child),
    );
  }
}

class _ElevatedSurfaceScope extends InheritedWidget {
  const _ElevatedSurfaceScope({required super.child});

  @override
  bool updateShouldNotify(_ElevatedSurfaceScope oldWidget) => false;
}

extension AppSurfaceThemeExt on ThemeData {
  ThemeData get elevated {
    final scheme = elevatedColorScheme;
    return scheme == null ? this : copyWith(colorScheme: scheme);
  }
}

/// The focus ring of `.agents/surfaces.md`; one that [standsOff] clears the
/// edge, which a primary fill or a button's own glass would hide it on.
const _focusRingWidth = 2.0;
const _focusRingGap = 1.0;

BorderSide focusRingSide(ColorScheme colorScheme, {bool standsOff = false}) =>
    BorderSide(
      color: colorScheme.primary,
      width: _focusRingWidth,
      strokeAlign: standsOff
          ? 1 + 2 * _focusRingGap / _focusRingWidth
          : BorderSide.strokeAlignInside,
    );

/// [focusRingSide] on [shape] while focus is in [child], for ink not a button.
class FocusRing extends StatefulWidget {
  const FocusRing({
    super.key,
    required this.shape,
    this.standsOff = false,
    required this.child,
  });

  final OutlinedBorder shape;
  final bool standsOff;
  final Widget child;

  @override
  State<FocusRing> createState() => _FocusRingState();
}

class _FocusRingState extends State<FocusRing> {
  var _focused = false;

  void _handleFocusChange(bool focused) {
    if (focused != _focused) {
      setState(() => _focused = focused);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      includeSemantics: false,
      onFocusChange: _handleFocusChange,
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: ShapeDecoration(
          shape: widget.shape.copyWith(
            side: _focused
                ? focusRingSide(
                    Theme.of(context).colorScheme,
                    standsOff: widget.standsOff,
                  )
                : BorderSide.none,
          ),
        ),
        child: widget.child,
      ),
    );
  }
}

/// A fill that holds what lands on it: it paints [color] in [shape] with its
/// shadow, sets the text style beneath it, and takes the hits nothing on it does.
class Surface extends StatelessWidget {
  const Surface({
    super.key,
    this.color = const Color(0x00000000),
    this.shape,
    this.clipBehavior = Clip.none,
    this.elevation = 0,
    this.shadowColor,
    this.textStyle,
    required this.child,
  }) : _absorbsHits = true;

  /// Paints nothing but [shape]'s side, and lets hits through.
  const Surface.transparent({
    super.key,
    this.shape,
    this.clipBehavior = Clip.none,
    this.textStyle,
    required this.child,
  }) : color = null,
       elevation = 0,
       shadowColor = null,
       _absorbsHits = false;

  final Color? color;
  final ShapeBorder? shape;
  final Clip clipBehavior;
  final double elevation;
  final Color? shadowColor;
  final TextStyle? textStyle;
  final bool _absorbsHits;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final textDirection = Directionality.maybeOf(context);
    Widget contents = DefaultTextStyle(
      style: textStyle ?? AppTextStyle.subheadline.of(context),
      child: child,
    );
    if (_absorbsHits) {
      contents = _HitAbsorber(child: contents);
    }
    final shape = this.shape;
    if (shape != null) {
      contents = CustomPaint(
        foregroundPainter: _ShapeSidePainter(shape, textDirection),
        child: contents,
      );
    }
    final color = this.color;
    if (color == null) {
      return shape == null || clipBehavior == Clip.none
          ? contents
          : ClipPath(
              clipper: ShapeBorderClipper(
                shape: shape,
                textDirection: textDirection,
              ),
              clipBehavior: clipBehavior,
              child: contents,
            );
    }
    final shadow = shadowColor ?? context.colorScheme.shadow;
    if (shape == null) {
      return PhysicalModel(
        clipBehavior: clipBehavior,
        elevation: elevation,
        color: color,
        shadowColor: shadow,
        child: contents,
      );
    }
    return PhysicalShape(
      clipper: ShapeBorderClipper(shape: shape, textDirection: textDirection),
      clipBehavior: clipBehavior,
      elevation: elevation,
      color: color,
      shadowColor: shadow,
      child: contents,
    );
  }
}

class _HitAbsorber extends SingleChildRenderObjectWidget {
  const _HitAbsorber({required Widget super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderHitAbsorber();
}

class _RenderHitAbsorber extends RenderProxyBox {
  @override
  bool hitTestSelf(Offset position) => true;
}

class _ShapeSidePainter extends CustomPainter {
  const _ShapeSidePainter(this.shape, this.textDirection);

  final ShapeBorder shape;
  final TextDirection? textDirection;

  @override
  void paint(Canvas canvas, Size size) {
    shape.paint(canvas, Offset.zero & size, textDirection: textDirection);
  }

  @override
  bool shouldRepaint(_ShapeSidePainter oldDelegate) =>
      oldDelegate.shape != shape || oldDelegate.textDirection != textDirection;
}
