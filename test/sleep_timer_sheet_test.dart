import 'package:cy_shine_music/features/player/sleep_timer_controller.dart';
import 'package:cy_shine_music/features/player/widgets/player_sleep_timer_sheet.dart';
import 'package:cy_shine_music/features/shell/shell_toolbar_visibility.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('preset timer survives closing the sheet and can be cancelled', (
    tester,
  ) async {
    final container = await _pumpHarness(tester);
    await tester.tap(find.text('打开定时'));
    await tester.pumpAndSettle();
    expect(container.read(shellToolbarVisibleProvider), isFalse);

    await tester.tap(find.text('45 分钟'));
    await tester.pump();
    await tester.tap(find.text('开启定时'));
    await tester.pumpAndSettle();
    expect(find.text('定时关闭音乐'), findsNothing);
    expect(container.read(shellToolbarVisibleProvider), isTrue);
    expect(container.read(sleepTimerProvider), const Duration(minutes: 45));

    await tester.pump(const Duration(seconds: 5));
    final remaining = container.read(sleepTimerProvider)!;
    expect(remaining, lessThan(const Duration(minutes: 45)));
    expect(remaining, greaterThan(const Duration(minutes: 44)));

    container.read(shellToolbarVisibleProvider.notifier).state = false;
    await tester.tap(find.text('打开定时'));
    await tester.pumpAndSettle();
    expect(find.text('距离暂停播放'), findsOneWidget);
    expect(find.text('重新计时'), findsOneWidget);
    await tester.tap(find.text('取消定时'));
    await tester.pumpAndSettle();
    expect(container.read(sleepTimerProvider), isNull);
    expect(container.read(shellToolbarVisibleProvider), isFalse);
  });

  testWidgets(
    'custom minutes validate and start with a narrow screen keyboard',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      final container = await _pumpHarness(tester);
      await tester.tap(find.text('打开定时'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('自定义'));
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding(bottom: 260);
      await tester.pumpAndSettle();

      final input = find.byType(TextField);
      final start = find.widgetWithText(FilledButton, '开启定时');
      expect(tester.widget<FilledButton>(start).onPressed, isNull);
      for (final invalid in ['0', '181']) {
        await tester.enterText(input, invalid);
        await tester.pump();
        expect(tester.widget<FilledButton>(start).onPressed, isNull);
        expect(container.read(sleepTimerProvider), isNull);
      }

      await tester.enterText(input, '12');
      await tester.pump();
      expect(tester.widget<FilledButton>(start).onPressed, isNotNull);
      await tester.ensureVisible(start);
      await tester.tap(start);
      await tester.pumpAndSettle();
      expect(container.read(sleepTimerProvider), const Duration(minutes: 12));
      expect(find.text('定时关闭音乐'), findsNothing);
      expect(tester.takeException(), isNull);
      container.read(sleepTimerProvider.notifier).cancel();
    },
  );
}

Future<ProviderContainer> _pumpHarness(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sleepTimerProvider.overrideWith(
          (ref) => SleepTimerController(
            onElapsed: () async {},
            now: tester.binding.clock.now,
          ),
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) => Center(
              child: FilledButton(
                onPressed: () => showPlayerSleepTimerSheet(context, ref),
                child: const Text('打开定时'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  return ProviderScope.containerOf(tester.element(find.text('打开定时')));
}
