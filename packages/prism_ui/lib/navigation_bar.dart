import 'package:flutter/widgets.dart';
import 'package:prism_ui/context.dart';
import 'package:prism_ui/press_region.dart';
import 'package:prism_ui/shape.dart';
import 'package:prism_ui/surface.dart';
import 'package:prism_ui/typography.dart';

class NavigationDestination {
  const NavigationDestination({required this.icon, required this.label});

  final Widget icon;
  final String label;
}

/// The bar a window's tabs stand on where the floating dock is turned off.
class NavigationBar extends StatelessWidget {
  const NavigationBar({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final List<NavigationDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  static const _height = 80.0;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return Surface(
      color: SurfaceLevel.floatingOf(colorScheme).colorOf(colorScheme),
      child: SafeArea(
        child: SizedBox(
          height: _height,
          child: Row(
            children: [
              for (final (index, destination) in destinations.indexed)
                Expanded(
                  child: _Destination(
                    destination: destination,
                    selected: index == selectedIndex,
                    onTap: () => onDestinationSelected(index),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Destination extends StatelessWidget {
  const _Destination({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final NavigationDestination destination;
  final bool selected;
  final VoidCallback onTap;

  static const _indicator = Size(64, 32);
  static const _motion = Duration(milliseconds: 500);

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final floating = SurfaceLevel.floatingOf(colorScheme);
    return Semantics(
      button: true,
      selected: selected,
      container: true,
      child: PressRegion(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          spacing: 4,
          children: [
            SizedBox.fromSize(
              size: _indicator,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  TweenAnimationBuilder<double>(
                    tween: Tween(end: selected ? 1 : 0),
                    duration: context.motionDuration(_motion),
                    curve: Curves.easeInOutCubicEmphasized,
                    builder: (context, t, _) => Opacity(
                      opacity: t.clamp(0.0, 1.0),
                      child: Transform.scale(
                        scaleX: t,
                        child: DecoratedBox(
                          decoration: ShapeDecoration(
                            color: floating.next.colorOf(colorScheme),
                            shape: AppShape.full,
                          ),
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ),
                  ),
                  IconTheme.merge(
                    data: IconThemeData(
                      size: 24,
                      color: selected
                          ? colorScheme.primary
                          : colorScheme.onSurfaceVariant,
                    ),
                    child: destination.icon,
                  ),
                ],
              ),
            ),
            Text(
              destination.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyle.caption1
                  .of(context, emphasized: true)
                  .copyWith(
                    color: selected
                        ? colorScheme.onSurface
                        : colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
