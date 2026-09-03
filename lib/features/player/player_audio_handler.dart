import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:bass_player/bass_player.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/services/app_logger.dart';
import 'media_item_copy.dart';

typedef PlayerTransportCallback = Future<void> Function();
typedef PlayerQueueItemCallback = Future<void> Function(int index);
typedef PlayerRepeatModeCallback =
    Future<void> Function(AudioServiceRepeatMode mode);
typedef PlayerShuffleModeCallback =
    Future<void> Function(AudioServiceShuffleMode mode);

const playerAudioServiceConfig = AudioServiceConfig(
  androidNotificationChannelId: 'com.cyshine.music.channel.audio_playback',
  androidNotificationChannelName: '音乐播放',
  androidNotificationChannelDescription: '显示正在播放的歌曲和媒体控制',
  androidNotificationIcon: 'drawable/ic_stat_music_note',
  androidShowNotificationBadge: false,
  androidNotificationOngoing: false,
  // Keep the MediaSession and notification alive while a track is paused or
  // replaced. Restarting a foreground service from the lock screen is not
  // reliable across Android vendors and can leave stale system metadata.
  androidStopForegroundOnPause: false,
  notificationColor: Color(0xFF006A60),
  artDownscaleWidth: 512,
  artDownscaleHeight: 512,
);

/// Upper bound for a single [PlayerAudioHandler.load] attempt.
const playerLoadTimeout = Duration(seconds: 40);

class PlayerLoadTimeoutException implements Exception {
  const PlayerLoadTimeoutException(this.timeout);

  final Duration timeout;

  @override
  String toString() => '加载超时（${timeout.inSeconds} 秒），文件可能过大或音源响应过慢';
}

AudioSessionConfiguration playerAudioSessionConfiguration({
  required bool allowMixWithOthers,
}) {
  if (!allowMixWithOthers) {
    return const AudioSessionConfiguration.music();
  }
  return const AudioSessionConfiguration(
    avAudioSessionCategory: AVAudioSessionCategory.playback,
    avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.mixWithOthers,
    avAudioSessionMode: AVAudioSessionMode.defaultMode,
    androidAudioAttributes: AndroidAudioAttributes(
      contentType: AndroidAudioContentType.music,
      usage: AndroidAudioUsage.media,
    ),
    androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
  );
}

bool shouldActivatePlayerAudioSession({
  required bool allowMixWithOthers,
  required bool isAndroid,
}) => !allowMixWithOthers || !isAndroid;

Future<PlayerAudioHandler> initializePlayerAudioHandler({
  bool allowMixWithOthers = false,
}) async {
  final handler = await AudioService.init<PlayerAudioHandler>(
    builder: () => PlayerAudioHandler(allowMixWithOthers: allowMixWithOthers),
    config: playerAudioServiceConfig,
  );

  await handler.setAllowMixWithOthers(allowMixWithOthers);
  return handler;
}

class PlayerAudioHandler extends BaseAudioHandler with SeekHandler {
  PlayerAudioHandler({bool allowMixWithOthers = false, BassPlayer? player})
    : _player = player ?? BassPlayer(),
      _allowMixWithOthers = allowMixWithOthers {
    _playbackSubscription = _player.playbackEventStream.listen(_broadcastState);
    _durationSubscription = _player.durationStream.listen(_updateDuration);
    _errorSubscription = _player.errorStream.listen((error) {
      _broadcastError(error, StackTrace.current);
    });
    _broadcastState(_player.snapshot);
  }

  final BassPlayer _player;
  bool _allowMixWithOthers;
  bool _audioSessionConfigured = false;
  bool _engineInitialized = false;
  BassEqualizerConfiguration? _pendingEqualizer;
  StreamSubscription<BassPlaybackSnapshot>? _playbackSubscription;
  StreamSubscription<Duration?>? _durationSubscription;
  StreamSubscription<BassPlayerException>? _errorSubscription;
  StreamSubscription<AudioInterruptionEvent>? _interruptionSubscription;
  StreamSubscription<void>? _becomingNoisySubscription;
  bool _resumeAfterInterruption = false;
  bool _ducked = false;

  Object? _callbackOwner;
  PlayerTransportCallback? _onPrevious;
  PlayerTransportCallback? _onNext;
  PlayerQueueItemCallback? _onQueueItem;
  PlayerRepeatModeCallback? _onRepeatMode;
  PlayerShuffleModeCallback? _onShuffleMode;
  int? _queueIndex;
  AudioServiceRepeatMode _repeatMode = AudioServiceRepeatMode.all;
  AudioServiceShuffleMode _shuffleMode = AudioServiceShuffleMode.none;
  MediaItem? _currentMediaItem;
  MediaItem? _mediaItemBeforeTransition;
  int? _queueIndexBeforeTransition;
  bool _trackTransitionActive = false;

  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<BassPlaybackSnapshot> get playerStateStream =>
      _player.playbackEventStream;
  Stream<BassPlayerException> get errorStream => _player.errorStream;
  MediaItem? get currentMediaItem => _currentMediaItem;

  Duration get position => _player.position;
  Duration? get duration => _player.duration;
  bool get playing => _player.playing;
  BassProcessingState get processingState => _player.processingState;

  Future<void> initializeEngine() async {
    final info = await _player.initialize();
    _engineInitialized = true;
    final pendingEqualizer = _pendingEqualizer;
    _pendingEqualizer = null;
    if (pendingEqualizer != null) {
      await _player.setEqualizer(pendingEqualizer);
    }
    await AppLogger.write(
      'player-engine',
      'BASS ${info.version}; BASS_FX ${info.fxVersion}; '
          'plugins=${info.plugins.entries.map((entry) => '${entry.key}:${entry.value}').join(',')}',
    );
  }

  Future<void> setAllowMixWithOthers(bool value) async {
    _allowMixWithOthers = value;
    final session = await AudioSession.instance;
    _bindAudioSessionEvents(session);
    await session.configure(
      playerAudioSessionConfiguration(allowMixWithOthers: value),
    );
    _audioSessionConfigured = true;

    if (Platform.isAndroid && value) {
      // Release focus acquired under the normal mode so another app can
      // resume immediately while this player keeps rendering audio.
      await session.setActive(false);
    } else if (_player.playing) {
      await session.setActive(true);
    }
  }

  void _bindAudioSessionEvents(AudioSession session) {
    _interruptionSubscription ??= session.interruptionEventStream.listen(
      (event) => unawaited(_handleAudioInterruption(event)),
    );
    _becomingNoisySubscription ??= session.becomingNoisyEventStream.listen(
      (_) => unawaited(pause()),
    );
  }

  Future<void> _handleAudioInterruption(AudioInterruptionEvent event) async {
    if (event.type == AudioInterruptionType.duck) {
      _ducked = event.begin;
      await _player.setVolume(event.begin ? 0.2 : 1);
      return;
    }
    if (event.begin) {
      _resumeAfterInterruption = _player.playing;
      if (_resumeAfterInterruption) await pause();
      return;
    }
    if (!_resumeAfterInterruption) return;
    _resumeAfterInterruption = false;
    if (_ducked) {
      _ducked = false;
      await _player.setVolume(1);
    }
    await play();
  }

  void bindTransportCallbacks({
    required Object owner,
    required PlayerTransportCallback onPrevious,
    required PlayerTransportCallback onNext,
    required PlayerQueueItemCallback onQueueItem,
    required PlayerRepeatModeCallback onRepeatMode,
    required PlayerShuffleModeCallback onShuffleMode,
  }) {
    _callbackOwner = owner;
    _onPrevious = onPrevious;
    _onNext = onNext;
    _onQueueItem = onQueueItem;
    _onRepeatMode = onRepeatMode;
    _onShuffleMode = onShuffleMode;
    _broadcastState(_player.snapshot);
  }

  void unbindTransportCallbacks(Object owner) {
    if (!identical(_callbackOwner, owner)) return;
    _callbackOwner = null;
    _onPrevious = null;
    _onNext = null;
    _onQueueItem = null;
    _onRepeatMode = null;
    _onShuffleMode = null;
  }

  Future<void> beginTrackTransition({
    required MediaItem item,
    int? queueIndex,
  }) async {
    if (!_trackTransitionActive) {
      _mediaItemBeforeTransition = _currentMediaItem;
      _queueIndexBeforeTransition = _queueIndex;
    }
    _trackTransitionActive = true;
    _queueIndex = queueIndex;
    _currentMediaItem = item;
    mediaItem.add(item);
    _broadcastState(_player.snapshot);
    if (_player.playing) await _player.pause();
  }

  void failTrackTransition(Object error) {
    if (!_trackTransitionActive) return;
    final previousItem = _mediaItemBeforeTransition;
    _queueIndex = _queueIndexBeforeTransition;
    if (previousItem != null) {
      _currentMediaItem = previousItem;
      mediaItem.add(previousItem);
    }
    _trackTransitionActive = false;
    _clearTransitionSnapshot();
    final restoredState = _transformEvent(_player.snapshot);
    playbackState.add(
      restoredState.copyWith(
        processingState:
            restoredState.processingState == AudioProcessingState.idle
            ? AudioProcessingState.error
            : restoredState.processingState,
        playing: false,
        errorCode: 1,
        errorMessage: error.toString(),
      ),
    );
  }

  Future<Duration?> load({
    required MediaItem item,
    required Uri sourceUri,
    int? queueIndex,
  }) async {
    _queueIndex = queueIndex;
    _currentMediaItem = item;
    mediaItem.add(item);
    final resolvedDuration = await _loadSourceBounded(
      sourceUri,
      formatHint: item.extras?['quality']?.toString(),
    );
    _trackTransitionActive = false;
    _clearTransitionSnapshot();
    _updateDuration(resolvedDuration);
    _broadcastState(_player.snapshot);
    return resolvedDuration;
  }

  Future<Duration?> _loadSourceBounded(
    Uri sourceUri, {
    String? formatHint,
  }) async {
    if (!_engineInitialized) await initializeEngine();
    final stopwatch = Stopwatch()..start();
    unawaited(
      AppLogger.write(
        'player-load',
        'START scheme=${sourceUri.scheme} host=${sourceUri.host} '
            'format=${formatHint ?? 'unknown'}',
      ),
    );
    final loading = _player.load(sourceUri, formatHint: formatHint);
    try {
      final resolvedDuration = await loading.timeout(playerLoadTimeout);
      stopwatch.stop();
      unawaited(
        AppLogger.write(
          'player-load',
          'OK scheme=${sourceUri.scheme} host=${sourceUri.host} '
              'format=${formatHint ?? 'unknown'} '
              'elapsed=${stopwatch.elapsedMilliseconds}ms '
              'duration=${resolvedDuration?.inMilliseconds ?? -1}ms',
        ),
      );
      return resolvedDuration;
    } on TimeoutException {
      stopwatch.stop();
      unawaited(loading.then((_) {}, onError: (Object _) {}));
      try {
        await _player.stop();
      } catch (_) {
        // Best effort: the load already failed, keep the original reason.
      }
      await AppLogger.write(
        'player-load',
        'TIMEOUT scheme=${sourceUri.scheme} host=${sourceUri.host} '
            'format=${formatHint ?? 'unknown'} '
            'after=${stopwatch.elapsedMilliseconds}ms',
      );
      throw const PlayerLoadTimeoutException(playerLoadTimeout);
    } catch (error) {
      stopwatch.stop();
      await AppLogger.write(
        'player-load',
        'FAIL scheme=${sourceUri.scheme} host=${sourceUri.host} '
            'format=${formatHint ?? 'unknown'} '
            'elapsed=${stopwatch.elapsedMilliseconds}ms: $error',
      );
      rethrow;
    }
  }

  void updateMediaMetadata(MediaItem item) {
    final resolvedDuration = item.duration ?? _player.duration;
    _currentMediaItem = resolvedDuration == null
        ? item
        : preserveMediaItemArtHeaders(
            item,
            item.copyWith(duration: resolvedDuration),
          );
    mediaItem.add(_currentMediaItem);
  }

  void publishQueue(List<MediaItem> items, {int? currentIndex}) {
    _queueIndex = currentIndex;
    queue.add(List<MediaItem>.unmodifiable(items));
    _broadcastState(_player.snapshot);
  }

  void updatePlaybackModes({
    required AudioServiceRepeatMode repeatMode,
    required AudioServiceShuffleMode shuffleMode,
  }) {
    _repeatMode = repeatMode;
    _shuffleMode = shuffleMode;
    _broadcastState(_player.snapshot);
  }

  Future<Uri?> cacheArtwork(Uint8List? bytes) async {
    if (bytes == null || bytes.isEmpty) return null;
    final cacheRoot = await getTemporaryDirectory();
    final artDirectory = Directory(
      '${cacheRoot.path}${Platform.pathSeparator}media_art',
    );
    if (!artDirectory.existsSync()) {
      await artDirectory.create(recursive: true);
    }
    final extension = _artworkExtension(bytes);
    final file = File(
      '${artDirectory.path}${Platform.pathSeparator}'
      '${sha256.convert(bytes)}.$extension',
    );
    if (!file.existsSync()) {
      await file.writeAsBytes(bytes, flush: true);
    }
    return file.uri;
  }

  @override
  Future<void> play() async {
    if (_trackTransitionActive) return;
    _logTransport('play');
    if (_player.processingState == BassProcessingState.completed) {
      await _player.seek(Duration.zero);
    }
    if (!_audioSessionConfigured) {
      await setAllowMixWithOthers(_allowMixWithOthers);
    }
    if (shouldActivatePlayerAudioSession(
      allowMixWithOthers: _allowMixWithOthers,
      isAndroid: Platform.isAndroid,
    )) {
      final session = await AudioSession.instance;
      if (!await session.setActive(true)) return;
    }
    await _player.play();
  }

  @override
  Future<void> pause() {
    _logTransport('pause');
    return _player.pause();
  }

  @override
  Future<void> click([MediaButton button = MediaButton.media]) async {
    switch (button) {
      case MediaButton.media:
        if (_player.playing) {
          await pause();
        } else {
          await play();
        }
        return;
      case MediaButton.next:
        await skipToNext();
        return;
      case MediaButton.previous:
        await skipToPrevious();
        return;
    }
  }

  @override
  Future<void> seek(Duration position) {
    if (_trackTransitionActive) return Future<void>.value();
    _logTransport('seek', target: position);
    return _player.seek(position);
  }

  Future<void> setEqualizer(BassEqualizerConfiguration configuration) async {
    if (!_engineInitialized) {
      _pendingEqualizer = configuration;
      return;
    }
    await _player.setEqualizer(configuration);
  }

  @override
  Future<void> skipToPrevious() async {
    await _onPrevious?.call();
  }

  @override
  Future<void> skipToNext() async {
    await _onNext?.call();
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    await _onQueueItem?.call(index);
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    _repeatMode = repeatMode;
    _broadcastState(_player.snapshot);
    await _onRepeatMode?.call(repeatMode);
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    _shuffleMode = shuffleMode;
    _broadcastState(_player.snapshot);
    await _onShuffleMode?.call(shuffleMode);
  }

  @override
  Future<void> stop() async {
    _logTransport('stop');
    await _player.stop();
    await super.stop();
  }

  Future<void> disposeHandler() async {
    await _playbackSubscription?.cancel();
    await _durationSubscription?.cancel();
    await _errorSubscription?.cancel();
    await _interruptionSubscription?.cancel();
    await _becomingNoisySubscription?.cancel();
    await _player.dispose();
  }

  void _clearTransitionSnapshot() {
    _mediaItemBeforeTransition = null;
    _queueIndexBeforeTransition = null;
  }

  void _updateDuration(Duration? duration) {
    if (duration == null) return;
    final item = _currentMediaItem;
    if (item == null || item.duration == duration) return;
    _currentMediaItem = preserveMediaItemArtHeaders(
      item,
      item.copyWith(duration: duration),
    );
    mediaItem.add(_currentMediaItem);
  }

  void _broadcastError(Object error, StackTrace stackTrace) {
    unawaited(
      AppLogger.write(
        'player-error',
        'engine_error state=${_player.processingState.name} '
            'playing=${_player.playing} positionMs=${_player.position.inMilliseconds} '
            'bufferedMs=${_player.bufferedPosition.inMilliseconds} '
            'error=$error',
      ),
    );
    if (_trackTransitionActive) {
      playbackState.add(_transitionState(_player.snapshot));
      return;
    }
    playbackState.add(
      _transformEvent(_player.snapshot).copyWith(
        processingState: AudioProcessingState.error,
        errorCode: 1,
        errorMessage: error.toString(),
      ),
    );
  }

  void _broadcastState(BassPlaybackSnapshot event) {
    playbackState.add(
      _trackTransitionActive ? _transitionState(event) : _transformEvent(event),
    );
  }

  PlaybackState _transitionState(BassPlaybackSnapshot event) {
    return _transformEvent(event).copyWith(
      processingState: AudioProcessingState.loading,
      playing: false,
      updatePosition: Duration.zero,
      bufferedPosition: Duration.zero,
      queueIndex: _queueIndex,
    );
  }

  PlaybackState _transformEvent(BassPlaybackSnapshot event) {
    final hasItem = _currentMediaItem != null;
    final controls = hasItem
        ? <MediaControl>[
            MediaControl.skipToPrevious,
            if (_player.playing) MediaControl.pause else MediaControl.play,
            MediaControl.skipToNext,
          ]
        : const <MediaControl>[];
    return PlaybackState(
      controls: controls,
      androidCompactActionIndices: hasItem ? const [0, 1, 2] : null,
      systemActions: hasItem
          ? const {
              MediaAction.seek,
              MediaAction.seekForward,
              MediaAction.seekBackward,
              MediaAction.setRepeatMode,
              MediaAction.setShuffleMode,
            }
          : const {},
      processingState: switch (_player.processingState) {
        BassProcessingState.idle => AudioProcessingState.idle,
        BassProcessingState.loading => AudioProcessingState.loading,
        BassProcessingState.buffering => AudioProcessingState.buffering,
        BassProcessingState.ready => AudioProcessingState.ready,
        BassProcessingState.completed => AudioProcessingState.completed,
        BassProcessingState.error => AudioProcessingState.error,
      },
      playing: _player.playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: _queueIndex,
      repeatMode: _repeatMode,
      shuffleMode: _shuffleMode,
    );
  }

  void _logTransport(String action, {Duration? target}) {
    final extras = _currentMediaItem?.extras;
    final kind = extras?['trackKind']?.toString() ?? 'none';
    final source = extras?['source']?.toString() ?? 'none';
    final quality = extras?['quality']?.toString() ?? 'none';
    unawaited(
      AppLogger.write(
        'player-transport',
        'action=$action state=${_player.processingState.name} '
            'playing=${_player.playing} positionMs=${_player.position.inMilliseconds} '
            'targetMs=${target?.inMilliseconds ?? -1} '
            'kind=$kind source=$source quality=$quality',
      ),
    );
  }

  String _artworkExtension(Uint8List bytes) {
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return 'png';
    }
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return 'webp';
    }
    return 'jpg';
  }
}

final playerAudioHandlerProvider = Provider<PlayerAudioHandler>((ref) {
  throw StateError('playerAudioHandlerProvider must be overridden at startup');
});
