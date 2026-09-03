library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum BassProcessingState { idle, loading, buffering, ready, completed, error }

enum BassBiquadFilter { peaking, lowShelf, highShelf, lowPass, highPass }

@immutable
class BassEqualizerBand {
  const BassEqualizerBand({
    required this.id,
    required this.filter,
    required this.frequencyHz,
    this.enabled = true,
    this.gainDb = 0,
    this.q = 0.707,
  });

  final String id;
  final BassBiquadFilter filter;
  final double frequencyHz;
  final bool enabled;
  final double gainDb;
  final double q;

  Map<String, Object> toMap() => {
    'id': id,
    'filter': filter.name,
    'frequencyHz': frequencyHz,
    'enabled': enabled,
    'gainDb': gainDb,
    'q': q,
  };
}

@immutable
class BassEqualizerConfiguration {
  const BassEqualizerConfiguration({
    required this.enabled,
    this.inputGainDb = 0,
    this.outputGainDb = 0,
    this.bands = const [],
  }) : assert(bands.length <= 32);

  const BassEqualizerConfiguration.disabled()
    : enabled = false,
      inputGainDb = 0,
      outputGainDb = 0,
      bands = const [];

  final bool enabled;
  final double inputGainDb;
  final double outputGainDb;
  final List<BassEqualizerBand> bands;

  Map<String, Object> toMap() => {
    'enabled': enabled,
    'inputGainDb': inputGainDb,
    'outputGainDb': outputGainDb,
    'bands': bands.map((band) => band.toMap()).toList(growable: false),
  };
}

@immutable
class BassEngineInfo {
  const BassEngineInfo({
    required this.version,
    required this.fxVersion,
    required this.plugins,
  });

  final String version;
  final String fxVersion;
  final Map<String, String> plugins;

  factory BassEngineInfo.fromMap(Map<Object?, Object?> map) {
    final rawPlugins = map['plugins'];
    return BassEngineInfo(
      version: map['version'] as String? ?? 'unknown',
      fxVersion: map['fxVersion'] as String? ?? 'unknown',
      plugins: rawPlugins is Map
          ? rawPlugins.map(
              (key, value) => MapEntry(key.toString(), value.toString()),
            )
          : const {},
    );
  }
}

@immutable
class BassPlaybackSnapshot {
  const BassPlaybackSnapshot({
    required this.playing,
    required this.processingState,
    required this.position,
    required this.bufferedPosition,
    required this.duration,
  });

  const BassPlaybackSnapshot.idle()
    : playing = false,
      processingState = BassProcessingState.idle,
      position = Duration.zero,
      bufferedPosition = Duration.zero,
      duration = null;

  final bool playing;
  final BassProcessingState processingState;
  final Duration position;
  final Duration bufferedPosition;
  final Duration? duration;

  BassPlaybackSnapshot copyWith({
    bool? playing,
    BassProcessingState? processingState,
    Duration? position,
    Duration? bufferedPosition,
    Duration? duration,
    bool clearDuration = false,
  }) {
    return BassPlaybackSnapshot(
      playing: playing ?? this.playing,
      processingState: processingState ?? this.processingState,
      position: position ?? this.position,
      bufferedPosition: bufferedPosition ?? this.bufferedPosition,
      duration: clearDuration ? null : duration ?? this.duration,
    );
  }
}

class BassPlayerException implements Exception {
  const BassPlayerException({
    required this.code,
    required this.message,
    this.operation,
  });

  final int code;
  final String message;
  final String? operation;

  factory BassPlayerException.fromPlatform(PlatformException exception) {
    final details = exception.details;
    final detailCode = details is Map ? details['bassCode'] : null;
    final parsedCode = detailCode is num
        ? detailCode.toInt()
        : int.tryParse(
            RegExp(r'^BASS_(-?\d+)$').firstMatch(exception.code)?.group(1) ??
                '',
          );
    return BassPlayerException(
      code: parsedCode ?? -1,
      message: exception.message ?? exception.code,
      operation: details is Map ? details['operation']?.toString() : null,
    );
  }

  @override
  String toString() {
    final prefix = operation == null ? 'BASS' : 'BASS $operation';
    return '$prefix error $code: $message';
  }
}

class BassPlayer {
  BassPlayer({MethodChannel? methodChannel, EventChannel? eventChannel})
    : _methods =
          methodChannel ??
          const MethodChannel('com.cyshine.music/bass_player/methods'),
      _events =
          eventChannel ??
          const EventChannel('com.cyshine.music/bass_player/events');

  final MethodChannel _methods;
  final EventChannel _events;
  final Stopwatch _clock = Stopwatch()..start();
  final StreamController<BassPlaybackSnapshot> _playbackController =
      StreamController<BassPlaybackSnapshot>.broadcast(sync: true);
  final StreamController<Duration> _positionController =
      StreamController<Duration>.broadcast(sync: true);
  final StreamController<Duration?> _durationController =
      StreamController<Duration?>.broadcast(sync: true);
  final StreamController<BassPlayerException> _errorController =
      StreamController<BassPlayerException>.broadcast(sync: true);

  BassPlaybackSnapshot _snapshot = const BassPlaybackSnapshot.idle();
  Duration _anchorPosition = Duration.zero;
  Duration _anchorElapsed = Duration.zero;
  StreamSubscription<Object?>? _eventSubscription;
  Timer? _positionTimer;
  Future<BassEngineInfo>? _initialization;
  BassEqualizerConfiguration? _pendingEqualizer;
  bool _equalizerPumpRunning = false;
  bool _disposed = false;

  Stream<BassPlaybackSnapshot> get playbackEventStream =>
      _playbackController.stream;
  Stream<Duration> get positionStream => _positionController.stream;
  Stream<Duration?> get durationStream => _durationController.stream;
  Stream<BassPlayerException> get errorStream => _errorController.stream;
  BassPlaybackSnapshot get snapshot => _snapshot;
  Duration get position => _interpolatedPosition();
  Duration? get duration => _snapshot.duration;
  Duration get bufferedPosition => _snapshot.bufferedPosition;
  bool get playing => _snapshot.playing;
  BassProcessingState get processingState => _snapshot.processingState;
  double get speed => 1;

  Future<BassEngineInfo> initialize() async {
    _throwIfDisposed();
    final existing = _initialization;
    if (existing != null) return await existing;

    final pending = _initialize();
    _initialization = pending;
    try {
      return await pending;
    } catch (_) {
      if (identical(_initialization, pending)) _initialization = null;
      rethrow;
    }
  }

  Future<BassEngineInfo> _initialize() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      throw UnsupportedError('BASS playback is available on Android only');
    }
    _eventSubscription ??= _events.receiveBroadcastStream().listen(
      _handleEvent,
      onError: _handleStreamError,
    );
    final raw = await _invokeMap('initialize');
    if (_disposed) throw StateError('BassPlayer was disposed during startup');
    return BassEngineInfo.fromMap(raw);
  }

  Future<Duration?> load(
    Uri source, {
    Map<String, String> headers = const {},
    String? formatHint,
  }) async {
    await initialize();
    _applyLocalState(
      _snapshot.copyWith(
        playing: false,
        processingState: BassProcessingState.loading,
        position: Duration.zero,
        bufferedPosition: Duration.zero,
        clearDuration: true,
      ),
    );
    final raw = await _invokeMap('load', {
      'uri': source.toString(),
      'headers': headers,
      'formatHint': formatHint,
    });
    _updateFromMap(raw, notifyPlayback: true);
    return _snapshot.duration;
  }

  Future<void> play() async {
    await initialize();
    _updateFromMap(await _invokeMap('play'), notifyPlayback: true);
  }

  Future<void> pause() async {
    if (_initialization == null) return;
    _updateFromMap(await _invokeMap('pause'), notifyPlayback: true);
  }

  Future<void> stop() async {
    if (_initialization == null) return;
    _updateFromMap(await _invokeMap('stop'), notifyPlayback: true);
  }

  Future<void> seek(Duration position) async {
    if (_initialization == null) return;
    _updateFromMap(
      await _invokeMap('seek', {'positionMs': position.inMilliseconds}),
      notifyPlayback: true,
    );
  }

  Future<void> setVolume(double volume) async {
    if (_initialization == null) return;
    await _invokeMap('setVolume', {'volume': volume.clamp(0.0, 1.0)});
  }

  Future<void> setEqualizer(BassEqualizerConfiguration configuration) async {
    _pendingEqualizer = configuration;
    if (_equalizerPumpRunning) return;
    _equalizerPumpRunning = true;
    Object? firstError;
    StackTrace? firstStackTrace;
    try {
      while (!_disposed) {
        final pending = _pendingEqualizer;
        _pendingEqualizer = null;
        if (pending == null) break;
        try {
          await initialize();
          await _invokeMap('setEqualizer', pending.toMap());
        } catch (error, stackTrace) {
          firstError ??= error;
          firstStackTrace ??= stackTrace;
        }
      }
    } finally {
      _equalizerPumpRunning = false;
    }
    if (firstError != null) {
      Error.throwWithStackTrace(firstError, firstStackTrace!);
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _positionTimer?.cancel();
    _positionTimer = null;
    await _eventSubscription?.cancel();
    _eventSubscription = null;
    if (_initialization != null) {
      try {
        await _methods.invokeMethod<void>('dispose');
      } on MissingPluginException {
        // A unit test or a shutting-down Flutter engine may have no Android
        // plugin attached. The Dart resources still need to be released.
      }
    }
    await _playbackController.close();
    await _positionController.close();
    await _durationController.close();
    await _errorController.close();
  }

  Future<Map<Object?, Object?>> _invokeMap(
    String method, [
    Object? arguments,
  ]) async {
    try {
      final value = await _methods.invokeMethod<Object?>(method, arguments);
      if (value is Map<Object?, Object?>) return value;
      if (value is Map) return Map<Object?, Object?>.from(value);
      return const {};
    } on PlatformException catch (error) {
      throw BassPlayerException.fromPlatform(error);
    }
  }

  void _handleEvent(Object? event) {
    if (_disposed || event is! Map) return;
    final map = Map<Object?, Object?>.from(event);
    _updateFromMap(map);
    if (map['event'] == 'error') {
      _errorController.add(
        BassPlayerException(
          code: (map['errorCode'] as num?)?.toInt() ?? -1,
          message: map['errorMessage']?.toString() ?? 'unknown error',
          operation: map['operation']?.toString(),
        ),
      );
    }
  }

  void _handleStreamError(Object error, StackTrace stackTrace) {
    if (_disposed) return;
    final exception = error is PlatformException
        ? BassPlayerException.fromPlatform(error)
        : BassPlayerException(code: -1, message: error.toString());
    _errorController.add(exception);
  }

  void _updateFromMap(
    Map<Object?, Object?> map, {
    bool notifyPlayback = false,
  }) {
    if (_disposed || !map.containsKey('processingState')) return;
    final next = BassPlaybackSnapshot(
      playing: map['playing'] as bool? ?? false,
      processingState: _processingState(map['processingState']?.toString()),
      position: _duration(map['positionMs']) ?? Duration.zero,
      bufferedPosition: _duration(map['bufferedPositionMs']) ?? Duration.zero,
      duration: _duration(map['durationMs']),
    );
    _applySnapshot(next, notifyPlayback: notifyPlayback);
  }

  void _applyLocalState(BassPlaybackSnapshot next) {
    _applySnapshot(next, notifyPlayback: true);
  }

  void _applySnapshot(
    BassPlaybackSnapshot next, {
    required bool notifyPlayback,
  }) {
    final previous = _snapshot;
    _snapshot = next;
    _anchorPosition = next.position;
    _anchorElapsed = _clock.elapsed;
    _syncPositionTimer();
    _positionController.add(next.position);
    if (previous.duration != next.duration) {
      _durationController.add(next.duration);
    }
    if (notifyPlayback ||
        previous.playing != next.playing ||
        previous.processingState != next.processingState ||
        previous.duration != next.duration) {
      // MediaSession extrapolates position from updatePosition/updateTime.
      // Publishing every 100 ms can starve incoming system transport commands
      // on vendor Android builds, so native anchors only update the lyric/UI
      // clock unless playback state materially changed.
      _playbackController.add(next);
    }
  }

  void _publishInterpolatedPosition() {
    if (_disposed || !_snapshot.playing) return;
    if (_snapshot.processingState != BassProcessingState.ready) return;
    _positionController.add(_interpolatedPosition());
  }

  void _syncPositionTimer() {
    final shouldRun =
        !_disposed &&
        _snapshot.playing &&
        _snapshot.processingState == BassProcessingState.ready;
    if (shouldRun) {
      _positionTimer ??= Timer.periodic(
        const Duration(milliseconds: 40),
        (_) => _publishInterpolatedPosition(),
      );
    } else {
      _positionTimer?.cancel();
      _positionTimer = null;
    }
  }

  Duration _interpolatedPosition() {
    if (!_snapshot.playing ||
        _snapshot.processingState != BassProcessingState.ready) {
      return _anchorPosition;
    }
    var result = _anchorPosition + (_clock.elapsed - _anchorElapsed);
    final duration = _snapshot.duration;
    if (duration != null && result > duration) result = duration;
    return result.isNegative ? Duration.zero : result;
  }

  BassProcessingState _processingState(String? name) {
    for (final value in BassProcessingState.values) {
      if (value.name == name) return value;
    }
    return BassProcessingState.idle;
  }

  Duration? _duration(Object? milliseconds) {
    if (milliseconds is! num || milliseconds.toInt() < 0) return null;
    return Duration(milliseconds: milliseconds.toInt());
  }

  void _throwIfDisposed() {
    if (_disposed) throw StateError('BassPlayer has been disposed');
  }
}
