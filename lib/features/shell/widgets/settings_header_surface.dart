import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart' as prism;

/// Prism UI ScaffoldBar's fading surface and 16dp overhang.
class SettingsHeaderSurface extends StatelessWidget {
  const SettingsHeaderSurface({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return prism.FloatingHeader(
      backgroundColor: prism.SurfaceLevel.page.colorOf(
        prism.Theme.of(context).colorScheme,
      ),
      fadeStart: top / (top + prism.pageToolbarHeight),
      overhang: 16,
      child: child,
    );
  }
}
