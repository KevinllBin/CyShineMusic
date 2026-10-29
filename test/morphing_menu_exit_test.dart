import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cy_shine_music/core/ui/widgets/morphing_menu_button.dart';
import 'package:cy_shine_music/core/ui/widgets/morphing_menu_surface.dart';

void main() {
  testWidgets('list menu exit dissolves from a rectangle, not the button', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        ),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: MorphingMenuButton(
              tooltip: '歌曲操作',
              actions: [
                MorphingMenuAction(
                  label: '删除',
                  leading: const Icon(Icons.delete_outline_rounded),
                  onSelected: () {},
                ),
                MorphingMenuAction(
                  label: '添加到歌单',
                  leading: const Icon(Icons.playlist_add_rounded),
                  onSelected: () {},
                ),
                MorphingMenuAction(
                  label: '添加到下一首播放',
                  leading: const Icon(Icons.playlist_play_rounded),
                  onSelected: () {},
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('歌曲操作'));
    await tester.pumpAndSettle();
    expect(find.text('删除'), findsOneWidget);

    Rect menuRect() {
      final positioned = tester.widget<Positioned>(
        find
            .descendant(
              of: find.byType(MorphingMenuSurface),
              matching: find.byType(Positioned),
            )
            .first,
      );
      return Rect.fromLTWH(
        positioned.left!,
        positioned.top!,
        positioned.width!,
        positioned.height!,
      );
    }

    double surfaceOpacity() => tester
        .widget<Opacity>(
          find
              .descendant(
                of: find.byType(MorphingMenuSurface),
                matching: find.byType(Opacity),
              )
              .first,
        )
        .opacity;

    double buttonOpacity() => tester
        .widget<Opacity>(
          find
              .descendant(
                of: find.byType(MorphingMenuButton),
                matching: find.byType(Opacity),
              )
              .first,
        )
        .opacity;

    double contentOpacity() => tester
        .widget<Opacity>(
          find
              .descendant(
                of: find.byType(MorphingMenuSurface),
                matching: find.byType(Opacity),
              )
              .at(1),
        )
        .opacity;

    final opened = menuRect();
    expect(buttonOpacity(), 0);

    // Tap the barrier far away from the menu to start the exit.
    await tester.tapAt(const Offset(4, 4));
    await tester.pump();

    var minWidth = double.infinity;
    var minHeight = double.infinity;
    var contentAtMinWidth = 1.0;
    for (var frame = 0; frame < 60; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      if (find.byType(MorphingMenuSurface).evaluate().isEmpty) break;
      final rect = menuRect();
      if (rect.width < minWidth) {
        minWidth = rect.width;
        contentAtMinWidth = contentOpacity();
      }
      minHeight = math.min(minHeight, rect.height);
      // The surface dissolve and the button fade-in are one handoff: if the
      // two opacities do not add up, both ends are invisible mid-exit.
      expect(
        surfaceOpacity() + buttonOpacity(),
        moreOrLessEquals(1, epsilon: 0.01),
      );
    }

    // The exit stops at a compact rectangle well clear of the 44x44 button.
    expect(minWidth, greaterThan(88));
    expect(minHeight, greaterThan(44));
    expect(minWidth, lessThan(opened.width));
    expect(minHeight, lessThan(opened.height));
    // Labels are fully dissolved by the time the rectangle hits its floor,
    // so they are never seen squeezed together.
    expect(contentAtMinWidth, 0);

    await tester.pumpAndSettle();
    expect(find.byType(MorphingMenuSurface), findsNothing);
    expect(buttonOpacity(), 1);
    expect(tester.takeException(), isNull);
  });
}
