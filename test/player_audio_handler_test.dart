import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:bass_player/bass_player.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cy_shine_music/features/player/player_audio_handler.dart';
import 'package:cy_shine_music/features/player/vivo_music_metadata.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Vivo queue pages use live song IDs beyond the first page', () async {
    final handler = PlayerAudioHandler(player: _FakeBassPlayer());
    addTearDown(handler.disposeHandler);
    final selected = <int>[];
    handler.bindTransportCallbacks(
      owner: handler,
      onPrevious: () async {},
      onNext: () async {},
      onQueueItem: (index) async => selected.add(index),
      onRepeatMode: (_) async {},
      onShuffleMode: (_) async {},
    );
    final items = List.generate(
      103,
      (index) => MediaItem(id: 'song-$index', title: 'Song $index'),
    );
    handler.publishQueue(items, currentIndex: 0);
    handler.updateMediaMetadata(items.first);

    final first = await handler.getChildren(VivoMusicMetadata.currentListId);
    final second = await handler.getChildren(VivoMusicMetadata.currentListId, {
      VivoMusicMetadata.pageKey: 1,
    });
    final last = await handler.getChildren(VivoMusicMetadata.currentListId, {
      VivoMusicMetadata.pageKey: 2,
    });
    expect(first, hasLength(50));
    expect(first.last.extras?[VivoMusicMetadata.pageKey], 1);
    expect(first.last.extras?[VivoMusicMetadata.hasMoreKey], isTrue);
    expect(second.first.id, 'song-50');
    expect(second.last.id, 'song-99');
    expect(last.map((item) => item.id), ['song-100', 'song-101', 'song-102']);
    expect(last.last.extras?[VivoMusicMetadata.hasMoreKey], isFalse);
    await handler.playFromMediaId(second.last.id);
    expect(selected, [99]);

    for (final invalidPage in [
      -1,
      '1',
      0.5,
      double.nan,
      double.infinity,
      1e300,
    ]) {
      expect(
        await handler.getChildren(VivoMusicMetadata.currentListId, {
          VivoMusicMetadata.pageKey: invalidPage,
        }),
        isEmpty,
      );
    }
    handler.publishQueue(const [MediaItem(id: 'new-song', title: 'New song')]);
    await handler.playFromMediaId('song-99');
    expect(selected, [99]);
  });

  test(
    'Vivo queue handles an empty page, standalone lyrics and online fallback',
    () async {
      final handler = PlayerAudioHandler(player: _FakeBassPlayer());
      addTearDown(handler.disposeHandler);
      final empty = await handler.getChildren(VivoMusicMetadata.currentListId);
      expect(empty.single.title, '暂无播放队列');
      expect(empty.single.extras?[VivoMusicMetadata.hasMoreKey], isFalse);
      await handler.playFromMediaId(empty.single.id);

      handler.updateMediaMetadata(
        const MediaItem(
          id: 'song:online',
          title: '正在唱的歌词',
          artist: '歌名 - 歌手',
          extras: {
            VivoMusicMetadata.songTitleKey: '原始歌名',
            VivoMusicMetadata.songArtistKey: '原始歌手',
            VivoMusicMetadata.lyricKey: '[00:01.00]正在唱的歌词',
          },
        ),
      );
      final standalone = await handler.getChildren(
        VivoMusicMetadata.currentListId,
      );
      expect(standalone.single.id, 'song:online');
      expect(standalone.single.title, '原始歌名');
      expect(standalone.single.artist, '原始歌手');
      expect(
        standalone.single.extras,
        isNot(contains(VivoMusicMetadata.lyricKey)),
      );
      final selected = <int>[];
      handler.bindTransportCallbacks(
        owner: handler,
        onPrevious: () async {},
        onNext: () async {},
        onQueueItem: (index) async => selected.add(index),
        onRepeatMode: (_) async {},
        onShuffleMode: (_) async {},
      );
      handler.publishQueue(const [
        MediaItem(id: 'song:local', title: '原始歌名', artist: '原始歌手'),
        MediaItem(id: 'next', title: '下一首'),
      ], currentIndex: 0);
      final fallback = await handler.getChildren(
        VivoMusicMetadata.currentListId,
      );
      expect(fallback.first.id, 'song:online');
      await handler.playFromMediaId(fallback.first.id);
      expect(selected, [0]);
    },
  );

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

  test('the remote load bound leaves room for a weak network', () {
    // Native gives a response 8 seconds, then the file headers 10 more.
    expect(
      playerRemoteLoadTimeout,
      greaterThanOrEqualTo(const Duration(seconds: 20)),
    );
    expect(playerRemoteLoadTimeout, lessThanOrEqualTo(playerLoadTimeout));
  });

  test('a pending remote load times out at its bound and stops', () async {
    final player = _PendingLoadBassPlayer();
    final handler = PlayerAudioHandler(
      player: player,
      remoteLoadTimeout: const Duration(milliseconds: 50),
    );
    addTearDown(handler.disposeHandler);
    await handler.initializeEngine();

    await expectLater(
      handler
          .load(
            item: const MediaItem(id: 'remote', title: 'Remote'),
            sourceUri: Uri.parse('https://audio.test/stalled.mp3'),
          )
          .timeout(const Duration(seconds: 5)),
      throwsA(
        isA<PlayerLoadTimeoutException>().having(
          (error) => error.timeout,
          'timeout',
          const Duration(milliseconds: 50),
        ),
      ),
    );
    expect(player.stopCount, 1);
  });

  test('an old remote timeout leaves a newer local load intact', () async {
    final player = _PendingLoadBassPlayer();
    final handler = PlayerAudioHandler(
      player: player,
      remoteLoadTimeout: const Duration(milliseconds: 50),
    );
    addTearDown(handler.disposeHandler);
    await handler.initializeEngine();

    final remoteFailure = expectLater(
      handler.load(
        item: const MediaItem(id: 'remote', title: 'Remote'),
        sourceUri: Uri.parse('https://audio.test/stalled.mp3'),
      ),
      throwsA(isA<PlayerLoadTimeoutException>()),
    );
    final localLoading = handler.load(
      item: const MediaItem(id: 'local', title: 'Local'),
      sourceUri: Uri.file('/music/local.flac'),
    );

    await remoteFailure.timeout(const Duration(seconds: 5));
    expect(player.stopCount, 0);
    expect(handler.currentMediaItem?.id, 'local');
    player.pendingLoads.last.complete(const Duration(minutes: 4));
    expect(await localLoading, const Duration(minutes: 4));
    expect(handler.currentMediaItem?.duration, const Duration(minutes: 4));
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

class _PendingLoadBassPlayer extends _FakeBassPlayer {
  final pendingLoads = <Completer<Duration?>>[];
  int stopCount = 0;

  @override
  Future<BassEngineInfo> initialize() async =>
      const BassEngineInfo(version: 'test', fxVersion: 'test', plugins: {});

  @override
  Future<Duration?> load(
    Uri source, {
    Map<String, String> headers = const {},
    String? formatHint,
  }) {
    final pending = Completer<Duration?>();
    pendingLoads.add(pending);
    return pending.future;
  }

  @override
  Future<void> stop() async {
    stopCount++;
    for (final pending in pendingLoads) {
      if (!pending.isCompleted) pending.complete(null);
    }
  }
}
