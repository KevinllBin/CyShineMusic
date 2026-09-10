import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cy_shine_music/features/settings/widgets/theme_seed_row.dart';
import 'package:cy_shine_music/theme/seed_palette.dart';

void main() {
  testWidgets('theme swatches scroll horizontally', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ThemeSeedRow(
            value: SeedPalette.presets.first.color,
            onPick: (_) {},
            onCustomize: () {},
          ),
        ),
      ),
    );

    final swatches = find.byKey(const ValueKey('theme-seed-swatch-row'));
    final scrollable = find.descendant(
      of: swatches,
      matching: find.byType(Scrollable),
    );
    expect(tester.state<ScrollableState>(scrollable).position.pixels, 0);

    await tester.drag(swatches, const Offset(-150, 0));
    await tester.pumpAndSettle();

    expect(
      tester.state<ScrollableState>(scrollable).position.pixels,
      greaterThan(0),
    );

    expect(tester.takeException(), isNull);
  });
}
