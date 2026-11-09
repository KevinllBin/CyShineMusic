import 'package:flutter/widgets.dart';
import 'package:prism_ui/bar_item_presence.dart';
import 'package:prism_ui/context.dart';
import 'package:prism_ui/inherited.dart';
import 'package:prism_ui/liquid_glass.dart';
import 'package:prism_ui/navigation_dock.dart';
import 'package:prism_ui/shape.dart';
import 'package:prism_ui/surface.dart';

/// Floats [bar] over the foot of [body] as a sheet's docked search floats,
/// in the dock's fill and shadow or its glass, and lets [body] scroll clear
/// of it.
class FloatingFootBar extends StatelessWidget {
  const FloatingFootBar({super.key, required this.bar, required this.body});

  final Widget bar;
  final Widget body;

  static const _margin = BottomInsetScope.dockedSearchMargin;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final level = SurfaceLevel.floatingOf(colorScheme);
    final content = SurfaceScope(
      level: level,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: BottomInsetScope.dockedSearchHeight,
        ),
        child: bar,
      ),
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        BottomInsetScope(
          inset:
              BottomInsetScope.of(context) + BottomInsetScope.dockedSearchInset,
          child: body,
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: BarItemPresence.foot(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                _margin,
                0,
                _margin,
                _margin + context.bottomInset,
              ),
              child: LiquidGlassScope.of(context)
                  ? LiquidGlass(
                      style: LiquidGlassStyle.pill(colorScheme),
                      child: content,
                    )
                  : DecoratedBox(
                      decoration: ShapeDecoration(
                        color: level.colorOf(colorScheme),
                        shape: AppShape.full,
                        shadows: dockShadows(colorScheme),
                      ),
                      child: content,
                    ),
            ),
          ),
        ),
      ],
    );
  }
}
