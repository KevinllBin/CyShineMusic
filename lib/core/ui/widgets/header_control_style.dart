import 'package:flutter/material.dart';
import 'package:prism_ui/prism_ui.dart' as prism;

/// Plain header controls share the overflow button's fill and fine outline.
Color headerControlFill(BuildContext context) {
  final scheme = Theme.of(context).colorScheme;
  return scheme.brightness == Brightness.light
      ? Colors.white
      : scheme.surfaceContainerHigh;
}

BorderSide headerControlBorder(BuildContext context) => BorderSide(
  color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.55),
  width: 0.8,
);

prism.ButtonStyle headerControlButtonStyle(BuildContext context) {
  if (prism.LiquidGlassScope.of(context)) return const prism.ButtonStyle();
  return prism.ButtonStyle(
    backgroundColor: WidgetStatePropertyAll(headerControlFill(context)),
    side: WidgetStatePropertyAll(headerControlBorder(context)),
  );
}
