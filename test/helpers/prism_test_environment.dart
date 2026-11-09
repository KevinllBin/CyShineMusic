import 'package:cy_shine_music/core/ui/widgets/prism_environment.dart';
import 'package:cy_shine_music/theme/liquid_glass_mode.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget buildPrismTestEnvironment(BuildContext context, Widget? child) =>
    Localizations.override(
      context: context,
      delegates: const [PrismChineseStrings.delegate],
      child: PrismEnvironment(
        mode: LiquidGlassMode.none,
        child: child ?? const SizedBox.shrink(),
      ),
    );

Finder floatingShellTab(String label) => find.descendant(
  of: find.byKey(const ValueKey('floating-navigation-dock')),
  matching: find.text(label),
);
