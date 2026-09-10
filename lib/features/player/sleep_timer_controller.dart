import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/app_logger.dart';
import 'player_controller.dart';

/// A session-only timer: closing a sheet or changing tracks does not cancel it.
class SleepTimerController extends StateNotifier<Duration?>
    with WidgetsBindingObserver {
  SleepTimerController({
    required Future<void> Function() onElapsed,
    DateTime Function()? now,
  }) : _onElapsed = onElapsed,
       _now = now ?? DateTime.now,
       super(null) {
    WidgetsBinding.instance.addObserver(this);
  }

  final Future<void> Function() _onElapsed;
  final DateTime Function() _now;
  DateTime? _deadline;
  Timer? _expiryTimer;
  Timer? _displayTimer;

  void start(Duration duration) {
    if (duration <= Duration.zero) {
      throw ArgumentError.value(duration, 'duration', 'Must be positive');
    }
    _clearTimers();
    _deadline = _now().add(duration);
    state = duration;
    _expiryTimer = Timer(duration, () => unawaited(_expire()));
    _displayTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _refreshRemaining(),
    );
    unawaited(
      AppLogger.write(
        'sleep-timer',
        'started durationSeconds=${duration.inSeconds}',
      ),
    );
  }

  void cancel() {
    _clearTimers();
    _deadline = null;
    state = null;
    unawaited(AppLogger.write('sleep-timer', 'cancelled'));
  }

  void _refreshRemaining() {
    final deadline = _deadline;
    if (deadline == null) return;
    final remaining = deadline.difference(_now());
    if (remaining <= Duration.zero) {
      unawaited(_expire());
    } else {
      // Derive from the deadline so delayed/background ticks do not add time.
      state = Duration(seconds: (remaining.inMicroseconds / 1000000).ceil());
    }
  }

  Future<void> _expire() async {
    if (!mounted || _deadline == null) return;
    _clearTimers();
    _deadline = null;
    state = null;
    try {
      await _onElapsed();
      await AppLogger.write('sleep-timer', 'elapsed playbackPaused=true');
    } catch (error) {
      await AppLogger.write('sleep-timer', 'pause failed: $error');
    }
  }

  void _clearTimers() {
    _expiryTimer?.cancel();
    _expiryTimer = null;
    _displayTimer?.cancel();
    _displayTimer = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshRemaining();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clearTimers();
    super.dispose();
  }
}

final sleepTimerProvider =
    StateNotifierProvider<SleepTimerController, Duration?>((ref) {
      return SleepTimerController(
        onElapsed: () =>
            ref.read(playerControllerProvider.notifier).pauseForSleepTimer(),
      );
    });
