import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:audio_service/audio_service.dart'
    show AudioServiceRepeatMode, AudioServiceShuffleMode, MediaItem;
import 'package:bass_player/bass_player.dart'
    show BassPlaybackSnapshot, BassProcessingState;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/music_api.dart';
import '../../core/models/enums.dart';
import '../../core/models/lyric_info.dart';
import '../../core/models/music_info.dart';
import '../../core/music_sources/music_url_resolver.dart';
import '../../core/services/app_logger.dart';
import '../../core/services/tagger.dart';
import '../../core/storage/settings_store.dart';
import '../../core/ui/cover_image_source.dart';
import '../downloads/download_history_store.dart';
import '../equalizer/equalizer_store.dart';
import 'bluetooth_lyric_metadata.dart';
import 'lyric_parser.dart';
import 'player_audio_handler.dart';
import 'player_models.dart';
import 'player_session_snapshot.dart';
import 'player_session_store.dart';

export 'player_models.dart';

PlayerProcessingState _mapProcessingState(BassProcessingState value) =>
    switch (value) {
      BassProcessingState.idle => PlayerProcessingState.idle,
      BassProcessingState.loading => PlayerProcessingState.loading,
      BassProcessingState.buffering => PlayerProcessingState.buffering,
      BassProcessingState.ready => PlayerProcessingState.ready,
      BassProcessingState.completed => PlayerProcessingState.completed,
      BassProcessingState.error => PlayerProcessingState.idle,
    };

const _lyricLoadTimeout = Duration(seconds: 8);
const _embeddedTagReadTimeout = Duration(seconds: 8);
const _positionCheckpointInterval = Duration(seconds: 2);
const _stalledPlaybackRecoveryDelay = Duration(seconds: 12);
const _stallProgressResetThreshold = Duration(seconds: 1);

final playbackStallRecoveryDelayProvider = Provider<Duration>(
  (_) => _stalledPlaybackRecoveryDelay,
);

class PlayerController extends StateNotifier<PlayerState>
    with WidgetsBindingObserver {
  PlayerController(this._ref)
    : _audioHandler = _ref.read(playerAudioHandlerProvider),
      _sessionStore = PlayerSessionStore(_ref.read(sharedPreferencesProvider)),
      _stallRecoveryDelay = _ref.read(playbackStallRecoveryDelayProvider),
      super(const PlayerState()) {
    _audioHandler.bindTransportCallbacks(
      owner: this,
      onPrevious: playPrevious,
      onNext: playNext,
      onQueueItem: playQueueItem,
      onRepeatMode: _handleSystemRepeatMode,
      onShuffleMode: _handleSystemShuffleMode,
    );
    _subscriptions = [
      _audioHandler.positionStream.listen((position) {
        if (!mounted || _transportSuppressionToken != null) return;
        state = state.copyWith(position: position);
        _recordPlaybackProgress(position);
        _syncBluetoothMetadata();
        _schedulePositionCheckpoint();
      }),
      _audioHandler.durationStream.listen((duration) {
        if (!mounted || _transportSuppressionToken != null) return;
        state = state.copyWith(duration: duration ?? Duration.zero);
        _schedulePositionCheckpoint();
      }),
      _audioHandler.playerStateStream.listen((playerState) {
        if (!mounted || _transportSuppressionToken != null) return;
        final wasPlaying = state.playing;
        if (!wasPlaying &&
            playerState.playing &&
            playerState.processingState != BassProcessingState.completed) {
          _completionHandledForTrackId = null;
          _pausedBySleepTimer = false;
        }
        state = state.copyWith(
          playing: playerState.playing,
          processingState: _mapProcessingState(playerState.processingState),
        );
        _syncBluetoothMetadata();
        if ((wasPlaying && !playerState.playing) ||
            playerState.processingState == BassProcessingState.completed) {
          _persistPositionCheckpoint();
        }
        if (playerState.processingState == BassProcessingState.completed) {
          _autoAdvanceAfterCompletion();
        }
        _logPlaybackState(playerState);
        _updateStallRecovery(playerState);
      }),
      _audioHandler.errorStream.listen(_handlePlaybackError),
    ];
    _ref.listen<AppSettings>(settingsProvider, (previous, next) {
      if (previous?.allowMixWithOthers != next.allowMixWithOthers) {
        unawaited(_applyAudioMixingPreference(next.allowMixWithOthers));
      }
      if (previous?.bluetoothLyricEnabled != next.bluetoothLyricEnabled ||
          previous?.bluetoothFullLyricEnabled !=
              next.bluetoothFullLyricEnabled) {
        _syncBluetoothMetadata(force: true);
      }
    });
    _ref.listen<EqualizerSettings>(equalizerProvider, (_, next) {
      _scheduleEqualizerApply(next);
    }, fireImmediately: true);
    WidgetsBinding.instance.addObserver(this);

    final restored = _sessionStore.read();
    if (restored == null) {
      _publishPlaybackMode();
    } else {
      _pendingRestoredSession = restored;
      _hydrateRestoredSession(restored);
      unawaited(_restorePersistedSession(restored));
    }
  }

  Future<void> _applyAudioMixingPreference(bool value) async {
    try {
      await _audioHandler.setAllowMixWithOthers(value);
    } catch (error) {
      await AppLogger.write(
        'player',
        'apply shared playback setting failed: $error',
      );
    }
  }

  final Ref _ref;
  final PlayerAudioHandler _audioHandler;
  final PlayerSessionStore _sessionStore;
  final Duration _stallRecoveryDelay;
  late final List<StreamSubscription<Object?>> _subscriptions;
  Timer? _positionCheckpointTimer;
  Timer? _stallRecoveryTimer;
  Future<void> _persistChain = Future<void>.value();
  Object? _requestToken;
  Object? _transportSuppressionToken;
  PlayerSessionSnapshot? _pendingRestoredSession;
  MusicInfo? _currentMusic;
  Quality? _currentQuality;
  List<DownloadHistoryEntry> _queue = const [];
  int _queueIndex = -1;
  List<int> _playOrder = const [];
  int _playOrderCursor = -1;
  final math.Random _random = math.Random();
  String? _completionHandledForTrackId;
  Set<String> _attemptedRemoteSourceIds = <String>{};
  bool _lateSourceFallbackActive = false;
  int _sleepTimerPauseGeneration = 0;
  bool _pausedBySleepTimer = false;
  int _softStallRecoveryAttempts = 0;
  Duration _stallProgressAnchor = Duration.zero;
  BassProcessingState? _lastLoggedProcessingState;
  bool? _lastLoggedPlaying;
  Stopwatch? _bufferingStopwatch;
  final BluetoothLyricMetadataCoordinator _bluetoothLyricMetadata =
      BluetoothLyricMetadataCoordinator();

  MusicInfo? get currentMusic => _currentMusic;

  Future<void> playFromMusic(MusicInfo music, {Quality? quality}) async {
    _pendingRestoredSession = null;
    _clearQueue(syncState: false);
    await _playRemoteMusic(music, quality: quality);
  }

  Future<bool> _playRemoteMusic(
    MusicInfo music, {
    Quality? quality,
    bool autoPlay = true,
    Duration initialPosition = Duration.zero,
    PlayerTrack? restoredTrack,
    bool showErrors = true,
    bool preservePresentation = false,
    Set<String> excludedSourceIds = const <String>{},
  }) async {
    _completionHandledForTrackId = null;
    _pausedBySleepTimer = false;
    final pauseGeneration = _sleepTimerPauseGeneration;
    final token = Object();
    _requestToken = token;
    _transportSuppressionToken = token;
    final selectedQuality =
        quality ??
        music.playbackQualityFor(
          _ref.read(settingsProvider).onlinePlaybackQuality,
        );
    _currentMusic = music;
    _logPlayback(
      'load_start kind=remote music=${music.source.code}:${music.id} '
      'requestedQuality=${selectedQuality.code} '
      'initialPositionMs=${initialPosition.inMilliseconds} '
      'autoPlay=$autoPlay excludedSources=${excludedSourceIds.length}',
    );
    if (excludedSourceIds.isEmpty) {
      _attemptedRemoteSourceIds = <String>{};
    }
    final transitionTrack = PlayerTrack.fromMusic(
      music: music,
      quality: selectedQuality,
      url: '',
      coverUrl: music.meta.picUrl,
    );
    if (preservePresentation) {
      state = state.copyWith(
        track: restoredTrack ?? state.track,
        loading: true,
        playing: false,
        processingState: PlayerProcessingState.loading,
        canPlayPrevious: _canPlayPrevious,
        canPlayNext: _canPlayNext,
        queue: List<DownloadHistoryEntry>.unmodifiable(_queue),
        queueIndex: _queueIndex,
        error: null,
      );
    } else {
      state = state.beginTrackLoading(
        nextTrack: restoredTrack,
        canPlayPrevious: _canPlayPrevious,
        canPlayNext: _canPlayNext,
        queue: List<DownloadHistoryEntry>.unmodifiable(_queue),
        queueIndex: _queueIndex,
      );
    }

    await _beginAudioTransition(
      token,
      _buildMediaItem(
        transitionTrack,
        artUri: _networkArtworkUri(transitionTrack.coverUrl),
      ),
    );
    if (!identical(_requestToken, token)) return false;

    // Lyrics only depend on `music`, not on URL resolution/audio setup/cover.
    // Start them after the old transport is stopped so no old playback state
    // can leak back into the new track's loading screen.
    // A quality switch invalidates the previous request token. If lyrics were
    // still loading, restart that request so the preserved spinner can finish.
    if (!preservePresentation || state.lyricLoading) {
      unawaited(_loadLyricsForMusic(music, token, logPrefix: 'lyric load'));
    }

    try {
      final api = _ref.read(musicApiProvider);
      Future<String?> fetchCover() async {
        try {
          return await api.getPicUrl(musicInfo: music);
        } catch (_) {
          return music.meta.picUrl;
        }
      }

      final coverFuture = fetchCover();

      final fallback = await _ref
          .read(musicUrlResolverProvider)
          .useFirstAvailable(
            music: music,
            quality: selectedQuality,
            excludedSourceIds: excludedSourceIds,
            isCancelled: () => !identical(_requestToken, token),
            use: (_, resolved) async {
              if (resolved.url.trim().isEmpty) {
                throw Exception('音源没有返回播放地址');
              }
              final resolvedQuality = resolved.type ?? selectedQuality;
              final initialTrack = PlayerTrack.fromMusic(
                music: music,
                quality: resolvedQuality,
                url: resolved.url,
                coverUrl: music.meta.picUrl,
              );
              final initialItem = await _mediaItemForTrack(initialTrack);
              if (!identical(_requestToken, token)) {
                throw const MusicSourceFallbackCancelledException();
              }
              await _audioHandler.load(
                item: initialItem,
                sourceUri: Uri.parse(resolved.url),
                queueIndex: _hasCurrentQueueTrack ? _queueIndex : null,
              );
              return resolved;
            },
          );
      if (!identical(_requestToken, token)) return false;
      final resolved = fallback.value;
      final resolvedQuality = resolved.type ?? selectedQuality;
      _currentQuality = resolvedQuality;
      _attemptedRemoteSourceIds = {
        if (resolvedQuality == selectedQuality) ...excludedSourceIds,
        ...fallback.attemptedSourceIds,
      };
      final coverUrl = await coverFuture;
      if (!identical(_requestToken, token)) return false;

      final sourceQualities = fallback.source.qualitiesFor(music.source);
      final track = PlayerTrack.fromMusic(
        music: music,
        quality: resolvedQuality,
        url: resolved.url,
        coverUrl: coverUrl,
        availableQualities: sourceQualities.isEmpty
            ? music.sortedQualities.map((item) => item.type)
            : sourceQualities,
      );
      final finalItem = await _mediaItemForTrack(
        track,
        duration: _audioHandler.duration,
      );
      if (!identical(_requestToken, token)) return false;
      _endTransportSuppression(token);
      await _seekAfterRestore(initialPosition, token);
      if (!identical(_requestToken, token)) return false;
      state = state.copyWith(
        track: track,
        loading: false,
        playing: _audioHandler.playing,
        position: _audioHandler.position,
        duration: _audioHandler.duration ?? Duration.zero,
        processingState: _mapProcessingState(_audioHandler.processingState),
        error: null,
      );
      _logPlayback(
        'load_ready kind=remote music=${music.source.code}:${music.id} '
        'resolverSource=${fallback.source.id} quality=${resolvedQuality.code} '
        'attemptedSources=${fallback.attemptedSourceIds.join(',')} '
        'positionMs=${state.position.inMilliseconds} '
        'durationMs=${state.duration.inMilliseconds}',
      );
      _publishMediaMetadata(finalItem);
      _syncQueueAvailability();
      _persistFullSession();
      if (!identical(_requestToken, token)) return false;
      if (autoPlay && pauseGeneration == _sleepTimerPauseGeneration) {
        await _audioHandler.play();
        if (!identical(_requestToken, token)) return false;
      }
      return true;
    } on MusicSourceFallbackCancelledException {
      return false;
    } catch (e) {
      if (e is MusicSourceFallbackException) {
        _attemptedRemoteSourceIds.addAll(
          e.failures.map((failure) => failure.source.id),
        );
      }
      await AppLogger.write('player', 'play remote failed: $e');
      if (!identical(_requestToken, token)) return false;
      _audioHandler.failTrackTransition(e);
      _endTransportSuppression(token);
      state = state.copyWith(
        loading: false,
        lyricLoading: preservePresentation ? state.lyricLoading : false,
        playing: false,
        processingState: PlayerProcessingState.idle,
        error: showErrors ? describeDioError(e) : null,
      );
      return false;
    }
  }

  Future<bool> switchQuality(Quality quality) async {
    final music = _currentMusic;
    final track = state.track;
    if (music == null || track == null || track.isLocal || state.loading) {
      return false;
    }
    final current = _currentQuality ?? Quality.tryFromCode(track.qualityLabel);
    if (current == quality) return true;
    final available = track.availableQualities;
    if (available.isNotEmpty && !available.contains(quality)) return false;

    return _playRemoteMusic(
      music,
      quality: quality,
      autoPlay: state.playing,
      initialPosition: state.position,
      restoredTrack: track,
      preservePresentation: true,
    );
  }

  void _handlePlaybackError(Object error) {
    if (!mounted || _pausedBySleepTimer) return;
    if (_transportSuppressionToken != null ||
        _lateSourceFallbackActive ||
        state.loading) {
      // The active load pipeline owns this failure and reports it through its
      // own catch. Log it anyway so a stall that never reaches that catch is
      // not completely invisible.
      unawaited(
        AppLogger.write(
          'player',
          'playback error while loading (handled by load path): $error',
        ),
      );
      return;
    }
    final music = _currentMusic;
    final track = state.track;
    if (music == null || track == null || track.isLocal) return;

    final quality = _currentQuality;
    final position = state.position;
    final excluded = Set<String>.of(_attemptedRemoteSourceIds);
    final pauseGeneration = _sleepTimerPauseGeneration;
    _lateSourceFallbackActive = true;
    unawaited(() async {
      await AppLogger.write(
        'player',
        'active source playback failed, trying fallback: $error',
      );
      try {
        if (!mounted || pauseGeneration != _sleepTimerPauseGeneration) return;
        await _playRemoteMusic(
          music,
          quality: quality,
          initialPosition: position,
          restoredTrack: track,
          excludedSourceIds: excluded,
        );
      } finally {
        _lateSourceFallbackActive = false;
      }
    }());
  }

  void _updateStallRecovery(BassPlaybackSnapshot playerState) {
    final track = state.track;
    final stalled =
        !state.loading &&
        track != null &&
        !track.isLocal &&
        playerState.playing &&
        playerState.processingState == BassProcessingState.buffering;
    if (!stalled) {
      _cancelStallRecoveryTimer();
      return;
    }
    if (_stallRecoveryTimer?.isActive ?? false) return;

    final trackId = track.id;
    final requestToken = _requestToken;
    _stallRecoveryTimer = Timer(_stallRecoveryDelay, () {
      _stallRecoveryTimer = null;
      if (!mounted ||
          state.loading ||
          state.track?.id != trackId ||
          !identical(_requestToken, requestToken) ||
          !_audioHandler.playing ||
          _audioHandler.processingState != BassProcessingState.buffering) {
        return;
      }
      unawaited(_recoverStalledPlayback(trackId, requestToken));
    });
  }

  void _logPlaybackState(BassPlaybackSnapshot playerState) {
    final previousState = _lastLoggedProcessingState;
    final previousPlaying = _lastLoggedPlaying;
    if (previousState == playerState.processingState &&
        previousPlaying == playerState.playing) {
      return;
    }
    _lastLoggedProcessingState = playerState.processingState;
    _lastLoggedPlaying = playerState.playing;

    if (playerState.processingState == BassProcessingState.buffering &&
        previousState != BassProcessingState.buffering) {
      _bufferingStopwatch = Stopwatch()..start();
      _logPlayback('buffering_start ${_playbackLogContext(playerState)}');
      return;
    }

    if (previousState == BassProcessingState.buffering) {
      final stopwatch = _bufferingStopwatch;
      stopwatch?.stop();
      _bufferingStopwatch = null;
      _logPlayback(
        'buffering_end elapsedMs=${stopwatch?.elapsedMilliseconds ?? -1} '
        '${_playbackLogContext(playerState)}',
      );
      return;
    }

    _logPlayback('state_change ${_playbackLogContext(playerState)}');
  }

  String _playbackLogContext(BassPlaybackSnapshot playerState) {
    final track = state.track;
    final trackKind = track == null
        ? 'none'
        : track.isLocal
        ? 'local'
        : 'remote';
    final source = _singleLine(track?.sourceLabel ?? 'none');
    final quality = _singleLine(track?.qualityLabel ?? 'none');
    final title = _singleLine(track?.title ?? 'none');
    return 'state=${playerState.processingState.name} '
        'playing=${playerState.playing} positionMs=${playerState.position.inMilliseconds} '
        'bufferedMs=${playerState.bufferedPosition.inMilliseconds} '
        'durationMs=${playerState.duration?.inMilliseconds ?? -1} '
        'trackKind=$trackKind source=$source quality=$quality '
        'queueIndex=$_queueIndex title="$title"';
  }

  void _logPlayback(String message) {
    unawaited(AppLogger.write('player-playback', message));
  }

  String _singleLine(String value) =>
      value.replaceAll(RegExp(r'[\r\n]+'), ' ').replaceAll('"', "'").trim();

  Future<void> _recoverStalledPlayback(
    String trackId,
    Object? requestToken,
  ) async {
    final pauseGeneration = _sleepTimerPauseGeneration;
    if (_softStallRecoveryAttempts == 0) {
      _softStallRecoveryAttempts++;
      await AppLogger.write(
        'player',
        'playback stalled for ${_stallRecoveryDelay.inSeconds}s; '
            'restarting transport at ${state.position.inMilliseconds}ms',
      );
      try {
        if (!mounted || pauseGeneration != _sleepTimerPauseGeneration) return;
        await _audioHandler.pause();
        if (!mounted ||
            pauseGeneration != _sleepTimerPauseGeneration ||
            state.loading ||
            state.track?.id != trackId ||
            !identical(_requestToken, requestToken)) {
          return;
        }
        await _audioHandler.play();
      } catch (error) {
        _handlePlaybackError(error);
      }
      return;
    }

    _handlePlaybackError(
      TimeoutException('网络音频持续缓冲，自动切换备用音源', _stallRecoveryDelay),
    );
  }

  void _recordPlaybackProgress(Duration position) {
    final track = state.track;
    if (track == null ||
        track.isLocal ||
        !state.playing ||
        state.processingState != PlayerProcessingState.ready) {
      return;
    }
    final progress = position - _stallProgressAnchor;
    if (progress >= _stallProgressResetThreshold || progress.isNegative) {
      _softStallRecoveryAttempts = 0;
      _stallProgressAnchor = position;
    }
  }

  void _cancelStallRecoveryTimer() {
    _stallRecoveryTimer?.cancel();
    _stallRecoveryTimer = null;
  }

  void _resetStallRecovery({Duration position = Duration.zero}) {
    _cancelStallRecoveryTimer();
    _softStallRecoveryAttempts = 0;
    _stallProgressAnchor = position;
  }

  void _scheduleEqualizerApply(EqualizerSettings settings) {
    unawaited(
      _audioHandler.setEqualizer(settings.toBassConfiguration()).catchError((
        Object error,
        StackTrace stackTrace,
      ) {
        return AppLogger.write('player-equalizer', 'apply failed: $error');
      }),
    );
  }

  Future<void> playFromHistory(DownloadHistoryEntry entry) async {
    _pendingRestoredSession = null;
    _setQueueForEntry(entry);
    await _playLocal(
      PlayerTrack.fromHistory(entry),
      fallbackMusic: entry.musicInfo,
    );
  }

  Future<void> playFromHistoryQueue(
    DownloadHistoryEntry entry,
    List<DownloadHistoryEntry> queue,
  ) {
    return _playFromQueue(entry, queue);
  }

  Future<void> playFromPlaylistQueue(
    DownloadHistoryEntry entry,
    List<DownloadHistoryEntry> queue,
  ) {
    return _playFromQueue(entry, queue);
  }

  /// Replaces a playlist queue after its remaining tracks finish loading,
  /// without restarting or seeking the active track.
  ///
  /// The replacement is ignored when the user has switched or edited the
  /// queue since [expectedQueue] began loading.
  bool expandPlaylistQueue({
    required List<DownloadHistoryEntry> expectedQueue,
    required List<DownloadHistoryEntry> expandedQueue,
  }) {
    final expected = _playableQueue(expectedQueue);
    if (!_hasSameQueueIdentity(_queue, expected)) return false;

    final expanded = _playableQueue(expandedQueue);
    if (expanded.length < _queue.length) return false;
    if (expanded.length == _queue.length) return true;

    final current = _hasCurrentQueueTrack ? _queue[_queueIndex] : null;
    final nextIndex = current == null
        ? -1
        : expanded.indexWhere((entry) => _sameEntry(entry, current));
    if (current != null && nextIndex < 0) return false;

    _queue = expanded;
    _queueIndex = nextIndex;
    _rebuildPlayOrder(anchorIndex: _queueIndex);
    _syncQueueAvailability();
    _persistFullSession();
    return true;
  }

  Future<void> _playFromQueue(
    DownloadHistoryEntry entry,
    List<DownloadHistoryEntry> queue,
  ) async {
    _pendingRestoredSession = null;
    _queue = _playableQueue(queue);
    _queueIndex = _queue.indexWhere((item) => _sameEntry(item, entry));
    if (_queueIndex < 0 && _isPlayableEntry(entry)) {
      _queue = [entry, ..._queue];
      _queueIndex = 0;
    }
    _rebuildPlayOrder(anchorIndex: _queueIndex);
    if (_queueIndex < 0) {
      state = state.copyWith(error: '歌曲不可播放');
      return;
    }
    await _playQueueEntry(_queue[_queueIndex]);
  }

  Future<void> playFromFile(String path) async {
    _pendingRestoredSession = null;
    _clearQueue();
    await _playLocal(PlayerTrack.fromFile(path));
  }

  Future<void> enqueueNext(DownloadHistoryEntry entry) async {
    if (!_isPlayableEntry(entry)) {
      state = state.copyWith(error: '文件不存在');
      return;
    }
    final current = _hasCurrentQueueTrack ? _queue[_queueIndex] : null;
    final next = _queue.where((item) => !_sameEntry(item, entry)).toList();
    final currentIndex = current == null
        ? -1
        : next.indexWhere((item) => _sameEntry(item, current));
    final insertAt = currentIndex >= 0
        ? (currentIndex + 1).clamp(0, next.length)
        : 0;
    next.insert(insertAt, entry);
    _queue = next;
    _queueIndex = current == null
        ? -1
        : _queue.indexWhere((item) => _sameEntry(item, current));
    final forcedNextIndex = current != null && !_sameEntry(current, entry)
        ? insertAt
        : null;
    _rebuildPlayOrder(
      anchorIndex: _queueIndex,
      forcedNextIndex: forcedNextIndex,
    );
    _syncQueueAvailability();
    _persistFullSession();
  }

  Future<void> playPrevious() {
    if (state.loading || _transportSuppressionToken != null) {
      return Future<void>.value();
    }
    final previousIndex = _previousQueueIndex;
    if (previousIndex == null) {
      return state.track == null
          ? Future<void>.value()
          : _restartCurrentTrack();
    }
    return _playQueueIndex(previousIndex);
  }

  Future<void> playNext() {
    if (state.loading || _transportSuppressionToken != null) {
      return Future<void>.value();
    }
    final nextIndex = _nextQueueIndex();
    if (nextIndex == null) {
      return state.track == null
          ? Future<void>.value()
          : _restartCurrentTrack();
    }
    return _playQueueIndex(nextIndex);
  }

  Future<void> playQueueItem(int index) {
    if (state.loading || _transportSuppressionToken != null) {
      return Future<void>.value();
    }
    return _playQueueIndex(index, resetPlayOrder: true);
  }

  Future<bool> _playLocal(
    PlayerTrack track, {
    MusicInfo? fallbackMusic,
    bool autoPlay = true,
    Duration initialPosition = Duration.zero,
    bool showErrors = true,
  }) async {
    final path = track.localPath;
    if (path == null || path.isEmpty || !File(path).existsSync()) {
      state = state.copyWith(error: '文件不存在');
      return false;
    }

    final token = Object();
    _requestToken = token;
    _transportSuppressionToken = token;
    _pausedBySleepTimer = false;
    final pauseGeneration = _sleepTimerPauseGeneration;
    _currentMusic = fallbackMusic;
    _currentQuality = Quality.tryFromCode(track.qualityLabel);
    _logPlayback(
      'load_start kind=local source=${_singleLine(track.sourceLabel)} '
      'quality=${_singleLine(track.qualityLabel)} '
      'initialPositionMs=${initialPosition.inMilliseconds} autoPlay=$autoPlay '
      'title="${_singleLine(track.title)}"',
    );
    state = state.beginTrackLoading(
      nextTrack: track,
      canPlayPrevious: _canPlayPrevious,
      canPlayNext: _canPlayNext,
      queue: List<DownloadHistoryEntry>.unmodifiable(_queue),
      queueIndex: _queueIndex,
    );
    _completionHandledForTrackId = null;

    await _beginAudioTransition(
      token,
      _buildMediaItem(track, artUri: _networkArtworkUri(track.coverUrl)),
    );
    if (!identical(_requestToken, token)) return false;

    try {
      // Reading embedded tags on a large lossless file can burn the whole
      // 8 s budget before the audio pipeline is even touched. Start the read
      // here but let the player load in parallel, then fold the tags in once
      // playback is already under way.
      final tagsFuture = _readEmbeddedTagsForLocal(path);

      await _audioHandler.load(
        item: _buildMediaItem(
          track,
          artUri: _networkArtworkUri(track.coverUrl),
        ),
        sourceUri: File(path).uri,
        queueIndex: _hasCurrentQueueTrack ? _queueIndex : null,
      );
      if (!identical(_requestToken, token)) return false;
      await _seekAfterRestore(initialPosition, token);
      if (!identical(_requestToken, token)) return false;
      _endTransportSuppression(token);
      state = state.copyWith(
        loading: false,
        playing: _audioHandler.playing,
        position: _audioHandler.position,
        duration: _audioHandler.duration ?? Duration.zero,
        processingState: _mapProcessingState(_audioHandler.processingState),
        error: null,
      );
      _logPlayback(
        'load_ready kind=local positionMs=${state.position.inMilliseconds} '
        'durationMs=${state.duration.inMilliseconds} '
        'quality=${_singleLine(track.qualityLabel)} '
        'title="${_singleLine(track.title)}"',
      );
      _syncBluetoothMetadata(force: true);
      _syncQueueAvailability();
      _persistFullSession();
      if (!identical(_requestToken, token)) return false;
      if (autoPlay && pauseGeneration == _sleepTimerPauseGeneration) {
        await _audioHandler.play();
        if (!identical(_requestToken, token)) return false;
      }

      final embedded = await tagsFuture;
      if (!identical(_requestToken, token)) return false;
      var resolvedTrack = track;
      if (embedded != null) {
        resolvedTrack = track.withEmbeddedTags(embedded);
        state = state.copyWith(track: resolvedTrack);
        // Refreshes the system media session and Bluetooth metadata with the
        // tags that were still being read while playback started.
        _publishMediaMetadata(
          _buildMediaItem(
            resolvedTrack,
            duration: _audioHandler.duration,
            artUri: _networkArtworkUri(resolvedTrack.coverUrl),
          ),
        );
        _persistFullSession();
      }
      unawaited(_publishEmbeddedArtworkAfterEntrance(resolvedTrack, token));

      final rawLyrics = embedded?.lyrics;
      final embeddedLyrics = rawLyrics != null && rawLyrics.trim().isNotEmpty
          ? rawLyrics
          : null;
      if (embeddedLyrics != null) {
        state = state
            .withLoadedLyrics(
              info: LyricInfo(lyric: embeddedLyrics),
              parsed: KaraokeLyricsParser.parseEmbedded(embeddedLyrics),
            )
            .copyWith(
              position: _audioHandler.position,
              duration: _audioHandler.duration ?? state.duration,
              playing: _audioHandler.playing,
            );
        _syncBluetoothMetadata(force: true);
        return true;
      }

      if (fallbackMusic == null) {
        state = state.copyWith(lyricLoading: false);
        return true;
      }
      await _loadLyricsForMusic(
        fallbackMusic,
        token,
        logPrefix: 'local lyric load',
      );
      return identical(_requestToken, token);
    } catch (e) {
      await AppLogger.write('player', 'play local failed: $e');
      if (!identical(_requestToken, token)) return false;
      _audioHandler.failTrackTransition(e);
      _endTransportSuppression(token);
      state = state.copyWith(
        loading: false,
        lyricLoading: false,
        playing: false,
        processingState: PlayerProcessingState.idle,
        error: showErrors ? '无法播放这个文件：$e' : null,
      );
      return false;
    }
  }

  Future<void> pauseForSleepTimer() async {
    // Leave an in-flight load intact, but revoke its permission to autoplay.
    _sleepTimerPauseGeneration++;
    _pausedBySleepTimer = true;
    _completionHandledForTrackId = state.track?.id;
    _resetStallRecovery(position: state.position);
    await _audioHandler.pause();
    if (!mounted) return;
    state = state.copyWith(playing: false);
    _persistPositionCheckpoint();
  }

  Future<void> toggle() async {
    if (state.loading ||
        state.track == null ||
        _transportSuppressionToken != null) {
      return;
    }
    _resetStallRecovery(position: state.position);
    final pendingRestore = _pendingRestoredSession;
    if (pendingRestore != null &&
        _audioHandler.processingState == BassProcessingState.idle) {
      await _restorePersistedSession(
        pendingRestore,
        autoPlay: true,
        showErrors: true,
      );
      return;
    }
    if (_audioHandler.playing) {
      await _audioHandler.pause();
      _persistPositionCheckpoint();
    } else {
      await _audioHandler.play();
    }
  }

  Future<void> seek(Duration position) async {
    if (state.loading ||
        state.track == null ||
        _transportSuppressionToken != null) {
      return;
    }
    final trackId = state.track!.id;
    await _audioHandler.seek(position);
    if (!mounted || state.track?.id != trackId) return;
    state = state.copyWith(position: _audioHandler.position);
    _resetStallRecovery(position: state.position);
    _persistPositionCheckpoint();
  }

  void cyclePlaybackMode() {
    final next = switch (state.playbackMode) {
      PlayerPlaybackMode.sequence => PlayerPlaybackMode.shuffle,
      PlayerPlaybackMode.shuffle => PlayerPlaybackMode.repeatOne,
      PlayerPlaybackMode.repeatOne => PlayerPlaybackMode.sequence,
    };
    setPlaybackMode(next);
  }

  void setPlaybackMode(PlayerPlaybackMode mode) {
    if (mode == state.playbackMode) return;
    state = state.copyWith(playbackMode: mode);
    _rebuildPlayOrder(anchorIndex: _queueIndex);
    _publishPlaybackMode();
    _syncQueueAvailability();
    _persistFullSession();
  }

  void _setQueueForEntry(DownloadHistoryEntry entry) {
    final history = _playableQueue(_ref.read(downloadHistoryProvider));
    if (history.isEmpty) {
      _queue = _isPlayableEntry(entry) ? [entry] : const [];
      _queueIndex = _queue.isEmpty ? -1 : 0;
    } else {
      _queue = history;
      _queueIndex = _queue.indexWhere((item) => _sameEntry(item, entry));
      if (_queueIndex < 0 && _isPlayableEntry(entry)) {
        _queue = [entry, ..._queue];
        _queueIndex = 0;
      }
    }
    _rebuildPlayOrder(anchorIndex: _queueIndex);
  }

  Future<void> _playQueueIndex(int index, {bool resetPlayOrder = false}) {
    if (index < 0 || index >= _queue.length) {
      _syncQueueAvailability();
      return Future<void>.value();
    }
    _queueIndex = index;
    if (resetPlayOrder) {
      _rebuildPlayOrder(anchorIndex: index);
    } else {
      _alignPlayOrderCursor(index);
    }
    final entry = _queue[index];
    return _playQueueEntry(entry);
  }

  Future<void> _playQueueEntry(DownloadHistoryEntry entry) {
    _pendingRestoredSession = null;
    final path = entry.savedPath?.trim();
    if (path != null && path.isNotEmpty && File(path).existsSync()) {
      if (state.track?.localPath == path) {
        return _restartCurrentTrack();
      }
      return _playLocal(
        PlayerTrack.fromHistory(entry),
        fallbackMusic: entry.musicInfo,
      );
    }
    final music = entry.musicInfo;
    if (music != null) {
      final remoteTrackId = '${music.source.code}:${music.id}:remote';
      if (state.track?.id == remoteTrackId) {
        return _restartCurrentTrack();
      }
      return _playRemoteMusic(music);
    }
    state = state.copyWith(error: '歌曲不可播放');
    return Future<void>.value();
  }

  Future<void> _restartCurrentTrack() async {
    final pauseGeneration = _sleepTimerPauseGeneration;
    _completionHandledForTrackId = null;
    await _audioHandler.seek(Duration.zero);
    if (!mounted || pauseGeneration != _sleepTimerPauseGeneration) return;
    await _audioHandler.play();
    _persistPositionCheckpoint();
  }

  void _autoAdvanceAfterCompletion() {
    if (_pausedBySleepTimer) return;
    final trackId = state.track?.id;
    if (trackId == null || _completionHandledForTrackId == trackId) return;
    _completionHandledForTrackId = trackId;
    if (state.playbackMode == PlayerPlaybackMode.repeatOne) {
      unawaited(_restartCurrentTrack());
      return;
    }
    final nextIndex = _nextQueueIndex(automatic: true);
    if (nextIndex == null) return;
    unawaited(_playQueueIndex(nextIndex));
  }

  List<DownloadHistoryEntry> _playableQueue(
    List<DownloadHistoryEntry> entries,
  ) {
    final out = <DownloadHistoryEntry>[];
    final seen = <String>{};
    for (final entry in entries) {
      if (!_isQueueCandidate(entry)) continue;
      final path = entry.savedPath?.trim();
      final key = path != null && path.isNotEmpty
          ? 'file:$path'
          : entry.musicId.isNotEmpty
          ? 'music:${entry.sourceCode}:${entry.musicId}'
          : entry.id;
      if (seen.add(key)) out.add(entry);
    }
    return out;
  }

  bool _isPlayableEntry(DownloadHistoryEntry entry) {
    if (!entry.isCompleted) return false;
    final path = entry.savedPath;
    if (path != null && path.isNotEmpty && File(path).existsSync()) return true;
    return entry.musicInfo != null;
  }

  bool _isQueueCandidate(DownloadHistoryEntry entry) {
    if (!entry.isCompleted) return false;
    final path = entry.savedPath?.trim();
    return (path != null && path.isNotEmpty) || entry.musicInfo != null;
  }

  bool _sameEntry(DownloadHistoryEntry a, DownloadHistoryEntry b) {
    if (a.id == b.id) return true;
    final aPath = a.savedPath;
    final bPath = b.savedPath;
    if (aPath != null && aPath.isNotEmpty && aPath == bPath) return true;
    return a.sourceCode == b.sourceCode &&
        a.musicId.isNotEmpty &&
        a.musicId == b.musicId;
  }

  bool _hasSameQueueIdentity(
    List<DownloadHistoryEntry> first,
    List<DownloadHistoryEntry> second,
  ) {
    if (first.length != second.length) return false;
    for (var index = 0; index < first.length; index++) {
      if (first[index].id != second[index].id) return false;
    }
    return true;
  }

  void _clearQueue({bool syncState = true}) {
    _queue = const [];
    _queueIndex = -1;
    _playOrder = const [];
    _playOrderCursor = -1;
    if (syncState) _syncQueueAvailability();
  }

  void _rebuildPlayOrder({required int anchorIndex, int? forcedNextIndex}) {
    if (anchorIndex < 0 || anchorIndex >= _queue.length) {
      _playOrder = const [];
      _playOrderCursor = -1;
      return;
    }
    if (state.playbackMode == PlayerPlaybackMode.shuffle) {
      final hasForcedNext =
          forcedNextIndex != null &&
          forcedNextIndex >= 0 &&
          forcedNextIndex < _queue.length &&
          forcedNextIndex != anchorIndex;
      final remaining = [
        for (var index = 0; index < _queue.length; index++)
          if (index != anchorIndex &&
              (!hasForcedNext || index != forcedNextIndex))
            index,
      ]..shuffle(_random);
      _playOrder = [
        anchorIndex,
        if (hasForcedNext) forcedNextIndex,
        ...remaining,
      ];
      _playOrderCursor = 0;
      return;
    }
    _playOrder = List<int>.generate(_queue.length, (index) => index);
    _playOrderCursor = anchorIndex;
  }

  void _alignPlayOrderCursor(int index) {
    if (_playOrder.length != _queue.length || !_playOrder.contains(index)) {
      _rebuildPlayOrder(anchorIndex: index);
      return;
    }
    _playOrderCursor = _playOrder.indexOf(index);
  }

  bool get _hasCurrentQueueTrack =>
      _queueIndex >= 0 && _queueIndex < _queue.length;

  bool get _canPlayPrevious {
    if (!_hasCurrentQueueTrack) return state.track != null;
    return _queue.isNotEmpty;
  }

  bool get _canPlayNext {
    if (!_hasCurrentQueueTrack) return state.track != null;
    return _queue.isNotEmpty;
  }

  int? get _previousQueueIndex {
    if (!_hasCurrentQueueTrack || _queue.isEmpty) return null;
    if (state.playbackMode == PlayerPlaybackMode.shuffle) {
      if (_playOrder.isEmpty) {
        _rebuildPlayOrder(anchorIndex: _queueIndex);
      }
      if (_playOrderCursor > 0) {
        return _playOrder[_playOrderCursor - 1];
      }
      return _playOrder.isEmpty ? _queueIndex : _playOrder.last;
    }
    return _queueIndex > 0 ? _queueIndex - 1 : _queue.length - 1;
  }

  int? _nextQueueIndex({bool automatic = false}) {
    if (_queue.isEmpty) return null;
    if (!_hasCurrentQueueTrack) return state.track == null ? null : 0;
    if (automatic && state.playbackMode == PlayerPlaybackMode.repeatOne) {
      return _queueIndex;
    }
    if (state.playbackMode == PlayerPlaybackMode.shuffle) {
      if (_queue.length == 1) return _queueIndex;
      if (_playOrderCursor + 1 < _playOrder.length) {
        return _playOrder[_playOrderCursor + 1];
      }
      _rebuildPlayOrder(anchorIndex: _queueIndex);
      return _playOrder.length > 1 ? _playOrder[1] : _queueIndex;
    }
    return _queueIndex + 1 < _queue.length ? _queueIndex + 1 : 0;
  }

  void _syncQueueAvailability() {
    if (!mounted) return;
    _audioHandler.publishQueue(
      _queue.map(_mediaItemForHistoryEntry).toList(growable: false),
      currentIndex: _hasCurrentQueueTrack ? _queueIndex : null,
    );
    state = state.copyWith(
      canPlayPrevious: _canPlayPrevious,
      canPlayNext: _canPlayNext,
      queue: List<DownloadHistoryEntry>.unmodifiable(_queue),
      queueIndex: _queueIndex,
    );
  }

  Future<MediaItem> _mediaItemForTrack(
    PlayerTrack track, {
    Duration? duration,
  }) async {
    final embeddedArtwork = await _audioHandler.cacheArtwork(track.coverBytes);
    return _buildMediaItem(
      track,
      duration: duration,
      artUri: embeddedArtwork ?? _networkArtworkUri(track.coverUrl),
    );
  }

  Future<void> _publishEmbeddedArtworkAfterEntrance(
    PlayerTrack track,
    Object token,
  ) async {
    final bytes = track.coverBytes;
    if (bytes == null || bytes.isEmpty) return;
    await Future<void>.delayed(const Duration(milliseconds: 360));
    if (!identical(_requestToken, token)) return;
    final item = await _mediaItemForTrack(
      track,
      duration: _audioHandler.duration,
    );
    if (!identical(_requestToken, token)) return;
    _publishMediaMetadata(item);
  }

  MediaItem _mediaItemForHistoryEntry(DownloadHistoryEntry entry) {
    // Queue metadata is descriptive only. The selected item is validated in
    // _playQueueEntry, so avoid synchronously stat-ing every library file
    // while the player route is trying to render its first frame.
    final track = PlayerTrack.fromQueueEntry(entry, trustSavedPath: true);
    return _buildMediaItem(track, artUri: _networkArtworkUri(track.coverUrl));
  }

  MediaItem _buildMediaItem(
    PlayerTrack track, {
    Duration? duration,
    Uri? artUri,
  }) {
    final album = track.album.trim();
    final sourceDescription = [
      track.sourceLabel.trim(),
      track.qualityLabel.trim(),
    ].where((part) => part.isNotEmpty).join(' · ');
    return MediaItem(
      id: track.id,
      title: track.title.trim().isEmpty ? '未知歌曲' : track.title.trim(),
      artist: track.artist.trim().isEmpty ? '未知歌手' : track.artist.trim(),
      album: album.isEmpty ? null : album,
      duration: duration != null && duration > Duration.zero ? duration : null,
      artUri: artUri,
      artHeaders: CoverImageSource.headersFor(artUri?.toString()),
      displayTitle: track.title,
      displaySubtitle: track.artist,
      displayDescription: sourceDescription.isEmpty ? null : sourceDescription,
      extras: {
        'trackKind': track.kind.name,
        'source': track.sourceLabel,
        'quality': track.qualityLabel,
      },
    );
  }

  void _publishMediaMetadata(MediaItem item) {
    _audioHandler.updateMediaMetadata(item);
    _bluetoothLyricMetadata.reset();
    _syncBluetoothMetadata(force: true);
  }

  void _syncBluetoothMetadata({bool force = false}) {
    if (!mounted) return;
    final track = state.track;
    final current = _audioHandler.currentMediaItem;
    if (track == null || current == null || current.id != track.id) return;

    final settings = _ref.read(settingsProvider);
    final canPublishLine =
        settings.bluetoothLyricEnabled &&
        state.playing &&
        !state.loading &&
        !state.buffering &&
        state.processingState != PlayerProcessingState.completed &&
        !state.lyrics.isEmpty;
    var lineIndex = -1;
    String? activeLine;
    if (canPublishLine) {
      lineIndex = state.lyrics.activeIndex(state.position);
      if (lineIndex >= 0 && lineIndex < state.lyrics.lines.length) {
        activeLine = state.lyrics.lines[lineIndex].text;
      }
    }
    final fullLyric = state.lyricInfo?.lyric.trim();
    try {
      final item = _bluetoothLyricMetadata.next(
        current: current,
        track: track,
        lineIndex: lineIndex,
        lineLyricEnabled: settings.bluetoothLyricEnabled,
        fullLyricEnabled: settings.bluetoothFullLyricEnabled,
        activeLine: activeLine,
        fullLyric: fullLyric,
        force: force,
      );
      if (item == null) return;
      _audioHandler.updateMediaMetadata(item);
    } catch (error) {
      _bluetoothLyricMetadata.reset();
      unawaited(
        AppLogger.write('player', 'bluetooth lyric metadata failed: $error'),
      );
    }
  }

  Uri? _networkArtworkUri(String? value) {
    final normalized = CoverImageSource.normalizeUrl(value, size: 500)?.trim();
    if (normalized == null || normalized.isEmpty) return null;
    final candidate = normalized.startsWith('//')
        ? 'https:$normalized'
        : normalized;
    final uri = Uri.tryParse(candidate);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return null;
    }
    return uri;
  }

  void _publishPlaybackMode() {
    _audioHandler.updatePlaybackModes(
      repeatMode: state.playbackMode == PlayerPlaybackMode.repeatOne
          ? AudioServiceRepeatMode.one
          : AudioServiceRepeatMode.all,
      shuffleMode: state.playbackMode == PlayerPlaybackMode.shuffle
          ? AudioServiceShuffleMode.all
          : AudioServiceShuffleMode.none,
    );
  }

  Future<void> _handleSystemRepeatMode(
    AudioServiceRepeatMode repeatMode,
  ) async {
    final next = repeatMode == AudioServiceRepeatMode.one
        ? PlayerPlaybackMode.repeatOne
        : state.playbackMode == PlayerPlaybackMode.shuffle
        ? PlayerPlaybackMode.shuffle
        : PlayerPlaybackMode.sequence;
    setPlaybackMode(next);
    _publishPlaybackMode();
  }

  Future<void> _handleSystemShuffleMode(
    AudioServiceShuffleMode shuffleMode,
  ) async {
    final next = shuffleMode == AudioServiceShuffleMode.none
        ? state.playbackMode == PlayerPlaybackMode.shuffle
              ? PlayerPlaybackMode.sequence
              : state.playbackMode
        : PlayerPlaybackMode.shuffle;
    setPlaybackMode(next);
    _publishPlaybackMode();
  }

  void _hydrateRestoredSession(PlayerSessionSnapshot snapshot) {
    final restoredTrack = _playerTrackFromPersisted(snapshot.track);
    final savedQueueEntry =
        snapshot.queueIndex >= 0 && snapshot.queueIndex < snapshot.queue.length
        ? snapshot.queue[snapshot.queueIndex]
        : null;
    _queue = _playableQueue(
      snapshot.queue.where(_isPlayableEntry).toList(growable: false),
    );
    _queueIndex = savedQueueEntry == null
        ? -1
        : _queue.indexWhere((entry) => _sameEntry(entry, savedQueueEntry));
    if (_queueIndex < 0) {
      _queueIndex = _queue.indexWhere(
        (entry) => _entryMatchesTrack(entry, restoredTrack, snapshot.music),
      );
    }

    _currentMusic = snapshot.music;
    _currentQuality = _qualityForSnapshot(snapshot, restoredTrack);
    final playbackMode = _playbackModeFromCode(snapshot.playbackModeCode);
    final restoredDuration = snapshot.duration;
    final restoredPosition =
        restoredDuration > Duration.zero && snapshot.position > restoredDuration
        ? restoredDuration
        : snapshot.position;
    state = PlayerState(
      track: restoredTrack,
      loading: true,
      lyricLoading: true,
      playing: false,
      position: restoredPosition,
      duration: restoredDuration,
      processingState: PlayerProcessingState.loading,
      queue: List<DownloadHistoryEntry>.unmodifiable(_queue),
      queueIndex: _queueIndex,
      playbackMode: playbackMode,
    );
    _rebuildPlayOrder(anchorIndex: _queueIndex);
    _publishPlaybackMode();
    _syncQueueAvailability();
  }

  Future<void> _restorePersistedSession(
    PlayerSessionSnapshot snapshot, {
    bool autoPlay = false,
    bool showErrors = false,
  }) async {
    if (!identical(_pendingRestoredSession, snapshot)) return;
    final restoredTrack = _playerTrackFromPersisted(snapshot.track);
    final quality = _qualityForSnapshot(snapshot, restoredTrack);
    bool restored;

    if (restoredTrack.isLocal) {
      final path = restoredTrack.localPath?.trim();
      if (path != null && path.isNotEmpty && File(path).existsSync()) {
        restored = await _playLocal(
          restoredTrack,
          fallbackMusic: snapshot.music,
          autoPlay: autoPlay,
          initialPosition: snapshot.position,
          showErrors: showErrors,
        );
      } else if (snapshot.music != null) {
        restored = await _playRemoteMusic(
          snapshot.music!,
          quality: quality,
          autoPlay: autoPlay,
          initialPosition: snapshot.position,
          restoredTrack: PlayerTrack.fromMusic(
            music: snapshot.music!,
            quality: quality ?? snapshot.music!.bestQuality,
            url: '',
            coverUrl: restoredTrack.coverUrl,
          ),
          showErrors: showErrors,
        );
      } else {
        await AppLogger.write(
          'player',
          'discard restored local track because the file no longer exists: '
              '${restoredTrack.localPath}',
        );
        if (!identical(_pendingRestoredSession, snapshot)) return;
        _discardInvalidRestoredSession();
        return;
      }
    } else {
      final music = snapshot.music;
      if (music == null) {
        await AppLogger.write(
          'player',
          'discard restored remote track without MusicInfo: '
              '${restoredTrack.id}',
        );
        if (!identical(_pendingRestoredSession, snapshot)) return;
        _discardInvalidRestoredSession();
        return;
      }
      restored = await _playRemoteMusic(
        music,
        quality: quality,
        autoPlay: autoPlay,
        initialPosition: snapshot.position,
        restoredTrack: restoredTrack,
        showErrors: showErrors,
      );
    }

    if (restored && identical(_pendingRestoredSession, snapshot)) {
      _pendingRestoredSession = null;
    }
  }

  void _discardInvalidRestoredSession() {
    _pendingRestoredSession = null;
    _requestToken = Object();
    _transportSuppressionToken = null;
    _currentMusic = null;
    _currentQuality = null;
    _clearQueue(syncState: false);
    state = const PlayerState();
    _publishPlaybackMode();
    _syncQueueAvailability();
    _queueStoreOperation(_sessionStore.clear);
  }

  Future<void> _seekAfterRestore(Duration requested, Object token) async {
    if (requested <= Duration.zero || !identical(_requestToken, token)) return;
    final duration = _audioHandler.duration;
    final target =
        duration != null && duration > Duration.zero && requested > duration
        ? duration
        : requested;
    try {
      await _audioHandler.seek(target);
    } catch (error, stackTrace) {
      await AppLogger.write(
        'player',
        'seek after restore non-fatal error target=${target.inMilliseconds}ms: $error\n'
            '$stackTrace',
      );
    }
  }

  void _schedulePositionCheckpoint() {
    if (state.track == null || _positionCheckpointTimer != null) return;
    _positionCheckpointTimer = Timer(_positionCheckpointInterval, () {
      _positionCheckpointTimer = null;
      _persistPositionCheckpoint();
    });
  }

  void _persistFullSession() {
    final track = state.track;
    if (track == null) return;
    final snapshot = PlayerSessionSnapshot(
      track: _persistedTrackFromPlayer(track),
      music: _currentMusic,
      qualityCode:
          _currentQuality?.code ??
          Quality.tryFromCode(track.qualityLabel)?.code,
      position: state.position,
      duration: state.duration,
      queue: List<DownloadHistoryEntry>.unmodifiable(_queue),
      queueIndex: _queueIndex,
      playbackModeCode: state.playbackMode.name,
    );
    final checkpoint = _checkpointForCurrentTrack();
    _queueStoreOperation(() async {
      await _sessionStore.writeSnapshot(snapshot);
      if (checkpoint != null) {
        await _sessionStore.writeCheckpoint(checkpoint);
      }
    });
  }

  void _persistPositionCheckpoint() {
    _positionCheckpointTimer?.cancel();
    _positionCheckpointTimer = null;
    final checkpoint = _checkpointForCurrentTrack();
    if (checkpoint == null) return;
    _queueStoreOperation(() => _sessionStore.writeCheckpoint(checkpoint));
  }

  PlayerSessionCheckpoint? _checkpointForCurrentTrack() {
    final track = state.track;
    if (track == null) return null;
    return PlayerSessionCheckpoint(
      trackId: track.id,
      position: state.position,
      duration: state.duration,
    );
  }

  void _queueStoreOperation(Future<void> Function() operation) {
    _persistChain = _persistChain.then((_) async {
      try {
        await operation();
      } catch (error) {
        await AppLogger.write('player', 'persist session failed: $error');
      }
    });
  }

  PlayerTrack _playerTrackFromPersisted(PersistedPlayerTrack track) {
    return PlayerTrack(
      id: track.id,
      kind: track.kindCode == PlayerTrackKind.localFile.name
          ? PlayerTrackKind.localFile
          : PlayerTrackKind.remote,
      title: track.title,
      artist: track.artist,
      album: track.album,
      sourceLabel: track.sourceLabel,
      qualityLabel: track.qualityLabel,
      coverUrl: track.coverUrl,
      localPath: track.localPath,
    );
  }

  PersistedPlayerTrack _persistedTrackFromPlayer(PlayerTrack track) {
    return PersistedPlayerTrack(
      id: track.id,
      kindCode: track.kind.name,
      title: track.title,
      artist: track.artist,
      album: track.album,
      sourceLabel: track.sourceLabel,
      qualityLabel: track.qualityLabel,
      coverUrl: track.coverUrl,
      localPath: track.localPath,
    );
  }

  bool _entryMatchesTrack(
    DownloadHistoryEntry entry,
    PlayerTrack track,
    MusicInfo? music,
  ) {
    final path = track.localPath?.trim();
    if (path != null && path.isNotEmpty && entry.savedPath?.trim() == path) {
      return true;
    }
    if (music == null || music.id.isEmpty) return false;
    return entry.sourceCode == music.source.code && entry.musicId == music.id;
  }

  Quality? _qualityForSnapshot(
    PlayerSessionSnapshot snapshot,
    PlayerTrack track,
  ) {
    final stored = snapshot.qualityCode;
    return stored == null
        ? Quality.tryFromCode(track.qualityLabel)
        : Quality.tryFromCode(stored);
  }

  PlayerPlaybackMode _playbackModeFromCode(String code) {
    for (final mode in PlayerPlaybackMode.values) {
      if (mode.name == code) return mode;
    }
    return PlayerPlaybackMode.sequence;
  }

  Future<void> _loadLyricsForMusic(
    MusicInfo music,
    Object token, {
    required String logPrefix,
  }) async {
    try {
      final lyricInfo = await _ref
          .read(musicApiProvider)
          .getLyric(musicInfo: music)
          .timeout(_lyricLoadTimeout);
      if (!identical(_requestToken, token)) return;
      state = state.withLoadedLyrics(
        info: lyricInfo,
        parsed: KaraokeLyricsParser.parse(lyricInfo),
      );
      _syncBluetoothMetadata(force: true);
    } on TimeoutException catch (e) {
      await AppLogger.write(
        'player',
        '$logPrefix timeout after ${_lyricLoadTimeout.inSeconds}s: $e',
      );
      if (!identical(_requestToken, token)) return;
      state = state.copyWith(lyricLoading: false);
    } catch (e) {
      await AppLogger.write('player', '$logPrefix failed: $e');
      if (!identical(_requestToken, token)) return;
      state = state.copyWith(lyricLoading: false);
    }
  }

  Future<void> _beginAudioTransition(Object token, MediaItem item) async {
    _resetStallRecovery();
    _bufferingStopwatch?.stop();
    _bufferingStopwatch = null;
    _lastLoggedProcessingState = null;
    _lastLoggedPlaying = null;
    try {
      await _audioHandler.beginTrackTransition(
        item: item,
        queueIndex: _hasCurrentQueueTrack ? _queueIndex : null,
      );
      _bluetoothLyricMetadata.reset();
    } catch (e) {
      await AppLogger.write(
        'player',
        'pause before track transition failed: $e',
      );
    }
    if (!identical(_requestToken, token)) return;
  }

  void _endTransportSuppression(Object token) {
    if (identical(_transportSuppressionToken, token)) {
      _transportSuppressionToken = null;
    }
  }

  Future<EmbeddedAudioTags?> _readEmbeddedTagsForLocal(String path) async {
    try {
      return await Tagger.readEmbeddedTags(
        path,
      ).timeout(_embeddedTagReadTimeout);
    } on TimeoutException catch (e) {
      await AppLogger.write(
        'player',
        'embedded tag read timeout after '
            '${_embeddedTagReadTimeout.inSeconds}s: $e',
      );
      return null;
    } catch (e) {
      await AppLogger.write('player', 'embedded tag read failed: $e');
      return null;
    }
  }

  Future<void> replay() async {
    if (state.loading ||
        state.track == null ||
        _transportSuppressionToken != null) {
      return;
    }
    await _restartCurrentTrack();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _persistPositionCheckpoint();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _persistPositionCheckpoint();
    _positionCheckpointTimer?.cancel();
    _stallRecoveryTimer?.cancel();
    _audioHandler.unbindTransportCallbacks(this);
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    super.dispose();
  }
}

final playerControllerProvider =
    StateNotifierProvider<PlayerController, PlayerState>(PlayerController.new);
