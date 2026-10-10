import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:music_home_widget/music_home_widget.dart';

import '../../core/services/app_logger.dart';
import '../../core/ui/cover_image_source.dart';
import 'player_audio_handler.dart';
import 'player_controller.dart';

final musicHomeWidgetProvider = Provider<MusicHomeWidgetService>((ref) {
  final service = MusicHomeWidgetService(ref);
  ref.onDispose(service.dispose);
  return service;
});

// Activate with the normal player startup, or explicitly for a widget cold
// start. Position/lyric ticks do not trigger widget redraws.
final musicHomeWidgetSyncProvider = Provider<void>((ref) {
  final service = ref.read(musicHomeWidgetProvider);
  ref.listen<PlayerState>(playerControllerProvider, (_, state) {
    service.publish(state);
  }, fireImmediately: true);
});

class MusicHomeWidgetService {
  MusicHomeWidgetService(this._ref);

  final Ref _ref;
  bool _available = false;
  bool _openPlayerRequested = false;
  Future<void> _controls = Future<void>.value();
  int _publishGeneration = 0;
  bool _hasPublishedTrack = false;
  PlayerTrack? _lastPublishedTrack;
  (bool, bool)? _lastPlayback;
  StreamSubscription<PlaybackState>? _playbackSubscription;
  Future<void> Function()? onOpenPlayer;

  Future<void> initialize() async {
    if (!Platform.isAndroid) return;
    musicHomeWidgetChannel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'control':
          final action = call.arguments as String;
          // Acknowledge receipt before loading audio; the Android broadcast
          // must not stay alive for a slow music-source/network request.
          _controls = _controls.then((_) => _control(action)).catchError((
            Object error,
            StackTrace stack,
          ) async {
            await AppLogger.write('home-widget', 'control failed: $error');
          });
          return true;
        case 'openPlayer':
          _openPlayerRequested = true;
          await onOpenPlayer?.call();
          return true;
      }
      throw MissingPluginException(
        'Unknown home widget method: ${call.method}',
      );
    });
    try {
      _available = true;
      await musicHomeWidgetChannel.invokeMethod<void>('ready');
      // Subscribe to the background player itself. Transport updates must
      // neither wait for the UI controller nor for artwork to be cached.
      _playbackSubscription = _ref
          .read(playerAudioHandlerProvider)
          .playbackState
          .listen(_publishPlayback);
    } on MissingPluginException {
      _available = false;
    }
  }

  bool takeOpenPlayerRequest() {
    final requested = _openPlayerRequested;
    _openPlayerRequested = false;
    return requested;
  }

  Future<void> _control(String action) async {
    _ref.read(musicHomeWidgetSyncProvider);
    final audioHandler = _ref.read(playerAudioHandlerProvider);
    final shouldPlay = !audioHandler.playing;
    final player = _ref.read(playerControllerProvider.notifier);
    await player.waitForSessionRestore();
    if (!_ref.read(playerControllerProvider).hasTrack) {
      _openPlayerRequested = true;
      await musicHomeWidgetChannel.invokeMethod<void>('openApp');
      return;
    }
    switch (action) {
      case 'toggle':
        if (audioHandler.playing != shouldPlay) {
          await player.toggle();
        }
      case 'previous':
        await player.playPrevious();
      case 'next':
        await player.playNext();
    }
    _publishPlayback(audioHandler.playbackState.value);
  }

  void publish(PlayerState state) {
    if (!_available) return;
    if (_hasPublishedTrack && identical(_lastPublishedTrack, state.track)) {
      return;
    }
    _hasPublishedTrack = true;
    _lastPublishedTrack = state.track;
    final generation = ++_publishGeneration;
    unawaited(_publish(state, generation));
  }

  Future<void> _publish(PlayerState state, int generation) async {
    try {
      final track = state.track;
      final embeddedArt = await _ref
          .read(playerAudioHandlerProvider)
          .cacheArtwork(track?.coverBytes);
      if (generation != _publishGeneration) return;
      final cover =
          embeddedArt?.toString() ??
          CoverImageSource.normalizeUrl(track?.coverUrl, size: 500);
      await musicHomeWidgetChannel.invokeMethod<void>('update', {
        'trackId': track?.id ?? '',
        'title': track?.title ?? '',
        'artist': track?.artist ?? '',
        'cover': cover ?? '',
        'headers': CoverImageSource.headersFor(cover) ?? <String, String>{},
      });
    } catch (error) {
      await AppLogger.write('home-widget', 'update failed: $error');
    }
  }

  void _publishPlayback(PlaybackState state) {
    if (!_available) return;
    final playing =
        state.playing &&
        state.processingState != AudioProcessingState.idle &&
        state.processingState != AudioProcessingState.completed &&
        state.processingState != AudioProcessingState.error;
    final loading =
        state.processingState == AudioProcessingState.loading ||
        state.processingState == AudioProcessingState.buffering;
    final playback = (playing, loading);
    if (_lastPlayback == playback) return;
    _lastPlayback = playback;
    unawaited(_updatePlayback(playing: playing, loading: loading));
  }

  Future<void> _updatePlayback({
    required bool playing,
    required bool loading,
  }) async {
    try {
      await musicHomeWidgetChannel.invokeMethod<void>('updatePlayback', {
        'playing': playing,
        'loading': loading,
      });
    } catch (error) {
      _lastPlayback = null;
      await AppLogger.write('home-widget', 'playback update failed: $error');
    }
  }

  void dispose() {
    unawaited(_playbackSubscription?.cancel());
  }
}
