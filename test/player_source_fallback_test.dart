import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:bass_player/bass_player.dart' as bass;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cy_shine_music/core/api/music_api.dart';
import 'package:cy_shine_music/core/models/enums.dart';
import 'package:cy_shine_music/core/models/lyric_info.dart';
import 'package:cy_shine_music/core/models/music_info.dart';
import 'package:cy_shine_music/core/models/music_url.dart';
import 'package:cy_shine_music/core/music_sources/music_source_models.dart';
import 'package:cy_shine_music/core/music_sources/music_source_runtime.dart';
import 'package:cy_shine_music/core/music_sources/music_url_resolver.dart';
import 'package:cy_shine_music/core/services/app_logger.dart';
import 'package:cy_shine_music/core/services/log_category.dart';
import 'package:cy_shine_music/core/storage/settings_store.dart';
import 'package:cy_shine_music/features/player/player_audio_handler.dart';
import 'package:cy_shine_music/features/player/player_controller.dart';
import 'package:cy_shine_music/features/downloads/download_history_entry.dart';
import 'package:cy_shine_music/features/player/player_session_snapshot.dart';
import 'package:cy_shine_music/features/player/player_session_store.dart';
import 'package:cy_shine_music/features/player/vivo_music_metadata.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'Vivo list selection preserves the full playlist and current song ID',
    () async {
      final harness = await _Harness.create(loadFailures: 0);
      addTearDown(harness.dispose);
      final entries = _remoteQueue(54);
      await harness.controller.playFromPlaylistQueue(
        entries.first,
        entries,
        playlistId: 'vivo-queue',
      );
      final secondPage = await harness.audio.getChildren(
        VivoMusicMetadata.currentListId,
        {VivoMusicMetadata.pageKey: 1},
      );
      expect(secondPage, hasLength(4));
      expect(secondPage.first.title, 'Song 50');
      await harness.audio.playFromMediaId(secondPage[1].id);

      final state = harness.container.read(playerControllerProvider);
      expect(state.queueIndex, 51);
      expect(state.track?.id, secondPage[1].id);
      expect(state.queue, hasLength(54));
      expect(harness.controller.queuePlaylistId, 'vivo-queue');
      await harness.controller.playNext();
      expect(harness.container.read(playerControllerProvider).queueIndex, 52);
      final expanded = [...entries, ..._remoteQueue(56).skip(54)];
      expect(
        harness.controller.expandPlaylistQueue(
          expectedQueue: entries,
          expandedQueue: expanded,
        ),
        isTrue,
      );
      final updated = await harness.audio.getChildren(
        VivoMusicMetadata.currentListId,
        {VivoMusicMetadata.pageKey: 1},
      );
      expect(updated, hasLength(6));
      expect(updated.last.title, 'Song 55');
    },
  );

  test(
    'Vivo playback modes replace shuffle and update both system states',
    () async {
      final harness = await _Harness.create(loadFailures: 0);
      addTearDown(harness.dispose);
      await harness.controller.playFromMusic(_music());
      final loads = harness.audio.loadedUris.length;

      Future<void> selectMode(int mode) => harness.audio.customAction(
        VivoMusicMetadata.playModeAction,
        {VivoMusicMetadata.loopModeKey: mode},
      );

      await selectMode(3);
      expect(
        harness.container.read(playerControllerProvider).playbackMode,
        PlayerPlaybackMode.shuffle,
      );
      expect(
        harness.audio.playbackState.value.shuffleMode,
        AudioServiceShuffleMode.all,
      );
      expect(
        harness.audio.currentMediaItem?.extras?[VivoMusicMetadata.loopModeKey],
        3,
      );

      await selectMode(2);
      expect(
        harness.container.read(playerControllerProvider).playbackMode,
        PlayerPlaybackMode.repeatOne,
      );
      expect(
        harness.audio.playbackState.value.shuffleMode,
        AudioServiceShuffleMode.none,
      );
      expect(
        harness.audio.playbackState.value.repeatMode,
        AudioServiceRepeatMode.one,
      );
      expect(
        harness.audio.currentMediaItem?.extras?[VivoMusicMetadata.loopModeKey],
        2,
      );

      await selectMode(1);
      expect(
        harness.container.read(playerControllerProvider).playbackMode,
        PlayerPlaybackMode.sequence,
      );
      expect(
        harness.audio.playbackState.value.repeatMode,
        AudioServiceRepeatMode.all,
      );
      expect(
        harness.audio.currentMediaItem?.extras?[VivoMusicMetadata.loopModeKey],
        1,
      );
      harness.controller.setPlaybackMode(PlayerPlaybackMode.shuffle);
      expect(
        harness.audio.currentMediaItem?.extras?[VivoMusicMetadata.loopModeKey],
        3,
      );
      expect(harness.audio.loadedUris.length, loads);
    },
  );

  test(
    'Vivo lyrics publish with Bluetooth lyric options disabled and survive mode changes',
    () async {
      final harness = await _Harness.create(loadFailures: 0);
      addTearDown(harness.dispose);
      expect(
        harness.container.read(settingsProvider).bluetoothLyricEnabled,
        isFalse,
      );
      expect(
        harness.container.read(settingsProvider).bluetoothFullLyricEnabled,
        isFalse,
      );
      await harness.controller.playFromMusic(_music());
      await _waitUntil(
        () => !harness.container.read(playerControllerProvider).lyricLoading,
      );

      final item = harness.audio.currentMediaItem!;
      expect(item.title, 'Test Song');
      expect(item.extras?[VivoMusicMetadata.lyricKey], '[00:01.00]Test lyric');
      await harness.audio.customAction(VivoMusicMetadata.playModeAction, {
        VivoMusicMetadata.loopModeKey: 2,
      });
      expect(
        harness.audio.currentMediaItem?.extras?[VivoMusicMetadata.lyricKey],
        '[00:01.00]Test lyric',
      );
      for (final invalid in [
        null,
        '3',
        0,
        4,
        2.5,
        double.nan,
        double.infinity,
      ]) {
        await harness.audio.customAction(VivoMusicMetadata.playModeAction, {
          VivoMusicMetadata.loopModeKey: invalid,
        });
      }
      expect(
        harness.container.read(playerControllerProvider).playbackMode,
        PlayerPlaybackMode.repeatOne,
      );
    },
  );

  test('player track keeps source quality sizes and canonical Hi-Res data', () {
    final music = MusicInfo(
      id: 'sized-song',
      name: 'Sized Song',
      singer: 'Singer',
      source: MusicSource.kw,
      interval: '03:00',
      meta: const MusicMeta(
        songId: 'sized-song',
        albumName: 'Album',
        qualitys: [
          QualityOption(type: Quality.flac24bit, size: '48.20 MB'),
          QualityOption(type: Quality.flac, size: '24.10 MB'),
        ],
        raw: {},
      ),
      raw: const {},
    );

    final track = PlayerTrack.fromMusic(
      music: music,
      quality: Quality.hires,
      url: 'https://audio.test/sized-song.flac',
      coverUrl: null,
      availableQualities: const [
        Quality.hires,
        Quality.flac24bit,
        Quality.flac,
        Quality.k320,
      ],
    );

    expect(track.availableQualities, [
      Quality.hires,
      Quality.flac,
      Quality.k320,
    ]);
    expect(track.availableQualityOptions[0].type, Quality.hires);
    expect(track.availableQualityOptions[0].size, '48.20 MB');
    expect(track.availableQualityOptions[1].size, '24.10 MB');
    expect(track.availableQualityOptions[2].size, isNull);
  });

  test(
    'audio load failure falls back without publishing an error state',
    () async {
      final harness = await _Harness.create(loadFailures: 1);
      addTearDown(harness.dispose);
      final errors = <String>[];
      final subscription = harness.container.listen<PlayerState>(
        playerControllerProvider,
        (_, next) {
          if (next.error != null) errors.add(next.error!);
        },
      );
      addTearDown(subscription.close);

      await harness.controller.playFromMusic(_music());
      final state = harness.container.read(playerControllerProvider);

      expect(harness.audio.loadedUris, [
        Uri.parse('https://audio.test/first.mp3'),
        Uri.parse('https://audio.test/second.mp3'),
      ]);
      expect(harness.resolver.attemptedIds, ['first', 'second']);
      expect(state.loading, isFalse);
      expect(state.error, isNull);
      expect(state.track?.remoteUrl, 'https://audio.test/second.mp3');
      expect(harness.audio.failTransitionCount, 0);
      expect(errors, isEmpty);
    },
  );

  test('NetEase system media artwork carries the required headers', () async {
    final harness = await _Harness.create(loadFailures: 0);
    addTearDown(harness.dispose);

    await harness.controller.playFromMusic(_neteaseMusic());

    final item = harness.audio.currentMediaItem;
    expect(
      item?.artUri.toString(),
      'https://p1.music.126.net/test/cover.jpg?param=500y500',
    );
    expect(item?.artHeaders, containsPair('Referer', 'https://music.163.com/'));
    expect(item?.artHeaders, contains('User-Agent'));
  });

  test('selected artwork is published before audio finishes loading', () async {
    final harness = await _Harness.create(loadFailures: 0);
    addTearDown(harness.dispose);
    final loadGate = Completer<void>();
    harness.audio.loadGate = loadGate;
    final music = _neteaseMusic();

    final loading = harness.controller.playFromMusic(music);
    final selected = harness.container.read(playerControllerProvider);
    expect(selected.track?.id, 'wy:netease-song:remote');
    expect(selected.track?.coverUrl, music.meta.picUrl);
    expect(selected.loading, isTrue);
    expect(selected.track?.remoteUrl, isEmpty);

    await _waitUntil(() => harness.audio.loadedUris.isNotEmpty);
    expect(harness.container.read(playerControllerProvider).loading, isTrue);
    expect(
      harness.container.read(playerControllerProvider).track?.coverUrl,
      music.meta.picUrl,
    );

    loadGate.complete();
    await loading;
    expect(harness.container.read(playerControllerProvider).loading, isFalse);
  });

  test(
    'resolved artwork publishes while loading and ignores stale cover responses',
    () async {
      final harness = await _Harness.create(loadFailures: 0);
      addTearDown(harness.dispose);
      final loadGate = Completer<void>();
      harness.audio.loadGate = loadGate;
      final oldCover = Completer<String?>();
      final currentCover = Completer<String?>();
      harness.api.coverResponses['song-1'] = oldCover;
      harness.api.coverResponses['netease-song'] = currentCover;

      final oldLoading = harness.controller.playFromMusic(_music());
      await _waitUntil(() => harness.audio.loadedUris.length == 1);
      final currentLoading = harness.controller.playFromMusic(_neteaseMusic());
      await _waitUntil(() => harness.audio.loadedUris.length == 2);

      const currentCoverUrl = 'https://artwork.test/current-cover.jpg';
      currentCover.complete(currentCoverUrl);
      await _waitUntil(
        () =>
            harness.container.read(playerControllerProvider).track?.coverUrl ==
            currentCoverUrl,
      );
      final current = harness.container.read(playerControllerProvider);
      expect(current.track?.id, 'wy:netease-song:remote');
      expect(current.loading, isTrue);
      expect(current.track?.remoteUrl, isEmpty);

      oldCover.complete('https://artwork.test/stale-cover.jpg');
      await Future<void>.delayed(Duration.zero);
      final afterStaleCover = harness.container.read(playerControllerProvider);
      expect(afterStaleCover.track?.id, current.track?.id);
      expect(afterStaleCover.track?.coverUrl, currentCoverUrl);
      expect(afterStaleCover.loading, isTrue);

      loadGate.complete();
      await Future.wait([oldLoading, currentLoading]);
      final loaded = harness.container.read(playerControllerProvider);
      expect(loaded.track?.id, current.track?.id);
      expect(loaded.track?.coverUrl, currentCoverUrl);
      expect(loaded.loading, isFalse);
    },
  );

  test('all source load failures keep the current track paused', () async {
    final harness = await _Harness.create(loadFailures: 2);
    addTearDown(harness.dispose);
    final errors = <String>[];
    final subscription = harness.container.listen<PlayerState>(
      playerControllerProvider,
      (_, next) {
        if (next.error != null) errors.add(next.error!);
      },
    );
    addTearDown(subscription.close);

    await harness.controller.playFromMusic(_music());
    final state = harness.container.read(playerControllerProvider);

    expect(harness.audio.loadedUris, hasLength(2));
    expect(state.loading, isFalse);
    expect(state.track?.id, 'kw:song-1:remote');
    expect(state.playing, isFalse);
    expect(state.processingState, PlayerProcessingState.ready);
    expect(
      harness.audio.playbackState.value.processingState,
      AudioProcessingState.ready,
    );
    expect(state.error, contains('所有已启用音源均无法播放'));
    expect(harness.audio.failTransitionCount, 0);
    expect(harness.audio.pauseCount, 1);
    expect(errors, hasLength(1));
  });

  test(
    'ten automatic source-failure skips pause and remain retryable',
    () async {
      final harness = await _Harness.create(loadFailures: 1000);
      addTearDown(harness.dispose);
      final queue = _remoteQueue(30);

      await harness.controller.playFromHistoryQueue(queue.first, queue);
      final paused = harness.container.read(playerControllerProvider);
      expect(paused.queueIndex, 10);
      expect(paused.queue, hasLength(30));
      expect(paused.track?.id, 'kw:song-10:remote');
      expect(paused.loading, isFalse);
      expect(paused.playing, isFalse);
      expect(paused.processingState, PlayerProcessingState.ready);
      expect(paused.error, contains('连续切换 10 首'));
      expect(harness.resolver.requestedQualities, hasLength(11));
      expect(harness.audio.hasPendingSourceRetry, isTrue);

      // Notification play uses the same pending retry as the in-app button.
      await harness.audio.play();
      final retried = harness.container.read(playerControllerProvider);
      expect(retried.queueIndex, 20);
      expect(retried.processingState, PlayerProcessingState.ready);
      expect(retried.playing, isFalse);
      expect(harness.audio.pauseCount, 2);
    },
  );

  test('manual song selection starts a new failure skip budget', () async {
    final harness = await _Harness.create(loadFailures: 1000);
    addTearDown(harness.dispose);
    final queue = _remoteQueue(30);
    await harness.controller.playFromHistoryQueue(queue.first, queue);
    expect(harness.container.read(playerControllerProvider).queueIndex, 10);

    await harness.controller.playFromHistoryQueue(queue[11], queue);
    final state = harness.container.read(playerControllerProvider);
    expect(state.queueIndex, 21);
    expect(state.processingState, PlayerProcessingState.ready);
    expect(state.playing, isFalse);
  });

  for (final progressed in [false, true]) {
    test(
      progressed
          ? 'actual playback progress resets the failure skip budget'
          : 'ready without playback progress does not reset failure skips',
      () async {
        final harness = await _Harness.create(loadFailures: 18);
        addTearDown(harness.dispose);
        final queue = _remoteQueue(30);
        await harness.controller.playFromHistoryQueue(queue.first, queue);
        expect(harness.container.read(playerControllerProvider).queueIndex, 9);
        harness.audio.emitPlaybackState(bass.BassProcessingState.ready);
        if (progressed) {
          harness.audio.emitPosition(const Duration(seconds: 2));
        }

        harness.audio.loadFailures = 1000;
        harness.audio.emitError(
          const bass.BassPlayerException(code: 1, message: 'stream failed'),
        );
        final expectedIndex = progressed ? 19 : 10;
        await _waitUntil(() {
          final state = harness.container.read(playerControllerProvider);
          return state.queueIndex == expectedIndex &&
              !state.loading &&
              harness.audio.hasPendingSourceRetry;
        });
        final paused = harness.container.read(playerControllerProvider);
        expect(paused.playing, isFalse);
        expect(paused.processingState, PlayerProcessingState.ready);
        expect(paused.error, contains('连续切换 10 首'));
      },
    );
  }

  for (final mode in [
    PlayerPlaybackMode.shuffle,
    PlayerPlaybackMode.repeatOne,
  ]) {
    test(
      'source failure skip limit also applies in ${mode.name} mode',
      () async {
        final harness = await _Harness.create(loadFailures: 1000);
        addTearDown(harness.dispose);
        harness.controller.setPlaybackMode(mode);
        final queue = _remoteQueue(30);

        await harness.controller.playFromHistoryQueue(queue.first, queue);
        final state = harness.container.read(playerControllerProvider);
        expect(harness.resolver.requestedQualities, hasLength(11));
        expect(state.processingState, PlayerProcessingState.ready);
        expect(state.playing, isFalse);
        expect(state.error, contains('连续切换 10 首'));
      },
    );
  }

  test('a shorter failed queue still pauses at its tail', () async {
    final harness = await _Harness.create(loadFailures: 1000);
    addTearDown(harness.dispose);
    final queue = _remoteQueue(4);
    await harness.controller.playFromHistoryQueue(queue.first, queue);
    final state = harness.container.read(playerControllerProvider);
    expect(state.queueIndex, 3);
    expect(harness.resolver.requestedQualities, hasLength(4));
    expect(state.processingState, PlayerProcessingState.ready);
    expect(state.error, isNot(contains('连续切换 10 首')));
  });

  test(
    'auto-play-on-startup resumes the persisted track automatically',
    () async {
      final snapshot = PlayerSessionSnapshot(
        track: PersistedPlayerTrack(
          id: 'kw:song-1:remote',
          kindCode: PersistedPlayerTrack.remoteKindCode,
          title: 'Test Song',
          artist: 'Test Singer',
          album: 'Test Album',
          sourceLabel: MusicSource.kw.label,
          qualityLabel: Quality.k128.code,
        ),
        music: _music(),
        qualityCode: Quality.k128.code,
        queuePlaylistId: 'restored-playlist',
      );
      SharedPreferences.setMockInitialValues({
        'auto_play_on_startup': true,
        playerSessionSnapshotStorageKey: jsonEncode(snapshot.toJson()),
      });

      final harness = await _Harness.create(loadFailures: 0);
      addTearDown(harness.dispose);

      await _waitUntil(() => harness.audio.playCount == 1);
      expect(harness.controller.queuePlaylistId, 'restored-playlist');
      expect(harness.audio.playing, isTrue);
      expect(harness.container.read(playerControllerProvider).track, isNotNull);
    },
  );

  test('a playback error retries only sources not already attempted', () async {
    final harness = await _Harness.create(loadFailures: 0);
    addTearDown(harness.dispose);

    await harness.controller.playFromMusic(_music());
    expect(
      harness.container.read(playerControllerProvider).track?.remoteUrl,
      'https://audio.test/first.mp3',
    );

    harness.audio.emitError(
      const bass.BassPlayerException(code: 1, message: 'stream failed'),
    );
    await _waitUntil(() => harness.audio.loadedUris.length == 2);
    final state = harness.container.read(playerControllerProvider);

    expect(harness.audio.loadedUris, [
      Uri.parse('https://audio.test/first.mp3'),
      Uri.parse('https://audio.test/second.mp3'),
    ]);
    expect(state.error, isNull);
    expect(state.track?.remoteUrl, 'https://audio.test/second.mp3');
  });

  test(
    'sleep timer pauses without losing the track or restarting a paused song',
    () async {
      final harness = await _Harness.create(loadFailures: 0);
      addTearDown(harness.dispose);
      await harness.controller.playFromMusic(_music());
      await harness.controller.seek(const Duration(seconds: 23));
      final track = harness.container.read(playerControllerProvider).track;

      await harness.controller.pauseForSleepTimer();
      expect(harness.audio.playing, isFalse);
      expect(harness.audio.position, const Duration(seconds: 23));
      expect(harness.container.read(playerControllerProvider).track, track);
      await harness.controller.pauseForSleepTimer();
      expect(harness.audio.playCount, 1);
      expect(harness.audio.playing, isFalse);

      await harness.controller.toggle();
      expect(harness.audio.playing, isTrue);
    },
  );

  test('sleep timer prevents a pending load from autoplaying', () async {
    final harness = await _Harness.create(loadFailures: 0);
    addTearDown(harness.dispose);
    final gate = Completer<void>();
    harness.audio.loadGate = gate;
    final loading = harness.controller.playFromMusic(_music());
    await _waitUntil(() => harness.audio.loadedUris.isNotEmpty);

    await harness.controller.pauseForSleepTimer();
    gate.complete();
    await loading;
    final state = harness.container.read(playerControllerProvider);
    expect(state.loading, isFalse);
    expect(state.track, isNotNull);
    expect(state.playing, isFalse);
    expect(harness.audio.playCount, 0);

    await harness.controller.toggle();
    expect(harness.audio.playCount, 1);
  });

  test(
    'sleep timer blocks late completion and errors until playback resumes',
    () async {
      final harness = await _Harness.create(loadFailures: 0);
      addTearDown(harness.dispose);
      await harness.controller.playFromMusic(_music());
      await harness.audio.setRepeatMode(AudioServiceRepeatMode.one);
      await harness.controller.pauseForSleepTimer();
      harness.audio.emitPlaybackState(bass.BassProcessingState.completed);
      harness.audio.emitError(
        const bass.BassPlayerException(code: 2, message: 'late error'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(harness.audio.playCount, 1);
      expect(harness.audio.loadedUris, hasLength(1));

      await harness.controller.toggle();
      harness.audio.emitPlaybackState(bass.BassProcessingState.buffering);
      harness.audio.emitPlaybackState(bass.BassProcessingState.ready);
      harness.audio.emitPlaybackState(bass.BassProcessingState.completed);
      await _waitUntil(() => harness.audio.playCount == 3);
    },
  );

  test(
    'sleep timer prevents an in-flight stall recovery from resuming',
    () async {
      final harness = await _Harness.create(
        loadFailures: 0,
        stallRecoveryDelay: const Duration(milliseconds: 20),
      );
      addTearDown(harness.dispose);
      await harness.controller.playFromMusic(_music());
      final gate = Completer<void>();
      harness.audio.pauseGate = gate;
      harness.audio.emitPlaybackState(bass.BassProcessingState.buffering);
      await _waitUntil(() => harness.audio.pauseCount == 1);
      harness.audio.pauseGate = null;
      await harness.controller.pauseForSleepTimer();
      gate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(harness.audio.playCount, 1);
      expect(harness.audio.playing, isFalse);
    },
  );

  test('network failures are told apart from song and source failures', () {
    MusicSourceAttemptFailure attempt(Object error) =>
        MusicSourceAttemptFailure(source: _record('first'), error: error);

    for (final error in <Object>[
      _hostLookupFailure,
      "DioException [connection error]: Failed host lookup: 'c.y.qq.com'",
      const bass.BassPlayerException(code: 32, message: 'no connection'),
      const bass.BassPlayerException(code: 40, message: 'no response'),
      const PlayerLoadTimeoutException(Duration(seconds: 30)),
      const MusicSourceRuntimeException('音源解析超时'),
      TimeoutException('slow'),
      MusicSourceFallbackException([
        attempt(_hostLookupFailure),
        attempt(const bass.BassPlayerException(code: 32, message: 'x')),
      ]),
    ]) {
      expect(isNetworkFailure(error), isTrue, reason: '$error');
    }
    for (final error in <Object>[
      const bass.BassPlayerException(code: 41, message: 'unsupported file'),
      const bass.BassPlayerException(code: 2, message: 'HTTP 403'),
      const MusicSourceRuntimeException('音源没有返回播放地址'),
      const MusicSourceFallbackException([]),
      // Another source answering that it lacks the song proves the network.
      MusicSourceFallbackException([
        attempt(_hostLookupFailure),
        attempt(const MusicSourceRuntimeException('暂无版权')),
      ]),
    ]) {
      expect(isNetworkFailure(error), isFalse, reason: '$error');
    }

    for (final error in <Object>[
      const bass.BassPlayerException(code: 9, message: 'audio output could not start'),
      const bass.BassPlayerException(code: 23, message: 'illegal device'),
      const bass.BassPlayerException(code: 3, message: 'driver error'),
      const bass.BassPlayerException(code: 11, message: 'device reinit'),
      'BASS play error 9: audio output could not start',
      'output device failed',
    ]) {
      expect(isAudioOutputFailure(error), isTrue, reason: '$error');
    }
    for (final error in <Object>[
      const bass.BassPlayerException(code: 32, message: 'no network'),
      const bass.BassPlayerException(code: 2, message: 'HTTP 403'),
      const MusicSourceRuntimeException('暂无版权'),
    ]) {
      expect(isAudioOutputFailure(error), isFalse, reason: '$error');
    }
  });

  test(
    'audio output failure stays on the song instead of skipping the queue',
    () async {
      final harness = await _Harness.create(loadFailures: 0);
      addTearDown(harness.dispose);
      harness.audio.playError = const bass.BassPlayerException(
        code: 9,
        operation: 'play',
        message: 'audio output could not start',
      );
      final queue = _remoteQueue(30);

      await harness.controller.playFromHistoryQueue(queue.first, queue);
      final state = harness.container.read(playerControllerProvider);

      expect(state.queueIndex, 0);
      expect(state.track?.id, 'kw:song-0:remote');
      expect(state.loading, isFalse);
      expect(state.playing, isFalse);
      expect(state.error, contains('音频输出设备不可用'));
    },
  );

  test(
    'losing the network stays on the song instead of skipping the queue',
    () async {
      final harness = await _Harness.create(loadFailures: 0);
      addTearDown(harness.dispose);
      harness.resolver.resolveError = _hostLookupFailure;
      final queue = _remoteQueue(30);

      await harness.controller.playFromHistoryQueue(queue.first, queue);
      final state = harness.container.read(playerControllerProvider);

      expect(state.queueIndex, 0);
      expect(state.track?.id, 'kw:song-0:remote');
      expect(state.loading, isFalse);
      expect(state.playing, isFalse);
      expect(state.error, contains('网络不可用'));
      expect(harness.audio.hasPendingSourceRetry, isTrue);
      expect(harness.resolver.requestedQualities, hasLength(1));
    },
  );

  test('finishing a song without a network waits on the next one', () async {
    final harness = await _Harness.create(loadFailures: 0);
    addTearDown(harness.dispose);
    final queue = _remoteQueue(30);
    await harness.controller.playFromHistoryQueue(queue.first, queue);
    harness.resolver.resolveError = _hostLookupFailure;

    harness.audio.emitPlaybackState(bass.BassProcessingState.completed);
    await _waitUntil(() => harness.audio.hasPendingSourceRetry);

    final state = harness.container.read(playerControllerProvider);
    expect(state.queueIndex, 1);
    expect(state.loading, isFalse);
    expect(harness.resolver.requestedQualities, hasLength(2));
  });

  test('the system reporting no network prevents skipping any error', () async {
    final harness = await _Harness.create(loadFailures: 1000);
    addTearDown(harness.dispose);
    harness.audio.offline = true;
    final queue = _remoteQueue(30);

    await harness.controller.playFromHistoryQueue(queue.first, queue);

    final state = harness.container.read(playerControllerProvider);
    expect(state.queueIndex, 0);
    expect(state.error, contains('网络不可用'));
  });

  test('a usable network resumes the song waiting for it', () async {
    final harness = await _Harness.create(loadFailures: 0);
    addTearDown(harness.dispose);
    harness.resolver.resolveError = _hostLookupFailure;
    final queue = _remoteQueue(30);
    await harness.controller.playFromHistoryQueue(queue.first, queue);
    expect(harness.audio.playCount, 0);

    harness.resolver.resolveError = null;
    harness.audio.emitNetworkUsable(false);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(harness.audio.playCount, 0);
    harness.audio.emitNetworkUsable(true);

    await _waitUntil(() => harness.audio.playCount == 1);
    final state = harness.container.read(playerControllerProvider);
    expect(state.queueIndex, 0);
    expect(state.error, isNull);
    expect(harness.audio.hasPendingSourceRetry, isFalse);
  });

  test(
    'a network that never reports recovery is retried without new notices',
    () async {
      final harness = await _Harness.create(
        loadFailures: 0,
        networkRetryInterval: const Duration(milliseconds: 10),
      );
      addTearDown(harness.dispose);
      final notices = <String>[];
      // The player page shows a toast each time the error text changes.
      final subscription = harness.container.listen<PlayerState>(
        playerControllerProvider,
        (previous, next) {
          if (next.error != null && next.error != previous?.error) {
            notices.add(next.error!);
          }
        },
      );
      addTearDown(subscription.close);
      harness.resolver.resolveError = _hostLookupFailure;

      await harness.controller.playFromMusic(_music());
      await _waitUntil(() => harness.resolver.requestedQualities.length >= 4);

      expect(notices, hasLength(1));
      expect(harness.container.read(playerControllerProvider).error, isNull);
      harness.resolver.resolveError = null;
      await _waitUntil(() => harness.audio.playCount == 1);
      expect(harness.audio.hasPendingSourceRetry, isFalse);
    },
  );

  test('no retries run while the system has no network', () async {
    final harness = await _Harness.create(
      loadFailures: 0,
      networkRetryInterval: const Duration(milliseconds: 5),
    );
    addTearDown(harness.dispose);
    harness.audio.offline = true;
    harness.resolver.resolveError = _hostLookupFailure;

    await harness.controller.playFromMusic(_music());
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(harness.resolver.requestedQualities, hasLength(1));

    harness.audio.offline = false;
    harness.resolver.resolveError = null;
    harness.audio.emitNetworkUsable(true);
    await _waitUntil(() => harness.audio.playCount == 1);
  });

  test('losing the network mid-song retries from the same position', () async {
    final harness = await _Harness.create(loadFailures: 0);
    addTearDown(harness.dispose);
    await harness.controller.playFromMusic(_music());
    harness.audio.emitPosition(const Duration(seconds: 42));
    harness.resolver.resolveError = _hostLookupFailure;

    // A BASS HTTP stream that broke off reports an error rather than an end.
    harness.audio.emitError(
      const bass.BassPlayerException(
        code: 45,
        message: 'network stream ended before the track finished',
        operation: 'stream-ended',
      ),
    );
    await _waitUntil(() => harness.audio.hasPendingSourceRetry);

    final waiting = harness.container.read(playerControllerProvider);
    expect(waiting.position, const Duration(seconds: 42));
    expect(waiting.duration, const Duration(minutes: 3));
    expect(waiting.track?.id, 'kw:song-1:remote');

    harness.resolver.resolveError = null;
    harness.audio.emitNetworkUsable(true);
    await _waitUntil(
      () => harness.audio.seekPositions.contains(const Duration(seconds: 42)),
    );
    await _waitUntil(() => harness.audio.playing);
    expect(harness.audio.hasPendingSourceRetry, isFalse);
  });

  test('tapping play on a waiting song retries it at once', () async {
    final harness = await _Harness.create(
      loadFailures: 0,
      networkRetryInterval: const Duration(hours: 1),
    );
    addTearDown(harness.dispose);
    harness.resolver.resolveError = _hostLookupFailure;
    await harness.controller.playFromMusic(_music());
    final notices = harness.container.read(playerControllerProvider).error;
    expect(notices, contains('恢复后将自动继续播放'));

    await harness.audio.play();

    // A retry the user asked for reports its outcome again.
    expect(
      harness.container.read(playerControllerProvider).error,
      contains('恢复后将自动继续播放'),
    );
    expect(harness.resolver.requestedQualities, hasLength(2));
  });

  test(
    'stalling on network trouble neither restarts nor replaces the stream',
    () async {
      final harness = await _Harness.create(
        loadFailures: 0,
        stallRecoveryDelay: const Duration(milliseconds: 5),
      );
      addTearDown(harness.dispose);
      await harness.controller.playFromMusic(_music());
      harness.audio.networkTrouble = true;
      final plays = harness.audio.playCount;

      harness.audio.emitPlaybackState(bass.BassProcessingState.buffering);
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(harness.audio.pauseCount, 0);
      expect(harness.audio.playCount, plays);
      expect(harness.audio.loadedUris, hasLength(1));
      expect(harness.container.read(playerControllerProvider).error, isNull);

      harness.audio.networkTrouble = false;
      harness.audio.emitPlaybackState(bass.BassProcessingState.ready);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(harness.audio.pauseCount, 0);
      expect(harness.audio.loadedUris, hasLength(1));
    },
  );

  test(
    'a very long network stall pauses and resumes once the network returns',
    () async {
      final harness = await _Harness.create(
        loadFailures: 0,
        stallRecoveryDelay: const Duration(milliseconds: 5),
        networkStallPauseDelay: const Duration(milliseconds: 20),
      );
      addTearDown(harness.dispose);
      await harness.controller.playFromMusic(_music());
      harness.audio.networkTrouble = true;
      final plays = harness.audio.playCount;

      harness.audio.emitPlaybackState(bass.BassProcessingState.buffering);
      await _waitUntil(() => harness.audio.pauseCount == 1);
      await _waitUntil(
        () =>
            harness.container
                .read(playerControllerProvider)
                .error
                ?.contains('已暂停') ??
            false,
      );
      expect(harness.audio.loadedUris, hasLength(1));

      harness.audio.networkTrouble = false;
      harness.audio.emitNetworkUsable(true);
      await _waitUntil(() => harness.audio.playCount == plays + 1);
      expect(harness.audio.loadedUris, hasLength(1));
    },
  );

  test('recovery while the stall limit pauses still resumes', () async {
    final harness = await _Harness.create(
      loadFailures: 0,
      stallRecoveryDelay: const Duration(milliseconds: 5),
      networkStallPauseDelay: const Duration(milliseconds: 5),
    );
    addTearDown(harness.dispose);
    await harness.controller.playFromMusic(_music());
    harness.audio.networkTrouble = true;
    final gate = Completer<void>();
    harness.audio.pauseGate = gate;
    final plays = harness.audio.playCount;

    harness.audio.emitPlaybackState(bass.BassProcessingState.buffering);
    await _waitUntil(() => harness.audio.pauseCount == 1);
    harness.audio.networkTrouble = false;
    harness.audio.emitNetworkUsable(true);
    gate.complete();

    await _waitUntil(() => harness.audio.playCount == plays + 1);
    expect(harness.container.read(playerControllerProvider).error, isNull);
  });

  test('pausing by hand cancels the automatic network resume', () async {
    final harness = await _Harness.create(
      loadFailures: 0,
      stallRecoveryDelay: const Duration(milliseconds: 5),
      networkStallPauseDelay: const Duration(milliseconds: 5),
    );
    addTearDown(harness.dispose);
    await harness.controller.playFromMusic(_music());
    harness.audio.networkTrouble = true;
    harness.audio.emitPlaybackState(bass.BassProcessingState.buffering);
    await _waitUntil(() => harness.audio.pauseCount == 1);
    await _waitUntil(
      () => harness.container.read(playerControllerProvider).error != null,
    );

    await harness.controller.toggle();
    await harness.controller.toggle();
    final plays = harness.audio.playCount;
    harness.audio.networkTrouble = false;
    harness.audio.emitNetworkUsable(true);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(harness.audio.playCount, plays);
    expect(harness.audio.playing, isFalse);
  });

  test('the sleep timer cancels waiting for the network', () async {
    final harness = await _Harness.create(
      loadFailures: 0,
      networkRetryInterval: const Duration(milliseconds: 5),
    );
    addTearDown(harness.dispose);
    harness.resolver.resolveError = _hostLookupFailure;
    await harness.controller.playFromMusic(_music());

    await harness.controller.pauseForSleepTimer();
    final attempts = harness.resolver.requestedQualities.length;
    harness.resolver.resolveError = null;
    harness.audio.emitNetworkUsable(true);
    await Future<void>.delayed(const Duration(milliseconds: 40));

    expect(harness.resolver.requestedQualities, hasLength(attempts));
    expect(harness.audio.playing, isFalse);
  });

  test('a stall fallback that finds nothing keeps the song', () async {
    final harness = await _Harness.create(
      loadFailures: 0,
      stallRecoveryDelay: const Duration(milliseconds: 5),
    );
    addTearDown(harness.dispose);
    final queue = _remoteQueue(5);
    await harness.controller.playFromHistoryQueue(queue.first, queue);
    harness.audio.emitPosition(const Duration(seconds: 42));
    harness.audio.loadFailures = 1000;
    final plays = harness.audio.playCount;

    harness.audio.emitPlaybackState(bass.BassProcessingState.buffering);
    await _waitUntil(() => harness.audio.playCount == plays + 1);
    harness.audio.emitPlaybackState(bass.BassProcessingState.buffering);
    await _waitUntil(() => harness.audio.hasPendingSourceRetry);

    final state = harness.container.read(playerControllerProvider);
    expect(state.queueIndex, 0);
    expect(state.position, const Duration(seconds: 42));
    expect(state.loading, isFalse);
  });

  test('a download failing during a pause does not start playback', () async {
    final harness = await _Harness.create(loadFailures: 0);
    addTearDown(harness.dispose);
    await harness.controller.playFromMusic(_music());
    harness.audio.emitPosition(const Duration(seconds: 42));
    await harness.audio.pause();
    final plays = harness.audio.playCount;

    harness.audio.emitError(
      const bass.BassPlayerException(
        code: 2,
        message: 'HTTP 403',
        operation: 'source-expired',
      ),
    );
    await _waitUntil(
      () =>
          harness.audio.loadedUris.length == 2 &&
          !harness.container.read(playerControllerProvider).loading,
    );

    expect(harness.audio.playCount, plays);
    expect(harness.audio.playing, isFalse);
    expect(harness.audio.seekPositions.last, const Duration(seconds: 42));
  });

  test(
    'a stream ending early resumes even though it stopped playing',
    () async {
      final harness = await _Harness.create(loadFailures: 0);
      addTearDown(harness.dispose);
      await harness.controller.playFromMusic(_music());
      harness.audio.emitPosition(const Duration(seconds: 42));
      await harness.audio.pause();
      final plays = harness.audio.playCount;

      harness.audio.emitError(
        const bass.BassPlayerException(
          code: 45,
          message: 'network stream ended before the track finished',
          operation: 'stream-ended',
        ),
      );
      await _waitUntil(() => harness.audio.playCount == plays + 1);

      expect(harness.audio.loadedUris, hasLength(2));
      expect(harness.audio.seekPositions.last, const Duration(seconds: 42));
    },
  );

  test(
    'an expired link asks the same source again before failing over',
    () async {
      final harness = await _Harness.create(loadFailures: 0);
      addTearDown(harness.dispose);
      await harness.controller.playFromMusic(_music());
      harness.audio.emitPosition(const Duration(seconds: 42));
      const expired = bass.BassPlayerException(
        code: 2,
        message: 'HTTP 403',
        operation: 'source-expired',
      );

      harness.audio.emitError(expired);
      await _waitUntil(
        () =>
            harness.audio.loadedUris.length == 2 &&
            !harness.container.read(playerControllerProvider).loading,
      );
      expect(
        harness.audio.loadedUris.last,
        Uri.parse('https://audio.test/first.mp3'),
      );
      expect(harness.audio.seekPositions.last, const Duration(seconds: 42));

      // A fresh link that is refused at once means the source itself is failing.
      harness.audio.emitError(expired);
      await _waitUntil(
        () =>
            harness.audio.loadedUris.length == 3 &&
            !harness.container.read(playerControllerProvider).loading,
      );
      expect(
        harness.audio.loadedUris.last,
        Uri.parse('https://audio.test/second.mp3'),
      );
    },
  );

  test('brief buffering resumes without watchdog interference', () async {
    AppLogger.configureRecording(await SharedPreferences.getInstance());
    await AppLogger.setRecordingCategories({AppLogCategory.playback});
    addTearDown(() => AppLogger.setRecordingCategories({}));
    final harness = await _Harness.create(
      loadFailures: 0,
      stallRecoveryDelay: const Duration(milliseconds: 40),
    );
    addTearDown(harness.dispose);

    await harness.controller.playFromMusic(_music());
    final logStart = AppLogger.recentMemoryLines.length;
    final playCount = harness.audio.playCount;
    harness.audio.emitPlaybackState(bass.BassProcessingState.buffering);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    harness.audio.emitPlaybackState(bass.BassProcessingState.ready);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(harness.audio.pauseCount, 0);
    expect(harness.audio.playCount, playCount);
    expect(
      harness.container.read(playerControllerProvider).processingState,
      PlayerProcessingState.ready,
    );
    final logs = AppLogger.recentMemoryLines.skip(logStart).join('\n');
    expect(logs, contains('[player-playback] buffering_start'));
    expect(logs, contains('[player-playback] buffering_end'));
    expect(logs, isNot(contains('https://audio.test')));
  });

  test(
    'prolonged buffering restarts once then resumes from a fallback',
    () async {
      final harness = await _Harness.create(
        loadFailures: 0,
        stallRecoveryDelay: const Duration(milliseconds: 10),
      );
      addTearDown(harness.dispose);

      await harness.controller.playFromMusic(_music());
      await harness.controller.seek(const Duration(seconds: 42));
      final playCount = harness.audio.playCount;

      harness.audio.emitPlaybackState(bass.BassProcessingState.buffering);
      await _waitUntil(
        () =>
            harness.audio.pauseCount == 1 &&
            harness.audio.playCount == playCount + 1,
      );

      harness.audio.emitPlaybackState(bass.BassProcessingState.buffering);
      await _waitUntil(
        () =>
            harness.audio.loadedUris.length == 2 &&
            harness.container.read(playerControllerProvider).track?.remoteUrl ==
                'https://audio.test/second.mp3',
      );

      expect(
        harness.audio.loadedUris.last,
        Uri.parse('https://audio.test/second.mp3'),
      );
      expect(harness.audio.seekPositions.last, const Duration(seconds: 42));
      expect(harness.container.read(playerControllerProvider).error, isNull);
    },
  );

  test('quality switch keeps position, lyrics, and paused state', () async {
    final harness = await _Harness.create(loadFailures: 0);
    addTearDown(harness.dispose);

    await harness.controller.playFromMusic(_music());
    await _waitUntil(
      () => harness.container.read(playerControllerProvider).lyricInfo != null,
    );
    await harness.controller.seek(const Duration(seconds: 42));
    final before = harness.container.read(playerControllerProvider);
    final lyricsBefore = before.lyrics;
    final lyricLoadsBefore = harness.api.lyricLoadCount;

    expect(before.playing, isFalse);
    expect(before.track?.availableQualities, contains(Quality.k320));
    expect(await harness.controller.switchQuality(Quality.k320), isTrue);

    final after = harness.container.read(playerControllerProvider);
    expect(after.track?.qualityLabel, Quality.k320.code);
    expect(after.position, const Duration(seconds: 42));
    expect(identical(after.lyrics, lyricsBefore), isTrue);
    expect(after.playing, isFalse);
    expect(harness.api.lyricLoadCount, lyricLoadsBefore);
    expect(harness.resolver.requestedQualities, [Quality.k128, Quality.k320]);
  });

  test(
    'quality switch succeeds even if restore seek fails with error 7',
    () async {
      final harness = await _Harness.create(loadFailures: 0);
      addTearDown(harness.dispose);

      await harness.controller.playFromMusic(_music());
      await _waitUntil(
        () =>
            harness.container.read(playerControllerProvider).lyricInfo != null,
      );
      await harness.controller.seek(const Duration(seconds: 42));
      expect(
        harness.container
            .read(playerControllerProvider)
            .track
            ?.availableQualities,
        contains(Quality.k320),
      );

      // Simulate seek error 7 on next seek (restore seek)
      harness.audio.failNextSeek = true;

      expect(await harness.controller.switchQuality(Quality.k320), isTrue);

      final after = harness.container.read(playerControllerProvider);
      expect(after.track?.qualityLabel, Quality.k320.code);
      expect(harness.resolver.requestedQualities, [Quality.k128, Quality.k320]);
    },
  );

  test('failed quality switch keeps the previous quality retryable', () async {
    final harness = await _Harness.create(loadFailures: 0);
    addTearDown(harness.dispose);

    await harness.controller.playFromMusic(_music());
    harness.resolver.failingQualities.add(Quality.k320);

    expect(await harness.controller.switchQuality(Quality.k320), isFalse);
    expect(
      harness.container.read(playerControllerProvider).track?.qualityLabel,
      Quality.k128.code,
    );

    expect(await harness.controller.switchQuality(Quality.k320), isFalse);
    expect(harness.resolver.requestedQualities, [
      Quality.k128,
      Quality.k320,
      Quality.k320,
    ]);
  });

  test('enqueue next stays next when shuffle mode is active', () async {
    final harness = await _Harness.create(loadFailures: 0);
    addTearDown(harness.dispose);
    final directory = await Directory.systemTemp.createTemp(
      'cyshine-player-shuffle-next-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final entries = <DownloadHistoryEntry>[];
    for (final id in ['current', 'other-a', 'other-b', 'forced-next']) {
      final file = File('${directory.path}${Platform.pathSeparator}$id.mp3');
      await file.writeAsBytes(const [0]);
      entries.add(_localEntry(id, file.path));
    }

    await harness.controller.playFromHistoryQueue(entries.first, entries);
    harness.controller.setPlaybackMode(PlayerPlaybackMode.shuffle);
    await harness.controller.enqueueNext(entries.last);
    await harness.controller.playNext();

    final state = harness.container.read(playerControllerProvider);
    expect(state.track?.localPath, entries.last.savedPath);
    expect(state.queue[state.queueIndex].id, 'forced-next');
  });

  test(
    'shuffle next enters an enqueued queue after standalone playback',
    () async {
      final harness = await _Harness.create(loadFailures: 0);
      addTearDown(harness.dispose);
      final directory = await Directory.systemTemp.createTemp(
        'cyshine-player-standalone-next-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File(
        '${directory.path}${Platform.pathSeparator}forced-next.mp3',
      );
      await file.writeAsBytes(const [0]);
      final next = _localEntry('forced-next', file.path);

      await harness.controller.playFromMusic(_music());
      harness.controller.setPlaybackMode(PlayerPlaybackMode.shuffle);
      await harness.controller.enqueueNext(next);
      await harness.controller.playNext();

      final state = harness.container.read(playerControllerProvider);
      expect(state.track?.localPath, next.savedPath);
      expect(state.queueIndex, 0);
    },
  );

  test('playlist queue expands without restarting the active track', () async {
    final harness = await _Harness.create(loadFailures: 0);
    addTearDown(harness.dispose);
    final directory = await Directory.systemTemp.createTemp(
      'cyshine-player-expand-queue-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final expanded = <DownloadHistoryEntry>[];
    for (var index = 1; index <= 5; index++) {
      final file = File(
        '${directory.path}${Platform.pathSeparator}track-$index.mp3',
      );
      await file.writeAsBytes(const [0]);
      expanded.add(_localEntry('track-$index', file.path));
    }
    final initial = expanded.take(3).toList(growable: false);

    await harness.controller.playFromPlaylistQueue(
      initial[1],
      initial,
      playlistId: 'source-a',
    );
    final before = harness.container.read(playerControllerProvider);
    final loadedBefore = harness.audio.loadedUris.length;

    expect(
      harness.controller.expandPlaylistQueue(
        expectedQueue: initial,
        expandedQueue: expanded,
      ),
      isTrue,
    );

    final after = harness.container.read(playerControllerProvider);
    expect(after.queue, hasLength(5));
    expect(after.queueIndex, 1);
    expect(after.queue[after.queueIndex].id, 'track-2');
    expect(after.track?.id, before.track?.id);
    expect(harness.audio.loadedUris, hasLength(loadedBefore));
    expect(harness.controller.queuePlaylistId, 'source-a');
    await harness.controller.playNext();
    expect(harness.controller.queuePlaylistId, 'source-a');
    // Starting the same song from another collection updates the queue too.
    await harness.controller.playFromPlaylistQueue(expanded[2], [
      expanded[2],
    ], playlistId: 'source-b');
    expect(harness.controller.queuePlaylistId, 'source-b');
    expect(
      harness.container.read(playerControllerProvider).queue,
      hasLength(1),
    );
    await harness.controller.playFromHistoryQueue(expanded[2], expanded);
    expect(harness.controller.queuePlaylistId, isNull);
  });
}

class _Harness {
  _Harness({
    required this.container,
    required this.audio,
    required this.resolver,
    required this.api,
  });

  final ProviderContainer container;
  final _FakeAudioHandler audio;
  final _ScriptedResolver resolver;
  final _FakeMusicApi api;

  PlayerController get controller =>
      container.read(playerControllerProvider.notifier);

  static Future<_Harness> create({
    required int loadFailures,
    Duration stallRecoveryDelay = const Duration(seconds: 12),
    Duration networkRetryInterval = const Duration(hours: 1),
    Duration networkStallPauseDelay = const Duration(hours: 1),
  }) async {
    final preferences = await SharedPreferences.getInstance();
    final audio = _FakeAudioHandler(loadFailures: loadFailures);
    final resolver = _ScriptedResolver([_record('first'), _record('second')]);
    final api = _FakeMusicApi();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        playerAudioHandlerProvider.overrideWithValue(audio),
        musicUrlResolverProvider.overrideWithValue(resolver),
        musicApiProvider.overrideWithValue(api),
        playbackStallRecoveryDelayProvider.overrideWithValue(
          stallRecoveryDelay,
        ),
        playbackNetworkRetryIntervalProvider.overrideWithValue(
          networkRetryInterval,
        ),
        playbackNetworkStallPauseDelayProvider.overrideWithValue(
          networkStallPauseDelay,
        ),
      ],
    );
    container.read(playerControllerProvider);
    return _Harness(
      container: container,
      audio: audio,
      resolver: resolver,
      api: api,
    );
  }

  Future<void> dispose() async {
    container.dispose();
    await audio.disposeHandler();
  }
}

class _ScriptedResolver implements MusicUrlResolver {
  _ScriptedResolver(this.sources);

  final List<MusicSourceRecord> sources;
  final List<String> attemptedIds = [];
  final List<Quality> requestedQualities = [];
  final Set<Quality> failingQualities = {};
  Object? resolveError;

  @override
  Future<Quality> highestQualityFor(MusicInfo music) async => Quality.k128;

  @override
  Future<MusicUrl> resolve({
    required MusicInfo music,
    required Quality quality,
  }) async {
    final result = await useFirstAvailable<MusicUrl>(
      music: music,
      quality: quality,
      use: (_, url) async => url,
    );
    return result.value;
  }

  @override
  Future<MusicSourceFallbackResult<T>> useFirstAvailable<T>({
    required MusicInfo music,
    required Quality quality,
    required MusicSourceUrlConsumer<T> use,
    Set<String> excludedSourceIds = const <String>{},
    bool Function()? isCancelled,
    bool Function(Object error)? shouldFallbackOnConsumerError,
  }) async {
    requestedQualities.add(quality);
    final failures = <MusicSourceAttemptFailure>[];
    final attempted = <String>[];
    for (final source in sources) {
      if (excludedSourceIds.contains(source.id)) continue;
      if (isCancelled?.call() ?? false) {
        throw const MusicSourceFallbackCancelledException();
      }
      attempted.add(source.id);
      attemptedIds.add(source.id);
      try {
        if (resolveError != null) throw resolveError!;
        if (failingQualities.contains(quality)) {
          throw const MusicSourceRuntimeException('quality unavailable');
        }
        final url = MusicUrl(
          url: 'https://audio.test/${source.id}.mp3',
          type: quality,
        );
        final value = await use(source, url);
        return MusicSourceFallbackResult(
          source: source,
          value: value,
          attemptedSourceIds: List.unmodifiable(attempted),
        );
      } on MusicSourceFallbackCancelledException {
        rethrow;
      } catch (error) {
        failures.add(MusicSourceAttemptFailure(source: source, error: error));
      }
    }
    if (failures.isEmpty) {
      throw const MusicSourceRuntimeException('没有更多可用的备用音源');
    }
    throw MusicSourceFallbackException(failures);
  }
}

class _FakeAudioHandler extends PlayerAudioHandler {
  _FakeAudioHandler({required this.loadFailures});

  int loadFailures;
  final List<Uri> loadedUris = [];
  final StreamController<bass.BassPlayerException> _errors =
      StreamController<bass.BassPlayerException>.broadcast(sync: true);
  final StreamController<bass.BassPlaybackSnapshot> _states =
      StreamController<bass.BassPlaybackSnapshot>.broadcast(sync: true);
  final StreamController<Duration> _positions =
      StreamController<Duration>.broadcast(sync: true);
  final StreamController<bool> _network = StreamController<bool>.broadcast(
    sync: true,
  );
  bool offline = false;
  bool networkTrouble = false;
  PlayerTransportCallback? _sourceRetry;
  int failTransitionCount = 0;
  int playCount = 0;
  int pauseCount = 0;
  Object? playError;
  Completer<void>? loadGate;
  Completer<void>? pauseGate;
  bool failNextSeek = false;
  final List<Duration> seekPositions = [];
  Duration? _duration;
  Duration _position = Duration.zero;
  bool _playing = false;
  bass.BassProcessingState _processingState = bass.BassProcessingState.idle;

  @override
  Stream<Duration> get positionStream => _positions.stream;

  @override
  Stream<bool> get networkUsableStream => _network.stream;

  @override
  bool get isOffline => offline;

  @override
  bool get hasNetworkTrouble => offline || networkTrouble;

  @override
  bool get hasPendingSourceRetry => _sourceRetry != null;

  @override
  Stream<Duration?> get durationStream => const Stream<Duration?>.empty();

  @override
  Stream<bass.BassPlaybackSnapshot> get playerStateStream => _states.stream;

  @override
  Stream<bass.BassPlayerException> get errorStream => _errors.stream;

  @override
  Duration get position => _position;

  @override
  Duration? get duration => _duration;

  @override
  bool get playing => _playing;

  @override
  bass.BassProcessingState get processingState => _processingState;

  @override
  Future<void> beginTrackTransition({
    required MediaItem item,
    int? queueIndex,
  }) async {
    _sourceRetry = null;
    _playing = false;
    _processingState = bass.BassProcessingState.loading;
  }

  @override
  Future<Duration?> load({
    required MediaItem item,
    required Uri sourceUri,
    int? queueIndex,
  }) async {
    loadedUris.add(sourceUri);
    await loadGate?.future;
    if (loadedUris.length <= loadFailures) {
      throw const bass.BassPlayerException(code: 1, message: 'load failed');
    }
    _duration = const Duration(minutes: 3);
    _processingState = bass.BassProcessingState.ready;
    return _duration;
  }

  @override
  Future<void> play() async {
    final retry = _sourceRetry;
    if (retry != null) {
      await retry();
      return;
    }
    if (playError != null) {
      final error = playError!;
      playError = null;
      throw error;
    }
    playCount++;
    _playing = true;
    _processingState = bass.BassProcessingState.ready;
  }

  @override
  Future<void> pause() async {
    pauseCount++;
    await pauseGate?.future;
    _playing = false;
    _processingState = bass.BassProcessingState.ready;
  }

  @override
  Future<void> seek(Duration position) async {
    if (failNextSeek) {
      failNextSeek = false;
      throw const bass.BassPlayerException(
        code: 7,
        message: 'position is not seekable',
      );
    }
    _position = position;
    seekPositions.add(position);
  }

  @override
  void failTrackTransition(Object error) {
    failTransitionCount++;
  }

  @override
  void pauseAfterSourceFailure({
    required MediaItem item,
    required PlayerTransportCallback onRetry,
    int? queueIndex,
  }) {
    _sourceRetry = onRetry;
    super.pauseAfterSourceFailure(
      item: item,
      onRetry: onRetry,
      queueIndex: queueIndex,
    );
  }

  void emitPosition(Duration position) {
    _position = position;
    _positions.add(position);
  }

  void emitError(bass.BassPlayerException error) => _errors.add(error);

  void emitNetworkUsable(bool usable) => _network.add(usable);

  void emitPlaybackState(bass.BassProcessingState processingState) {
    _processingState = processingState;
    _states.add(
      bass.BassPlaybackSnapshot(
        playing: _playing,
        processingState: processingState,
        position: _position,
        bufferedPosition: _position,
        duration: _duration,
      ),
    );
  }

  @override
  Future<void> disposeHandler() async {
    await _positions.close();
    await _errors.close();
    await _states.close();
    await _network.close();
    await super.disposeHandler();
  }
}

class _FakeMusicApi extends MusicApi {
  int lyricLoadCount = 0;
  final coverResponses = <String, Completer<String?>>{};

  @override
  Future<LyricInfo> getLyric({required MusicInfo musicInfo}) async {
    lyricLoadCount++;
    return const LyricInfo(lyric: '[00:01.000]Test lyric');
  }

  @override
  Future<String?> getPicUrl({
    required MusicInfo musicInfo,
    bool preferCached = true,
  }) async => await coverResponses[musicInfo.id]?.future;
}

const _hostLookupFailure = MusicSourceRuntimeException(
  "The connection errored: Failed host lookup: 'source.test' This indicates "
  'an error which most likely cannot be solved by the library.',
);

Future<void> _waitUntil(bool Function() predicate) async {
  for (var attempt = 0; attempt < 50; attempt++) {
    if (predicate()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('condition was not reached');
}

MusicSourceRecord _record(String id) {
  return MusicSourceRecord(
    id: id,
    name: id,
    description: '',
    author: 'test',
    homepage: '',
    version: '1',
    origin: 'test',
    importedAt: DateTime.utc(2026, 7, 31),
    updatedAt: DateTime.utc(2026, 7, 31),
    capabilities: const {
      MusicSource.kw: [Quality.k320, Quality.k128],
    },
  );
}

MusicInfo _music() {
  return MusicInfo(
    id: 'song-1',
    name: 'Test Song',
    singer: 'Test Singer',
    source: MusicSource.kw,
    interval: '03:00',
    meta: const MusicMeta(
      songId: 'song-1',
      albumName: 'Test Album',
      qualitys: [QualityOption(type: Quality.k128)],
      raw: {},
    ),
    raw: const {},
  );
}

MusicInfo _neteaseMusic() {
  return MusicInfo(
    id: 'netease-song',
    name: 'NetEase Song',
    singer: 'Test Singer',
    source: MusicSource.wy,
    interval: '03:00',
    meta: const MusicMeta(
      songId: 'netease-song',
      albumName: 'Test Album',
      picUrl: 'http://p1.music.126.net/test/cover.jpg',
      qualitys: [QualityOption(type: Quality.k128)],
      raw: {},
    ),
    raw: const {},
  );
}

DownloadHistoryEntry _localEntry(String id, String path) {
  return DownloadHistoryEntry(
    id: id,
    musicId: id,
    name: id,
    singer: 'Test Singer',
    albumName: 'Test Album',
    sourceCode: MusicSource.kw.code,
    qualityCode: Quality.k128.code,
    status: DownloadHistoryStatus.completed,
    createdAt: DateTime.utc(2026, 8, 4),
    savedPath: path,
  );
}

List<DownloadHistoryEntry> _remoteQueue(int length) => [
  for (var index = 0; index < length; index++)
    DownloadHistoryEntry(
      id: 'remote-$index',
      musicId: 'song-$index',
      name: 'Song $index',
      singer: 'Test Singer',
      albumName: 'Test Album',
      sourceCode: 'kw',
      qualityCode: '128k',
      status: DownloadHistoryStatus.completed,
      createdAt: DateTime.utc(2026),
      musicJson: {
        'id': 'song-$index',
        'name': 'Song $index',
        'singer': 'Test Singer',
        'source': 'kw',
        'interval': '03:00',
        'meta': {
          'songId': 'song-$index',
          'albumName': 'Test Album',
          'qualitys': [
            {'type': '128k'},
          ],
        },
      },
    ),
];
