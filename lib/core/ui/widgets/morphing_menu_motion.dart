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
    this.surface = 1,
    this.source = 0,
    this.shrink = 1,
  });

  static const closed = MorphingMenuFrame(
    size: 0,
    position: 0,
    reveal: 0,
    clarity: 0,
    surface: 0,
    source: 1,
    shrink: 0,
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
  final double surface;
  final double source;
  final double shrink;

  // Transfer the icon only when the moving surface reaches its source. Size
  // alone finishes too early on closing: the center is still travelling home.
  double get surfaceOpacity =>
      (math.max(size, position) / 0.08).clamp(0.0, 1.0);

  double get contentOpacity => ((reveal - 0.2) / 0.8).clamp(0.0, 1.0);

  double get sourceOpacity => (1 - reveal) * (1 - (size / 0.5).clamp(0.0, 1.0));

  double get contentBlur => 18 * math.pow(1 - clarity, 3).toDouble();
}

/// Toolbar motion keeps its free springs. Weather's source-content branch uses
/// finite, normalized spring curves and an independent 140 + 80ms exit handoff.
class MorphingMenuSimulation extends Simulation {
  MorphingMenuSimulation({
    required this.forward,
    required this.from,
    required this.style,
    double sizeVelocity = 0,
    double positionVelocity = 0,
  }) : size = style == MorphingMenuMotionStyle.list
           ? _WeatherGeometry(
               response: forward ? 0.40 : 0.28,
               duration: forward ? 0.617 : 0.140,
               start: from.size,
               end: forward ? 1 : 0,
             )
           : _spring(
               response: forward ? 0.40 : 0.22,
               dampingRatio: 0.82,
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
           : _WeatherGeometry(
               response: forward ? 0.25 : 0.40,
               duration: forward ? 0.386 : 0.600,
               start: from.position,
               end: forward ? 1 : 0,
             ),
       _shrink = style == MorphingMenuMotionStyle.list
           ? _spring(
               response: 0.25,
               dampingRatio: 0.92,
               start: from.shrink,
               end: forward ? 1 : 0,
               velocity: 0,
             )
           : null;

  final bool forward;
  final MorphingMenuFrame from;
  final MorphingMenuMotionStyle style;
  final Simulation size;
  final Simulation _position;
  final SpringSimulation? _shrink;
  Simulation get position => _position;
  double _lastTime = 0;
  double _geometryTime = 0;

  // gHa caps only geometry's frame delta; the content timers use wall time.
  double _sampleGeometry(double time) {
    if (time > _lastTime) {
      _geometryTime += math.min(time - _lastTime, 0.016667);
      _lastTime = time;
    }
    return _geometryTime;
  }

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
    bool snapToEnd = true,
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
      snapToEnd: snapToEnd,
      tolerance: const Tolerance(distance: 0.0005, velocity: 0.01),
    );
  }

  double _effect(double start, double time, double duration) => lerpDouble(
    start,
    _end,
    duration == 0 ? 1 : (time / duration).clamp(0.0, 1.0),
  )!;

  MorphingMenuFrame frame(double time) {
    if (style == MorphingMenuMotionStyle.toolbar) {
      return MorphingMenuFrame(
        size: size.x(time),
        position: position.x(time),
        reveal: _effect(from.reveal, time, _revealDuration),
        clarity: _effect(from.clarity, time, _clarityDuration),
      );
    }
    final geometryTime = _sampleGeometry(time);
    final reveal = _effect(
      from.reveal,
      math.max(0, time - (forward ? 0.050 : 0)),
      0.080,
    );
    return MorphingMenuFrame(
      size: size.x(geometryTime),
      position: position.x(geometryTime),
      reveal: reveal,
      clarity: _effect(from.clarity, time, 0.080),
      surface: forward
          ? 1
          : from.surface * (1 - ((time - 0.140) / 0.080).clamp(0.0, 1.0)),
      source: forward
          ? from.source * (1 - (time / 0.080).clamp(0.0, 1.0))
          : lerpDouble(
              from.source,
              1,
              ((time - 0.060) / 0.060).clamp(0.0, 1.0),
            )!,
      shrink: _shrink!.x(time).clamp(0.0, 1.0),
    );
  }

  @override
  double x(double time) {
    if (style == MorphingMenuMotionStyle.toolbar) {
      return (size.x(time) + position.x(time)) / 2;
    }
    _sampleGeometry(time);
    // This bounded value is just the route clock, never the geometry progress.
    final progress = (time / (forward ? 0.617 : 0.220)).clamp(0.0, 1.0);
    return forward ? progress : 1 - progress;
  }

  @override
  double dx(double time) => style == MorphingMenuMotionStyle.toolbar
      ? (size.dx(time) + position.dx(time)) / 2
      : (forward ? 1 / 0.617 : -1 / 0.220);

  @override
  bool isDone(double time) => style == MorphingMenuMotionStyle.list
      ? (forward ? size.isDone(_sampleGeometry(time)) : time >= 0.220)
      : size.isDone(time) &&
            position.isDone(time) &&
            time >= _revealDuration &&
            time >= _clarityDuration;
}

/// qEa: normalize a zero-velocity unit spring at its finite end time. Response
/// controls its shape; duration independently controls when it reaches 1.
class _WeatherGeometry extends Simulation {
  _WeatherGeometry({
    required double response,
    required this.duration,
    required this.start,
    required this.end,
  }) : _unit = MorphingMenuSimulation._spring(
         response: response,
         dampingRatio: 0.8,
         start: 0,
         end: 1,
         velocity: 0,
         snapToEnd: false,
       );

  final double duration;
  final double start;
  final double end;
  final SpringSimulation _unit;

  @override
  double x(double time) {
    if (time <= 0) return start;
    if (time >= duration) return end;
    return lerpDouble(start, end, _unit.x(time) / _unit.x(duration))!;
  }

  @override
  double dx(double time) =>
      time >= duration ? 0 : (end - start) * _unit.dx(time) / _unit.x(duration);

  @override
  bool isDone(double time) => time >= duration;
}
