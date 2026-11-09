import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart' as prism;

/// The measured source tile retained by Prism UI's OpenContainer zoom route.
class SettingsContainerOrigin {
  const SettingsContainerOrigin(this.createRoute);

  final prism.OpenContainerRouteFactory<void> createRoute;
}

/// GoRouter keeps page identity; Prism UI owns the tile-to-page zoom motion.
class SettingsRoutePage extends Page<void> {
  const SettingsRoutePage({
    super.key,
    required this.child,
    this.isRoot = false,
    this.origin,
  });
  final Widget child;
  final bool isRoot;
  final SettingsContainerOrigin? origin;

  @override
  Route<void> createRoute(BuildContext context) => isRoot
      ? prism.HomeRoute<void>(settings: this, builder: (_) => child)
      : origin != null
      ? origin!.createRoute(this, (_) => child)
      : prism.CardPageRoute<void>(settings: this, builder: (_) => child);
}
