import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/widgets.dart';
import 'package:prism_ui/shapes/shapes.dart' as shapes;
import 'package:prism_ui/context.dart';
import 'package:prism_ui/deferred_push.dart';
import 'package:prism_ui/fade_box.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/inherited.dart';
import 'package:prism_ui/l10n.dart';
import 'package:prism_ui/loading.dart';
import 'package:prism_ui/metrics.dart';
import 'package:prism_ui/navigator.dart';
import 'package:prism_ui/theme_data.dart';
import 'package:prism_ui/typography.dart';

/// What an [EmptyIllustration] draws, on a shape and among accent marks it picks
/// at random.
abstract interface class Illustration {
  static const Illustration search = _SearchIllustration();

  Glyph get glyph;

  /// Whether it is drawn in the error colors.
  bool get isError;
}

class _SearchIllustration implements Illustration {
  const _SearchIllustration();

  @override
  Glyph get glyph => Glyphs.search;

  @override
  bool get isError => false;
}

/// Holds the transition of the route it arrives in while its first load runs,
/// as [ArrivalHold] does.
class NullStatusSwitcher extends StatefulWidget {
  /// Only the first load is held back; later loads keep what is on screen.
  final bool isLoading;
  final bool isEmpty;
  final bool isSearching;

  /// Shown in place of a first load still running after a route transition.
  final Widget? loadingStatus;
  final NullStatus? nullStatus;
  final Widget child;

  /// Without it, the first load leaves the push alone and shows
  /// [loadingStatus] at once.
  final bool holdsArrival;

  const NullStatusSwitcher({
    super.key,
    this.isLoading = false,
    this.isEmpty = false,
    this.isSearching = false,
    this.holdsArrival = true,
    this.loadingStatus,
    this.nullStatus,
    required this.child,
  }) : assert(!isEmpty || nullStatus != null);

  @override
  State<NullStatusSwitcher> createState() => _NullStatusSwitcherState();
}

class _NullStatusSwitcherState extends State<NullStatusSwitcher> {
  static const _exitDuration = Duration(milliseconds: 150);
  static const _loadingStatusDelay = Duration(milliseconds: 400);

  late bool _loaded = !widget.isLoading;
  Timer? _loadingStatusTimer;
  late var _showsLoadingStatus = !widget.holdsArrival;

  @override
  void initState() {
    super.initState();
    if (!_loaded && !_showsLoadingStatus && widget.loadingStatus != null) {
      _loadingStatusTimer = Timer(
        _loadingStatusDelay,
        () => setState(() => _showsLoadingStatus = true),
      );
    }
  }

  @override
  void didUpdateWidget(covariant NullStatusSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    _loaded = _loaded || !widget.isLoading;
    if (_loaded) {
      _loadingStatusTimer?.cancel();
    }
  }

  @override
  void dispose() {
    _loadingStatusTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.holdsArrival) {
      return _buildSlot(context);
    }
    return ArrivalHold(ready: _loaded, child: _buildSlot(context));
  }

  Widget _buildSlot(BuildContext context) {
    if (!_loaded && !_showsLoadingStatus) {
      return const SizedBox.expand();
    }
    final slot = switch ((widget.isEmpty, widget.isSearching)) {
      _ when !_loaded => _NullStatusSlot.loading,
      (true, true) => _NullStatusSlot.noResults,
      (true, false) => _NullStatusSlot.empty,
      (false, _) => _NullStatusSlot.content,
    };
    return AnimatedSwitcher(
      duration: context.motionDuration(commonDuration),
      reverseDuration: context.motionDuration(_exitDuration),
      switchInCurve: Easing.emphasizedDecelerate,
      switchOutCurve: Curves.easeIn,
      layoutBuilder: (currentChild, previousChildren) => Align(
        alignment: Alignment.center,
        child: Stack(
          alignment: Alignment.center,
          fit: StackFit.expand,
          children: <Widget>[...previousChildren, ?currentChild],
        ),
      ),
      transitionBuilder: (child, animation) => ActivityPresence(
        animation: animation,
        child: FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: animation.drive(Tween(begin: 0.92, end: 1.0)),
            child: child,
          ),
        ),
      ),
      child: KeyedSubtree(
        key: ValueKey(slot),
        child: switch (slot) {
          _NullStatusSlot.loading => widget.loadingStatus!,
          _NullStatusSlot.noResults => NullStatus(
            label: UiLocalizations.of(context).noSearchResults,
            illustration: Illustration.search,
          ),
          _NullStatusSlot.empty => widget.nullStatus!,
          _NullStatusSlot.content => widget.child,
        },
      ),
    );
  }
}

enum _NullStatusSlot { loading, empty, noResults, content }

class NullStatus extends StatefulWidget {
  final String? label;
  final String? description;
  final Widget? action;
  final Illustration illustration;

  const NullStatus({
    super.key,
    this.label,
    this.description,
    this.action,
    required this.illustration,
  });

  @override
  State<NullStatus> createState() => _NullStatusState();
}

class _NullStatusState extends State<NullStatus> {
  late final ScrollController _controller;

  @override
  void initState() {
    super.initState();
    _controller = sheetScrollController(context);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final NullStatus(:label, :description, :action, :illustration) = widget;
    final colorScheme = context.colorScheme;
    final compact = MediaQuery.sizeOf(context).height < _compactHeight;
    return Align(
      alignment: const Alignment(0.0, -0.2),
      child: SingleChildScrollView(
        controller: _controller,
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _EnterItem(
                child: EmptyIllustration(
                  type: illustration,
                  dimension: EmptyIllustration.dimensionOf(context),
                ),
              ),
              if (label != null) ...[
                SizedBox(height: compact ? 12 : 16),
                _EnterItem(
                  delay: _staggerStep,
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: AppTextStyle.headline
                        .of(context)
                        .copyWith(color: colorScheme.onSurface),
                  ),
                ),
              ],
              if (description != null) ...[
                const SizedBox(height: 8),
                _EnterItem(
                  delay: _staggerStep * 2,
                  child: Text(
                    description,
                    textAlign: TextAlign.center,
                    style: AppTextStyle.subheadline
                        .of(context)
                        .copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                ),
              ],
              if (action != null) ...[
                const SizedBox(height: 24),
                _EnterItem(
                  delay: _staggerStep * (description != null ? 3 : 2),
                  child: Theme(
                    data: Theme.of(
                      context,
                    ).copyWith(visualDensity: VisualDensity.standard),
                    child: action,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

const _compactHeight = 560.0;
const _staggerStep = Duration(milliseconds: 60);
const _enterRise = 12.0;

bool _skipsEntrance(BuildContext context) =>
    context.disableAnimations || isRouteArriving(context);

class _EnterItem extends StatefulWidget {
  final Duration delay;
  final Widget child;

  const _EnterItem({this.delay = Duration.zero, required this.child});

  @override
  State<_EnterItem> createState() => _EnterItemState();
}

class _EnterItemState extends State<_EnterItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool? _skipped;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: commonDuration + widget.delay,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_skipped != null) {
      return;
    }
    _skipped = _skipsEntrance(context);
    if (!_skipped!) {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final skipped = _skipped;
    if (skipped == null || skipped) {
      return widget.child;
    }
    final total = commonDuration + widget.delay;
    final start = widget.delay.inMicroseconds / total.inMicroseconds;
    final animation = start == 0
        ? _controller.view
        : _controller.drive(CurveTween(curve: Interval(start, 1)));
    return FadeSlideEnterTransition(
      animation: animation,
      distance: _enterRise,
      axis: Axis.vertical,
      child: widget.child,
    );
  }
}

class EmptyIllustration extends StatefulWidget {
  final Illustration type;
  final double dimension;

  const EmptyIllustration({
    super.key,
    required this.type,
    required this.dimension,
  });

  static double dimensionOf(BuildContext context) =>
      MediaQuery.sizeOf(context).height < _compactHeight ? 120 : 160;

  @override
  State<EmptyIllustration> createState() => _EmptyIllustrationState();
}

class _EmptyIllustrationState extends State<EmptyIllustration>
    with SingleTickerProviderStateMixin {
  static final _random = math.Random();

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
    value: 1,
  );
  final _entrance = _Entrance.values[_random.nextInt(_Entrance.values.length)];
  final _shape = _shapes[_random.nextInt(_shapes.length)];
  final _layout = _layouts[_random.nextInt(_layouts.length)];
  var _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) {
      return;
    }
    _started = true;
    if (!_skipsEntrance(context)) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final type = widget.type;
    final colorScheme = context.colorScheme;
    return RepaintBoundary(
      child: CustomPaint(
        key: ValueKey(type),
        painter: _IllustrationPainter(
          shape: _shape,
          glyph: type.glyph,
          color: type.isError ? colorScheme.error : colorScheme.primary,
          layout: _layout,
          entrance: _entrance,
          progress: _controller,
        ),
        child: SizedBox.square(dimension: widget.dimension),
      ),
    );
  }
}

/// Every choreography must land on the same final frame, since a skipped
/// entrance paints that frame directly.
enum _Entrance { spin, morph, orbit }

enum _Accent { dot, ring, tile, plus, dash, wave }

typedef _ShapePose = ({double scale, double turn, double morph});
typedef _GlyphPose = ({double scale, double rise, double fill, double alpha});
typedef _AccentPose = ({double scale, double drift, double orbit, double turn});

/// Shapes that leave the glyph a margin all round; a freer one cuts in too close.
final _shapes = [
  shapes.MaterialShapes.circle,
  shapes.MaterialShapes.cookie9Sided,
  shapes.MaterialShapes.cookie12Sided,
  // Inset so its corners do not make it read larger than the others.
  shapes.RoundedPolygon.rectangle(
    width: 0.9,
    height: 0.9,
    rounding: const shapes.CornerRounding(radius: 0.28, smoothing: 1),
    centerX: 0.5,
    centerY: 0.5,
  ),
];

const _layouts = <List<(_Accent, Offset, double, double)>>[
  [
    (_Accent.dot, Offset(-0.42, -0.2), 0.05, 0),
    (_Accent.ring, Offset(0.43, 0.12), 0.075, 0),
    (_Accent.tile, Offset(-0.33, 0.35), 0.12, 0.26),
  ],
  [
    (_Accent.plus, Offset(0.38, -0.36), 0.09, 0),
    (_Accent.dot, Offset(0.46, -0.1), 0.04, 0),
    (_Accent.dash, Offset(-0.4, 0.3), 0.12, -0.8),
    (_Accent.ring, Offset(-0.38, -0.36), 0.06, 0),
  ],
  [
    (_Accent.wave, Offset(-0.38, -0.38), 0.15, 0),
    (_Accent.dot, Offset(0.4, 0.34), 0.06, 0),
    (_Accent.dot, Offset(0.46, 0.18), 0.035, 0),
    (_Accent.plus, Offset(-0.43, 0.2), 0.09, 0.4),
  ],
  [
    (_Accent.ring, Offset(0.37, -0.37), 0.1, 0),
    (_Accent.dash, Offset(0.42, 0.28), 0.1, 1.1),
    (_Accent.dot, Offset(-0.44, -0.05), 0.045, 0),
    (_Accent.tile, Offset(-0.38, 0.36), 0.08, -0.4),
  ],
  [
    (_Accent.tile, Offset(0.38, -0.36), 0.11, 0.4),
    (_Accent.wave, Offset(-0.36, 0.4), 0.16, -0.2),
    (_Accent.dot, Offset(-0.42, -0.28), 0.05, 0),
  ],
  [
    (_Accent.dot, Offset(-0.33, -0.4), 0.07, 0),
    (_Accent.dot, Offset(-0.46, -0.22), 0.035, 0),
    (_Accent.plus, Offset(0.42, 0.3), 0.09, 0.3),
    (_Accent.dash, Offset(0.38, -0.38), 0.11, 0.8),
  ],
  [
    (_Accent.plus, Offset(-0.4, -0.33), 0.1, 0),
    (_Accent.ring, Offset(0.42, 0.33), 0.085, 0),
    (_Accent.wave, Offset(0.36, -0.4), 0.14, 0.2),
    (_Accent.dot, Offset(-0.44, 0.26), 0.04, 0),
  ],
  [
    (_Accent.ring, Offset(-0.36, 0.38), 0.11, 0),
    (_Accent.dot, Offset(0.4, -0.34), 0.06, 0),
    (_Accent.tile, Offset(0.46, -0.12), 0.06, 0.3),
    (_Accent.dash, Offset(-0.44, -0.2), 0.1, 1.4),
  ],
];

class _IllustrationPainter extends CustomPainter {
  static const _shapeExtent = 0.72;
  static const _glyphExtent = 0.4;
  static const _shapeAlpha = 0.15;
  static const _softAccentAlpha = 0.4;
  static final _wave = Path()
    ..moveTo(-0.5, 0)
    ..quadraticBezierTo(-0.25, -0.5, 0, 0)
    ..quadraticBezierTo(0.25, 0.5, 0.5, 0);
  static final _paths = Expando<Path>();
  static final _morphs = Expando<shapes.Morph>();

  final shapes.RoundedPolygon shape;
  final Glyph glyph;
  final Color color;
  final List<(_Accent, Offset, double, double)> layout;
  final _Entrance entrance;
  final Animation<double> progress;

  _IllustrationPainter({
    required this.shape,
    required this.glyph,
    required this.color,
    required this.layout,
    required this.entrance,
    required this.progress,
  }) : super(repaint: progress);

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress.value;
    final side = size.shortestSide;
    final center = size.center(Offset.zero);
    final (body, mark) = _poseAt(t);

    _paintShape(
      canvas,
      body,
      center,
      side * _shapeExtent,
      color.withValues(alpha: color.a * _shapeAlpha),
    );
    if (mark.scale > 0) {
      _paintGlyph(
        canvas,
        glyph,
        center + Offset(0, side * mark.rise),
        side * _glyphExtent * mark.scale,
        mark.fill,
        color.withValues(alpha: color.a * mark.alpha),
      );
    }

    for (final (index, (accent, offset, extent, rest)) in layout.indexed) {
      final pose = _accentAt(t, index, layout.length);
      if (pose.scale <= 0) {
        continue;
      }
      final at =
          center +
          Offset.fromDirection(offset.direction + pose.orbit, offset.distance) *
              side *
              pose.drift;
      canvas.save();
      canvas.translate(at.dx, at.dy);
      canvas.rotate(rest + pose.turn);
      canvas.scale(side * extent * pose.scale);
      _paintAccent(canvas, accent);
      canvas.restore();
    }
  }

  void _paintAccent(Canvas canvas, _Accent accent) {
    final soft = color.withValues(alpha: color.a * _softAccentAlpha);
    Paint stroke(Color color, double width) => Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round;
    switch (accent) {
      case _Accent.dot:
        canvas.drawCircle(Offset.zero, 0.5, Paint()..color = color);
      case _Accent.ring:
        canvas.drawCircle(Offset.zero, 0.36, stroke(color, 0.28));
      case _Accent.tile:
        canvas.drawRSuperellipse(
          RSuperellipse.fromRectAndRadius(
            const Rect.fromLTRB(-0.5, -0.5, 0.5, 0.5),
            const Radius.circular(0.3),
          ),
          Paint()..color = soft,
        );
      case _Accent.plus:
        final paint = stroke(color, 0.26);
        canvas.drawLine(const Offset(-0.37, 0), const Offset(0.37, 0), paint);
        canvas.drawLine(const Offset(0, -0.37), const Offset(0, 0.37), paint);
      case _Accent.dash:
        canvas.drawLine(
          const Offset(-0.38, 0),
          const Offset(0.38, 0),
          stroke(soft, 0.24),
        );
      case _Accent.wave:
        canvas.drawPath(_wave, stroke(soft, 0.2));
    }
  }

  (_ShapePose, _GlyphPose) _poseAt(double t) {
    switch (entrance) {
      case _Entrance.spin:
        _ShapePose spun(double settle) => (
          scale: lerpDouble(0.6, 1, settle)!,
          turn: -math.pi / 3 * (1 - settle),
          morph: 1,
        );
        return (
          spun(_phase(t, 0, 0.65, Curves.easeOutBack)),
          (
            scale:
                lerpDouble(0.5, 1, _phase(t, 0.1, 0.55, Curves.easeOutBack))! +
                math.sin(math.pi * _phase(t, 0.55, 0.85)) * 0.08,
            rise: 0,
            fill: _phase(t, 0.2, 0.6, Curves.easeInOutCubic),
            alpha: _phase(t, 0.1, 0.3),
          ),
        );
      case _Entrance.morph:
        _ShapePose morphed(double begin, double end) {
          final morph = _phase(t, begin, end, Curves.easeInOutCubic);
          return (
            scale: lerpDouble(
              0.5,
              1,
              _phase(t, begin, begin + 0.5, Curves.easeOutBack),
            )!,
            turn: math.pi / 2 * (1 - morph),
            morph: morph,
          );
        }
        final rise = _phase(t, 0.2, 0.6, Curves.easeOutBack);
        return (
          morphed(0.05, 0.65),
          (
            scale: lerpDouble(0.8, 1, rise)!,
            rise: 0.14 * (1 - rise),
            fill: _phase(t, 0.3, 0.7, Curves.easeInOutCubic),
            alpha: _phase(t, 0.2, 0.35),
          ),
        );
      case _Entrance.orbit:
        return (
          (
            scale: lerpDouble(
              0.3,
              1,
              _phase(t, 0, 0.6, const ElasticOutCurve(0.6)),
            )!,
            turn: 0,
            morph: 1,
          ),
          (
            scale: _phase(t, 0.15, 0.7, const ElasticOutCurve(0.5)),
            rise: 0,
            fill: _phase(t, 0.3, 0.7, Curves.easeInOutCubic),
            alpha: _phase(t, 0.15, 0.25),
          ),
        );
    }
  }

  _AccentPose _accentAt(double t, int index, int count) {
    switch (entrance) {
      case _Entrance.spin:
        final begin = 0.4 + index * 0.08;
        final enter = _phase(t, begin, begin + 0.35, Curves.easeOutBack);
        return (
          scale: enter,
          drift: lerpDouble(0.7, 1, enter)!,
          orbit: 0,
          turn: -math.pi / 4 * (1 - enter),
        );
      case _Entrance.morph:
        final begin = 0.45 + (count - 1 - index) * 0.07;
        final enter = _phase(t, begin, begin + 0.3, Curves.easeOutBack);
        return (
          scale: enter,
          drift: 1,
          orbit: 0,
          turn: -math.pi / 2 * (1 - enter),
        );
      case _Entrance.orbit:
        final begin = 0.3 + index * 0.1;
        final travel = _phase(t, begin, begin + 0.4, Curves.easeOutCubic);
        return (
          scale: _phase(t, begin, begin + 0.3, Curves.easeOutBack),
          drift: lerpDouble(0.55, 1, travel)!,
          orbit: -math.pi * 0.7 * (1 - travel),
          turn: -math.pi / 2 * (1 - travel),
        );
    }
  }

  static double _phase(
    double t,
    double begin,
    double end, [
    Curve curve = Curves.linear,
  ]) => curve.transform(((t - begin) / (end - begin)).clamp(0.0, 1.0));

  void _paintShape(
    Canvas canvas,
    _ShapePose pose,
    Offset center,
    double extent,
    Color color,
  ) {
    final path = pose.morph >= 1
        ? _paths[shape] ??= shape.toPath()
        : (_morphs[shape] ??= shapes.Morph(
            shapes.MaterialShapes.circle,
            shape,
          )).toPath(progress: pose.morph);
    _paintPath(canvas, path, center, extent * pose.scale, pose.turn, color);
  }

  void _paintPath(
    Canvas canvas,
    Path path,
    Offset center,
    double extent,
    double rotation,
    Color color,
  ) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rotation);
    canvas.scale(extent);
    canvas.translate(-0.5, -0.5);
    canvas.drawPath(path, Paint()..color = color);
    canvas.restore();
  }

  void _paintGlyph(
    Canvas canvas,
    Glyph glyph,
    Offset center,
    double extent,
    double fill,
    Color color,
  ) {
    canvas.save();
    canvas.translate(center.dx - extent / 2, center.dy - extent / 2);
    GlyphPainter(
      glyph: glyph,
      fill: fill,
      color: color,
    ).paint(canvas, Size.square(extent));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _IllustrationPainter oldDelegate) =>
      oldDelegate.shape != shape ||
      oldDelegate.glyph != glyph ||
      oldDelegate.color != color ||
      oldDelegate.layout != layout ||
      oldDelegate.entrance != entrance ||
      oldDelegate.progress != progress;
}
