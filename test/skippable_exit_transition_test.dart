import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cy_shine_music/core/ui/skippable_exit_transition.dart';

void main() {
  Future<AnimationController> pumpTransition(
    WidgetTester tester, {
    required bool skip,
  }) async {
    final controller = AnimationController(
      vsync: tester,
      duration: const Duration(milliseconds: 300),
      value: 1,
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: SkippableExitTransition(
          animation: controller,
          skipExit: (_) => skip,
          child: const Text('detail'),
        ),
      ),
    );
    return controller;
  }

  testWidgets('exit is hidden immediately when skipExit says so', (
    tester,
  ) async {
    final controller = await pumpTransition(tester, skip: true);
    expect(find.text('detail'), findsOneWidget);

    controller.reverse();
    await tester.pump();
    expect(find.text('detail'), findsNothing);

    // 退场结束后保持隐藏，不在最后一帧闪现。
    await tester.pumpAndSettle();
    expect(controller.status, AnimationStatus.dismissed);
    expect(find.text('detail'), findsNothing);

    // 重新进入时恢复可见。
    controller.forward();
    await tester.pump();
    expect(find.text('detail'), findsOneWidget);
  });

  testWidgets('regular back keeps the exit visible', (tester) async {
    final controller = await pumpTransition(tester, skip: false);

    controller.reverse();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('detail'), findsOneWidget);
    await tester.pumpAndSettle();
  });
}
