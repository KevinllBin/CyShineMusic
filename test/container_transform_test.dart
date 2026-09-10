import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cy_shine_music/core/ui/container_transform.dart';
import 'package:cy_shine_music/theme/app_motion.dart';

void main() {
  test('hero progress remaps fastOutSlowIn onto the emphasized curve', () {
    expect(emphasizedHeroProgress(0), 0);
    expect(emphasizedHeroProgress(1), 1);
    for (final t in const [0.1, 0.25, 0.5, 0.75, 0.9]) {
      final heroValue = Curves.fastOutSlowIn.transform(t);
      expect(
        emphasizedHeroProgress(heroValue),
        closeTo(AppMotion.emphasized.transform(t), 5e-3),
      );
    }
    var previous = 0.0;
    for (var step = 1; step <= 100; step++) {
      final value = emphasizedHeroProgress(step / 100);
      expect(value, greaterThanOrEqualTo(previous));
      previous = value;
    }
    final tween = containerTransformHeroRectTween(
      const Rect.fromLTWH(0, 0, 100, 100),
      const Rect.fromLTWH(0, 0, 200, 200),
    );
    expect(tween.transform(0), const Rect.fromLTWH(0, 0, 100, 100));
    expect(tween.transform(1), const Rect.fromLTWH(0, 0, 200, 200));
    expect(
      tween.transform(Curves.fastOutSlowIn.transform(0.5))!.width,
      closeTo(100 + 100 * AppMotion.emphasized.transform(0.5), 1e-3),
    );
  });

  test('content fades in after the container opened a third of the way', () {
    expect(containerTransformContentOpacity(0), 0);
    expect(containerTransformContentOpacity(0.3), 0);
    expect(containerTransformContentOpacity(0.65), closeTo(0.5, 1e-9));
    expect(containerTransformContentOpacity(1), 1);
    expect(containerTransformFillOpacity(0), 0);
    expect(containerTransformFillOpacity(0.04), closeTo(0.5, 1e-9));
    expect(containerTransformFillOpacity(0.08), 1);
    expect(containerTransformFillOpacity(1), 1);
  });

  testWidgets('container grows from the origin rect and settles neutral', (
    tester,
  ) async {
    final controller = AnimationController(
      vsync: tester,
      duration: const Duration(milliseconds: 500),
    );
    addTearDown(controller.dispose);
    const origin = ContainerTransformOrigin(
      rect: Rect.fromLTWH(20, 300, 160, 240),
      borderRadius: BorderRadius.all(Radius.circular(8)),
      color: Color(0xFFEEEEEE),
    );
    const full = Rect.fromLTWH(0, 0, 800, 600);
    final surface = find.byKey(ContainerTransformTransition.surfaceKey);
    Opacity contentOpacity() => tester.widget<Opacity>(
      find.descendant(of: surface, matching: find.byType(Opacity)),
    );
    BoxDecoration decoration() {
      final box = tester.widget<DecoratedBox>(
        find.ancestor(of: surface, matching: find.byType(DecoratedBox)).first,
      );
      return box.decoration as BoxDecoration;
    }

    await tester.pumpWidget(
      MaterialApp(
        home: ContainerTransformTransition(
          animation: controller,
          origin: origin,
          child: const ColoredBox(color: Colors.blue, child: SizedBox.expand()),
        ),
      ),
    );

    expect(tester.getRect(surface), origin.rect);
    expect(tester.widget<ClipRRect>(surface).clipBehavior, Clip.antiAlias);
    expect(tester.widget<ClipRRect>(surface).borderRadius, origin.borderRadius);
    expect(contentOpacity().opacity, 0);
    expect(decoration().boxShadow, isNull);
    expect(decoration().color, const Color(0x00EEEEEE));

    controller.value = 0.5;
    await tester.pump();
    final t = AppMotion.emphasized.transform(0.5);
    _expectRectCloseTo(
      tester.getRect(surface),
      Rect.lerp(origin.rect, full, t)!,
    );
    expect(
      contentOpacity().opacity,
      closeTo(containerTransformContentOpacity(t), 1e-9),
    );
    expect(decoration().boxShadow, isNotNull);
    expect(decoration().color!.a, closeTo(1, 1e-9));

    controller.value = 1;
    await tester.pump();
    expect(tester.getRect(surface), full);
    expect(tester.widget<ClipRRect>(surface).clipBehavior, Clip.none);
    expect(tester.widget<ClipRRect>(surface).borderRadius, BorderRadius.zero);
    expect(contentOpacity().opacity, 1);
    expect(decoration().color, isNull);
    expect(decoration().boxShadow, isNull);
    expect(decoration().border, isNull);

    // 收回沿 emphasized.flipped 曲线：先快速缩小、再缓缓贴合卡片。
    controller.reverse();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    final reverseT = AppMotion.emphasized.flipped.transform(0.7);
    _expectRectCloseTo(
      tester.getRect(surface),
      Rect.lerp(origin.rect, full, reverseT)!,
    );
    expect(tester.widget<ClipRRect>(surface).clipBehavior, Clip.antiAlias);
    controller.stop();
    expect(tester.takeException(), isNull);
  });

  testWidgets('without an origin the page simply fades and scales in', (
    tester,
  ) async {
    final controller = AnimationController(
      vsync: tester,
      duration: const Duration(milliseconds: 500),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ContainerTransformTransition(
          animation: controller,
          origin: null,
          child: const SizedBox.expand(),
        ),
      ),
    );
    expect(find.byKey(ContainerTransformTransition.surfaceKey), findsNothing);
    expect(
      find.descendant(
        of: find.byType(ContainerTransformTransition),
        matching: find.byType(FadeTransition),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(ContainerTransformTransition),
        matching: find.byType(ScaleTransition),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('origin capture measures the card in navigator coordinates', (
    tester,
  ) async {
    const cardKey = ValueKey('card');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.only(left: 30, top: 50),
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(key: cardKey, width: 120, height: 80),
            ),
          ),
        ),
      ),
    );
    final origin = ContainerTransformOrigin.capture(
      tester.element(find.byKey(cardKey)),
      borderRadius: const BorderRadius.all(Radius.circular(6)),
      color: Colors.red,
    );
    expect(origin, isNotNull);
    expect(origin!.rect, tester.getRect(find.byKey(cardKey)));
    expect(origin.rect, const Rect.fromLTWH(30, 50, 120, 80));
    expect(origin.borderRadius, const BorderRadius.all(Radius.circular(6)));
    expect(origin.color, Colors.red);

    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(key: cardKey, width: 10, height: 10),
      ),
    );
    expect(
      ContainerTransformOrigin.capture(tester.element(find.byKey(cardKey))),
      isNull,
    );
  });

  testWidgets('hero artwork shape only clips when it has a radius', (
    tester,
  ) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Column(
          children: [
            HeroArtworkShape(
              borderRadius: BorderRadius.all(Radius.circular(8)),
              child: SizedBox(width: 10, height: 10),
            ),
            HeroArtworkShape(child: SizedBox(width: 10, height: 10)),
          ],
        ),
      ),
    );
    expect(find.byType(ClipRRect), findsOneWidget);
  });
}

void _expectRectCloseTo(Rect actual, Rect expected, {double tolerance = 0.01}) {
  expect(actual.left, closeTo(expected.left, tolerance));
  expect(actual.top, closeTo(expected.top, tolerance));
  expect(actual.right, closeTo(expected.right, tolerance));
  expect(actual.bottom, closeTo(expected.bottom, tolerance));
}
