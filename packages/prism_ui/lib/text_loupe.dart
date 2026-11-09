import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/physics.dart' show SpringDescription, SpringSimulation;
import 'package:flutter/widgets.dart';
import 'package:prism_ui/context.dart';
import 'package:prism_ui/text_selection_controls.dart';
import 'package:prism_ui/shape.dart';

// Measured on iOS 27.
const _loupeSize = Size(115, 85);
const _loupeGapAboveLineCenter = 75.0;
const _loupeEdgePadding = 8.0;
const _loupeMaxGrowth = 1.2;
const _loupeOutDuration = Duration(milliseconds: 276);
const _loupeGrowSpring = SpringDescription(mass: 1, stiffness: 70, damping: 10);
const _loupeFollowSpring = SpringDescription(
  mass: 1,
  stiffness: 506,
  damping: 37.8,
);

final textLoupeConfiguration = TextMagnifierConfiguration(
  magnifierBuilder: (context, controller, magnifierInfo) => isDesktopPlatform
      ? null
      : TextLoupe(controller: controller, magnifierInfo: magnifierInfo),
);

/// An iOS-style text loupe for a [MagnifierBuilder]. [MagnifierController.hide]
/// plays it back into the caret before the overlay entry goes.
class TextLoupe extends StatefulWidget {
  final MagnifierController controller;
  final ValueListenable<MagnifierInfo> magnifierInfo;

  const TextLoupe({
    super.key,
    required this.controller,
    required this.magnifierInfo,
  });

  @override
  State<TextLoupe> createState() => _TextLoupeState();
}

class _TextLoupeState extends State<TextLoupe> with TickerProviderStateMixin {
  late final AnimationController _grow;
  late final AnimationController _x;
  double? _targetX;

  @override
  void initState() {
    super.initState();
    _grow = AnimationController(
      vsync: this,
      upperBound: _loupeMaxGrowth,
      reverseDuration: _loupeOutDuration,
    );
    _x = AnimationController.unbounded(vsync: this);
    _growIn();
    widget.controller.animationController = _grow;
    widget.magnifierInfo.addListener(_onInfoChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _follow();
  }

  @override
  void didUpdateWidget(TextLoupe oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.magnifierInfo != widget.magnifierInfo) {
      oldWidget.magnifierInfo.removeListener(_onInfoChanged);
      widget.magnifierInfo.addListener(_onInfoChanged);
      _follow();
    }
  }

  @override
  void dispose() {
    widget.magnifierInfo.removeListener(_onInfoChanged);
    if (widget.controller.animationController == _grow) {
      widget.controller.animationController = null;
    }
    _x.dispose();
    _grow.dispose();
    super.dispose();
  }

  void _growIn() {
    _grow.animateWith(
      SpringSimulation(_loupeGrowSpring, _grow.value, 1, _grow.velocity),
    );
  }

  void _onInfoChanged() {
    if (!widget.controller.shown) {
      _growIn();
    }
    _follow();
    setState(() {});
  }

  void _follow() {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final inset = _loupeEdgePadding + _loupeSize.width / 2;
    final double target = widget.magnifierInfo.value.globalGesturePosition.dx
        .clamp(inset, math.max(inset, screenWidth - inset));
    if (_targetX == null) {
      _x.value = target;
    } else if (_targetX != target) {
      _x.animateWith(
        SpringSimulation(_loupeFollowSpring, _x.value, target, _x.velocity),
      );
    }
    _targetX = target;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final caret = widget.magnifierInfo.value.caretRect;
    return AnimatedBuilder(
      animation: Listenable.merge([_grow, _x]),
      builder: (context, _) {
        final t = _grow.value;
        final travel = math.min(t, 1.0);
        final size = Size.lerp(caret.size, _loupeSize, t)!;
        final gap = _loupeGapAboveLineCenter * travel;
        final center = Offset(
          caret.center.dx + (_x.value - caret.center.dx) * travel,
          caret.center.dy - gap,
        );
        return Positioned(
          left: center.dx - size.width / 2,
          top: center.dy - size.height / 2,
          child: RawMagnifier(
            size: size,
            magnificationScale: 1.25,
            focalPointOffset: Offset(0, gap),
            decoration: MagnifierDecoration(
              opacity: math.min(t * 2, 1),
              shape: AppShape.full.copyWith(
                side: BorderSide(
                  color: colorScheme.onSurface.withValues(alpha: 0.08),
                ),
              ),
              shadows: const [
                BoxShadow(
                  color: Color.fromARGB(15, 0, 0, 0),
                  blurRadius: 12,
                  blurStyle: BlurStyle.outer,
                ),
              ],
            ),
            child: const ColoredBox(color: Color(0x0AFFFFFF)),
          ),
        );
      },
    );
  }
}
