import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/physics.dart';

enum MorphingMenuMotionStyle { toolbar, list }

/// Independent values sampled from the route's clock, not its clamped value.
class MorphingMenuFrame {
  const MorphingMenuFrame({
    required this.size,
    required this.position,
    required this.reveal,
    required this.clarity,
  });

  static const closed = MorphingMenuFrame(
    size: 0,
    position: 0,
    reveal: 0,
    clarity: 0,
  );
  static const open = MorphingMenuFrame(
    size: 1,
    position: 1,
    reveal: 1,
    clarity: 1,
  );

  final double size;
  final double position;
  final double reveal;
  final double clarity;

  // Transfer the icon only when the moving surface reaches its source. Size
  // alone finishes too early on closing: the center is still travelling home.
  double get surfaceOpacity =>
      (math.max(size, position) / 0.08).clamp(0.0, 1.0);

  double get contentOpacity => ((reveal - 0.2) / 0.8).clamp(0.0, 1.0);

  double get sourceOpacity => (1 - reveal) * (1 - (size / 0.5).clamp(0.0, 1.0));

  double get contentBlur => 18 * math.pow(1 - clarity, 3).toDouble();
}

/// The route stays alive until both springs and the content handoff finish.
/// Its bounded animation value only drives ticks; geometry keeps the springs'
/// small overshoot and can reverse with each property's current velocity.
class MorphingMenuSimulation extends Simulation {
  MorphingMenuSimulation({
    required this.forward,
    required this.from,
    required this.style,
    double sizeVelocity = 0,
    double positionVelocity = 0,
  }) : size = _spring(
         response: style == MorphingMenuMotionStyle.toolbar
             ? (forward ? 0.40 : 0.22)
             : 0.25,
         dampingRatio: style == MorphingMenuMotionStyle.toolbar ? 0.82 : 0.92,
         start: from.size,
         end: forward ? 1 : 0,
         velocity: sizeVelocity,
       ),
       _position = style == MorphingMenuMotionStyle.toolbar
           ? _spring(
               response: forward ? 0.25 : 0.35,
               dampingRatio: 0.82,
               start: from.position,
               end: forward ? 1 : 0,
               velocity: positionVelocity,
             )
           : null;

  final bool forward;
  final MorphingMenuFrame from;
  final MorphingMenuMotionStyle style;
  final SpringSimulation size;
  final SpringSimulation? _position;
  SpringSimulation get position => _position ?? size;

  double get _end => forward ? 1 : 0;
  double get _revealDuration =>
      (style == MorphingMenuMotionStyle.toolbar ? (forward ? 0.08 : 0.20) : 0) *
      (_end - from.reveal).abs();
  double get _clarityDuration =>
      (style == MorphingMenuMotionStyle.toolbar ? (forward ? 0.20 : 0.08) : 0) *
      (_end - from.clarity).abs();

  static SpringSimulation _spring({
    required double response,
    required double dampingRatio,
    required double start,
    required double end,
    required double velocity,
  }) {
    final omega = 2 * math.pi / response;
    return SpringSimulation(
      SpringDescription(
        mass: 1,
        stiffness: omega * omega,
        damping: 2 * dampingRatio * omega,
      ),
      start,
      end,
      velocity,
      snapToEnd: true,
      tolerance: const Tolerance(distance: 0.0005, velocity: 0.01),
    );
  }

  double _effect(double start, double time, double duration) => lerpDouble(
    start,
    _end,
    duration == 0 ? 1 : (time / duration).clamp(0.0, 1.0),
  )!;

  MorphingMenuFrame frame(double time) => MorphingMenuFrame(
    size: size.x(time),
    position: _position?.x(time) ?? size.x(time),
    reveal: style == MorphingMenuMotionStyle.toolbar
        ? _effect(from.reveal, time, _revealDuration)
        : size.x(time),
    clarity: style == MorphingMenuMotionStyle.toolbar
        ? _effect(from.clarity, time, _clarityDuration)
        : 1,
  );

  @override
  double x(double time) =>
      _position == null ? size.x(time) : (size.x(time) + _position.x(time)) / 2;

  @override
  double dx(double time) => _position == null
      ? size.dx(time)
      : (size.dx(time) + _position.dx(time)) / 2;

  @override
  bool isDone(double time) =>
      size.isDone(time) &&
      (_position?.isDone(time) ?? true) &&
      time >= _revealDuration &&
      time >= _clarityDuration;
}
