import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

/// Sparkles sent out from where presses landed on a surface, or from its
/// center for a key, drawn and timed as Material's InkSparkle.
class PressSparkles extends ChangeNotifier {
  static const _shaderAsset = 'packages/prism_ui/shaders/ink_sparkle.frag';
  static ui.FragmentProgram? _program;
  static Future<void>? _loading;

  final _random = math.Random();
  final _sparkles = <_Sparkle>[];

  bool get isEmpty => _sparkles.isEmpty;

  void start(
    Offset? origin, {
    required TickerProvider vsync,
    required Duration Function(Duration duration) timing,
  }) {
    _loading ??= ui.FragmentProgram.fromAsset(_shaderAsset).then(
      (program) => _program = program,
      onError: (Object error, StackTrace stack) => FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'prism_ui',
        ),
      ),
    );
    final sparkle = _Sparkle(
      origin: origin,
      seed: _random.nextDouble() * 1000,
      vsync: vsync,
      duration: timing(_Sparkle.duration),
      onChanged: notifyListeners,
    );
    _sparkles.add(sparkle);
    sparkle.run(() => _remove(sparkle));
  }

  void clear() {
    if (_sparkles.isEmpty) {
      return;
    }
    for (final sparkle in _sparkles) {
      sparkle.dispose();
    }
    _sparkles.clear();
    notifyListeners();
  }

  void _remove(_Sparkle sparkle) {
    if (_sparkles.remove(sparkle)) {
      sparkle.dispose();
      notifyListeners();
    }
  }

  /// Paints the sparkles over [rect], with origins measured from [boxOrigin],
  /// once the shader has loaded.
  void paint(Canvas canvas, Rect rect, Offset boxOrigin, Color color) {
    final program = _program;
    if (program == null) {
      return;
    }
    canvas
      ..save()
      ..translate(rect.left, rect.top);
    for (final sparkle in _sparkles) {
      sparkle.paint(
        canvas,
        program,
        rect.size,
        boxOrigin - rect.topLeft,
        color,
      );
    }
    canvas.restore();
  }

  @override
  void dispose() {
    for (final sparkle in _sparkles) {
      sparkle.dispose();
    }
    _sparkles.clear();
    super.dispose();
  }
}

class _Sparkle {
  _Sparkle({
    required this.origin,
    required this.seed,
    required TickerProvider vsync,
    required Duration duration,
    required VoidCallback onChanged,
  }) : _motion = AnimationController(vsync: vsync, duration: duration) {
    _motion.addListener(onChanged);
  }

  static const duration = Duration(milliseconds: 617);
  static const _radiusMultiplier = 2.3;
  static const _rotateRight = math.pi * 0.0078125;
  static const _noiseDensity = 2.1;
  static const _turbulenceScale = 1.5;

  static final _radiusScale = TweenSequence<double>([
    TweenSequenceItem(
      tween: CurveTween(curve: Curves.fastOutSlowIn),
      weight: 75,
    ),
    TweenSequenceItem(tween: ConstantTween(1), weight: 25),
  ]);
  static final _alpha = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 0, end: 1), weight: 13),
    TweenSequenceItem(tween: ConstantTween(1), weight: 27),
    TweenSequenceItem(tween: Tween(begin: 1, end: 0), weight: 60),
  ]);
  static final _sparkleAlpha = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 0, end: 1), weight: 13),
    TweenSequenceItem(tween: ConstantTween(1), weight: 27),
    TweenSequenceItem(tween: Tween(begin: 1, end: 0), weight: 50),
  ]);

  final Offset? origin;
  final double seed;
  final AnimationController _motion;
  ui.FragmentShader? _shader;

  void run(VoidCallback onDone) {
    _motion
      ..addStatusListener((status) {
        if (status.isCompleted) {
          onDone();
        }
      })
      ..forward();
  }

  void paint(
    Canvas canvas,
    ui.FragmentProgram program,
    Size size,
    Offset originShift,
    Color color,
  ) {
    if (size.isEmpty) {
      return;
    }
    final progress = _motion.value;
    final radiusScale = _radiusScale.transform(progress);
    final middle = size.center(Offset.zero);
    final center = switch (origin) {
      final origin? => Offset.lerp(
        origin + originShift,
        middle,
        math.min(radiusScale * 2, 1),
      )!,
      null => middle,
    };
    final phase = seed + radiusScale;
    final rotations = [
      phase * _rotateRight + 1.7 * math.pi,
      phase * -_rotateRight + 2 * math.pi,
      phase * _rotateRight + 2.75 * math.pi,
    ];
    const scale = _turbulenceScale;
    final shader = _shader ??= program.fragmentShader();
    var index = 0;
    void set(double value) => shader.setFloat(index++, value);
    set(color.r);
    set(color.g);
    set(color.b);
    set(color.a);
    set(_alpha.transform(progress));
    set(_sparkleAlpha.transform(progress));
    set(1);
    set(radiusScale);
    set(center.dx);
    set(center.dy);
    set(Offset(size.width, size.height).distance / 2 * _radiusMultiplier);
    set(1 / size.width);
    set(1 / size.height);
    set(_noiseDensity / size.width);
    set(_noiseDensity / size.height);
    set(phase / 1000);
    set(scale * 0.5 + phase * 0.01 * math.cos(scale * 0.55));
    set(scale * 0.5 + phase * 0.01 * math.sin(scale * 0.55));
    set(scale * 0.2 + phase * -0.0066 * math.cos(scale * 0.45));
    set(scale * 0.2 + phase * -0.0066 * math.sin(scale * 0.45));
    set(scale + phase * -0.0066 * math.cos(scale * 0.35));
    set(scale + phase * -0.0066 * math.sin(scale * 0.35));
    for (final rotation in rotations) {
      set(math.cos(rotation));
      set(math.sin(rotation));
    }
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  void dispose() {
    _motion.dispose();
    _shader?.dispose();
  }
}
