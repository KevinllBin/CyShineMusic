import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:bass_player/bass_player.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cy_shine_music/features/player/player_audio_handler.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('shared playback skips Android focus and enables iOS mixing', () {
    expect(
      shouldActivatePlayerAudioSession(
        allowMixWithOthers: false,
        isAndroid: true,
      ),
      isTrue,
    );
    expect(
      shouldActivatePlayerAudioSession(
        allowMixWithOthers: true,
        isAndroid: true,
      ),
      isFalse,
    );
    expect(
      shouldActivatePlayerAudioSession(
        allowMixWithOthers: true,
        isAndroid: false,
      ),
      isTrue,
    );

    final configuration = playerAudioSessionConfiguration(
      allowMixWithOthers: true,
    );
    expect(
      configuration.avAudioSessionCategoryOptions,
      AVAudioSessionCategoryOptions.mixWithOthers,
    );
    expect(
      configuration.androidAudioAttributes?.contentType,
      AndroidAudioContentType.music,
    );
    expect(
      configuration.androidAudioAttributes?.usage,
      AndroidAudioUsage.media,
    );
  });

  test('a stalled load fails within a bounded time instead of hanging', () {
    expect(playerLoadTimeout, greaterThan(Duration.zero));
    expect(playerLoadTimeout, lessThanOrEqualTo(const Duration(minutes: 1)));
    expect(
      const PlayerLoadTimeoutException(Duration(seconds: 40)).toString(),
      contains('40'),
    );
  });

  test('platform failures preserve signed BASS error codes', () {
    final error = BassPlayerException.fromPlatform(
      PlatformException(
        code: 'BASS_-2',
        message: 'cancelled',
        details: const {'operation': 'load', 'bassCode': -2},
      ),
    );
    expect(error.code, -2);
    expect(error.operation, 'load');
  });

  testWidgets(
    'track transition keeps the media session alive with new metadata',
    (tester) async {
      expect(playerAudioServiceConfig.androidStopForegroundOnPause, isFalse);

      final handler = PlayerAudioHandler();
      final states = <PlaybackState>[];
      final subscription = handler.playbackState.listen(states.add);
      addTearDown(() async {
        await subscription.cancel();
        unawaited(handler.disposeHandler());
      });

      handler.updateMediaMetadata(
        MediaItem(
          id: 'old',
          title: '上一首',
          artist: '旧歌手',
          duration: const Duration(minutes: 3),
          artUri: Uri.parse('https://p1.music.126.net/old.jpg'),
          artHeaders: const {'Referer': 'https://music.163.com/'},
        ),
      );
      await tester.pump();
      expect(handler.mediaItem.value?.artHeaders, {
        'Referer': 'https://music.163.com/',
      });
      final stateCountBeforeTransition = states.length;

      await handler.beginTrackTransition(
        item: const MediaItem(id: 'next', title: '下一首', artist: '新歌手'),
        queueIndex: 1,
      );
      await tester.pump();

      expect(handler.mediaItem.value?.id, 'next');
      expect(handler.mediaItem.value?.title, '下一首');
      expect(
        handler.playbackState.value.processingState,
        AudioProcessingState.loading,
      );
      expect(handler.playbackState.value.playing, isFalse);
      expect(handler.playbackState.value.updatePosition, Duration.zero);
      expect(handler.playbackState.value.queueIndex, 1);
      expect(
        states
            .skip(stateCountBeforeTransition)
            .every(
              (state) => state.processingState != AudioProcessingState.idle,
            ),
        isTrue,
      );

      await handler.play();
      await handler.seek(const Duration(seconds: 30));
      expect(
        handler.playbackState.value.processingState,
        AudioProcessingState.loading,
      );

      handler.failTrackTransition('加载失败');
      expect(handler.mediaItem.value?.title, '上一首');
      expect(
        handler.playbackState.value.processingState,
        AudioProcessingState.error,
      );
      expect(handler.playbackState.value.errorMessage, contains('加载失败'));
      expect(tester.takeException(), isNull);
    },
  );

  test('system media clicks dispatch against the live BASS state', () async {
    final player = _FakeBassPlayer()..isPlaying = true;
    final handler = PlayerAudioHandler(player: player);
    var previousCount = 0;
    var nextCount = 0;
    handler.bindTransportCallbacks(
      owner: handler,
      onPrevious: () async => previousCount++,
      onNext: () async => nextCount++,
      onQueueItem: (_) async {},
      onRepeatMode: (_) async {},
      onShuffleMode: (_) async {},
    );
    addTearDown(handler.disposeHandler);

    await handler.click(MediaButton.media);
    expect(player.pauseCount, 1);
    await handler.click(MediaButton.media);
    expect(player.playCount, 1);
    await handler.click(MediaButton.next);
    await handler.click(MediaButton.previous);
    expect(nextCount, 1);
    expect(previousCount, 1);
  });

  test('pause cancels a play waiting for audio session setup', () async {
    final player = _FakeBassPlayer();
    final handler = _DelayedSessionAudioHandler(player);
    addTearDown(handler.disposeHandler);

    final pendingPlay = handler.play();
    await handler.sessionSetupStarted.future;
    await handler.pause();
    handler.sessionSetupCompleted.complete();
    await pendingPlay;

    expect(player.playCount, 0);
    expect(player.isPlaying, isFalse);
    await handler.play();
    expect(player.playCount, 1);
  });

  test('pause during an interruption cancels automatic resume', () async {
    final player = _FakeBassPlayer()..isPlaying = true;
    final handler = PlayerAudioHandler(player: player);
    addTearDown(handler.disposeHandler);
    final begin = AudioInterruptionEvent(true, AudioInterruptionType.pause);
    final end = AudioInterruptionEvent(false, AudioInterruptionType.pause);

    await handler.handleAudioInterruption(begin);
    expect(player.isPlaying, isFalse);
    await handler.handleAudioInterruption(end);
    expect(player.playCount, 1);

    await handler.handleAudioInterruption(begin);
    await handler.pause();
    await handler.handleAudioInterruption(end);
    expect(player.playCount, 1);
    expect(player.isPlaying, isFalse);
  });

  test('pause cancels interruption resume while volume is restoring', () async {
    final player = _FakeBassPlayer()..isPlaying = true;
    final handler = PlayerAudioHandler(player: player);
    addTearDown(handler.disposeHandler);
    await handler.handleAudioInterruption(
      AudioInterruptionEvent(true, AudioInterruptionType.duck),
    );
    await handler.handleAudioInterruption(
      AudioInterruptionEvent(true, AudioInterruptionType.pause),
    );

    final restoredVolume = Completer<void>();
    player.volumeRestore = restoredVolume;
    final pendingResume = handler.handleAudioInterruption(
      AudioInterruptionEvent(false, AudioInterruptionType.pause),
    );
    await handler.pause();
    restoredVolume.complete();
    await pendingResume;

    expect(player.playCount, 0);
    expect(player.isPlaying, isFalse);
  });
}

class _DelayedSessionAudioHandler extends PlayerAudioHandler {
  _DelayedSessionAudioHandler(BassPlayer player) : super(player: player);

  final sessionSetupStarted = Completer<void>();
  final sessionSetupCompleted = Completer<void>();

  @override
  Future<void> setAllowMixWithOthers(bool value) async {
    if (!sessionSetupStarted.isCompleted) sessionSetupStarted.complete();
    await sessionSetupCompleted.future;
  }
}

class _FakeBassPlayer extends BassPlayer {
  bool isPlaying = false;
  int playCount = 0;
  int pauseCount = 0;
  Completer<void>? volumeRestore;

  @override
  bool get playing => isPlaying;

  @override
  Future<void> play() async {
    playCount++;
    isPlaying = true;
  }

  @override
  Future<void> pause() async {
    pauseCount++;
    isPlaying = false;
  }

  @override
  Future<void> setVolume(double volume) async {
    if (volume == 1) await volumeRestore?.future;
  }

  @override
  Future<void> dispose() async {}
}
