import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// 复用 Slider 的按压动画，缩放不受 seek 完成时机影响。
class PlayerSliderThumbShape extends SliderComponentShape {
  const PlayerSliderThumbShape({required this.disableAnimations});

  final bool disableAnimations;

  static const _restingRadius = 2.5;
  static const _activeRadius = 7.0;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) {
    // 始终预留最大尺寸，避免动画改变轨道端点与进度映射。
    return const Size.fromRadius(_activeRadius);
  }

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final activation = disableAnimations
        ? switch (activationAnimation.status) {
            AnimationStatus.forward || AnimationStatus.completed => 1.0,
            AnimationStatus.reverse || AnimationStatus.dismissed => 0.0,
          }
        : activationAnimation.value;
    final radius = ui.lerpDouble(
      _restingRadius,
      _activeRadius,
      activation * enableAnimation.value,
    )!;
    final color = Color.lerp(
      sliderTheme.disabledThumbColor,
      sliderTheme.thumbColor,
      enableAnimation.value,
    )!;
    context.canvas.drawCircle(center, radius, Paint()..color = color);
  }
}
