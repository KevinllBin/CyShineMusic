import 'package:flutter/animation.dart';

class AppMotion {
  const AppMotion._();

  static const Curve emphasized = Cubic(0.2, 0, 0, 1);
  static const Curve emphasizedDecelerate = Cubic(0.05, 0.7, 0.1, 1);
  static const Curve emphasizedAccelerate = Cubic(0.3, 0, 0.8, 0.15);

  // 大幅页面展开/收回留出起步和落地时间，封面 Hero 与页面共用。
  static const Curve containerTransform = Cubic(0.42, 0, 0.22, 1);
  static const Duration containerTransformDuration = Duration(
    milliseconds: 350,
  );

  static const Duration short = Duration(milliseconds: 180);
  static const Duration medium = Duration(milliseconds: 300);
  static const Duration long = Duration(milliseconds: 500);

  static const SpringDescription standardSpring = SpringDescription(
    mass: 1,
    stiffness: 540,
    damping: 36,
  );

  static const SpringDescription expressiveSpring = SpringDescription(
    mass: 1,
    stiffness: 420,
    damping: 24,
  );
}
