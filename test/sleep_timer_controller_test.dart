import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cy_shine_music/features/player/sleep_timer_controller.dart';

void main() {
  testWidgets('expires once at the deadline and clears remaining time', (
    tester,
  ) async {
    var pauseCount = 0;
    final timer = SleepTimerController(
      onElapsed: () async => pauseCount++,
      now: tester.binding.clock.now,
    );
    addTearDown(timer.dispose);

    timer.start(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 2));
    expect(timer.state, const Duration(seconds: 1));
    expect(pauseCount, 0);
    await tester.pump(const Duration(seconds: 1));
    expect(timer.state, isNull);
    expect(pauseCount, 1);
    await tester.pump(const Duration(minutes: 1));
    expect(pauseCount, 1);
  });

  testWidgets('replacing and cancelling a timer revoke its old deadline', (
    tester,
  ) async {
    var pauseCount = 0;
    final timer = SleepTimerController(
      onElapsed: () async => pauseCount++,
      now: tester.binding.clock.now,
    );
    addTearDown(timer.dispose);

    timer.start(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 1));
    timer.start(const Duration(seconds: 5));
    await tester.pump(const Duration(seconds: 2));
    expect(pauseCount, 0);
    expect(timer.state, const Duration(seconds: 3));
    timer.cancel();
    await tester.pump(const Duration(seconds: 10));
    expect(pauseCount, 0);
    expect(timer.state, isNull);

    timer.start(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(pauseCount, 1);
  });

  testWidgets('resuming after a delayed background tick expires immediately', (
    tester,
  ) async {
    var now = DateTime(2026, 9, 8);
    var pauseCount = 0;
    final timer = SleepTimerController(
      onElapsed: () async => pauseCount++,
      now: () => now,
    );
    addTearDown(timer.dispose);

    timer.start(const Duration(minutes: 15));
    timer.didChangeAppLifecycleState(AppLifecycleState.paused);
    now = now.add(const Duration(minutes: 16));
    timer.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pump();
    expect(pauseCount, 1);
    expect(timer.state, isNull);
  });

  testWidgets('disposing releases timers without pausing playback', (
    tester,
  ) async {
    var pauseCount = 0;
    final timer = SleepTimerController(
      onElapsed: () async => pauseCount++,
      now: tester.binding.clock.now,
    );
    timer.start(const Duration(seconds: 2));
    timer.dispose();
    await tester.pump(const Duration(seconds: 3));
    expect(pauseCount, 0);
  });
}
