import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'artwork_disk_cache.dart';
import 'artwork_thumbnail_stub.dart'
    if (dart.library.ui) 'artwork_thumbnail_flutter.dart';
import 'tagger.dart';
import 'media_artwork_stub.dart'
    if (dart.library.ui) 'media_artwork_flutter.dart';

/// Loads embedded covers on demand without allowing a visible list to start an
/// unbounded number of metadata reads at once.
class EmbeddedArtworkCache {
  const EmbeddedArtworkCache._();

  static const int _maxEntries = 256;
  static const int _maxBytes = 24 * 1024 * 1024;
  static const int _maxConcurrentReads = 2;
  static const Duration _readTimeout = Duration(seconds: 8);

  static final LinkedHashMap<String, Uint8List?> _cache = LinkedHashMap();
  static final Map<String, _ArtworkLoad> _loads = {};
  static final Queue<_ArtworkLoad> _pending = Queue();
  static final Map<String, Object> _versions = {};
  static final Map<String, String> _identities = {};
  static int _activeReads = 0;
  static int _cachedBytes = 0;

  static EmbeddedArtworkRequest subscribe(String path, {Object? version}) {
    final normalizedPath = path.trim();
    if (normalizedPath.isEmpty) {
      return EmbeddedArtworkRequest._completed(null);
    }
    final key = _cacheKey(normalizedPath, version ?? _versions[normalizedPath]);

    if (_cache.containsKey(key)) {
      final cached = _cache.remove(key);
      _cache[key] = cached;
      return EmbeddedArtworkRequest._completed(cached);
    }

    final existing = _loads[key];
    if (existing != null) {
      existing.consumers++;
      return EmbeddedArtworkRequest._(existing);
    }

    final load = _ArtworkLoad(key: key, path: normalizedPath, consumers: 1);
    _loads[key] = load;
    _pending.add(load);
    _pump();
    return EmbeddedArtworkRequest._(load);
  }

  static Future<Uint8List?> load(String path, {Object? version}) {
    return subscribe(path, version: version).future;
  }

  static Uint8List? peek(String path, {Object? version}) =>
      _cache[_cacheKey(path.trim(), version ?? _versions[path.trim()])];

  static void registerVersion(String path, Object version, {String? identity}) {
    _versions[path.trim()] = version;
    if (identity != null) _identities[path.trim()] = identity;
  }

  /// Import and visible rows share the same extraction job. Disk-only hits do
  /// not contain text tags, so an index migration may request one metadata read.
  static Future<EmbeddedAudioTags?> readForIndex(
    String path, {
    Object? version,
  }) async {
    final key = _cacheKey(path, version ?? _versions[path]);
    var load = _loads[key];
    if (load == null) {
      load = _ArtworkLoad(key: key, path: path, consumers: 0);
      _loads[key] = load;
      _pending.add(load);
    }
    load.needsMetadata = true;
    load.consumers++;
    _pump();
    try {
      return await load.metadata.future;
    } finally {
      _release(load);
    }
  }

  static Future<void> seed(
    String path,
    Uint8List bytes, {
    Object? version,
  }) async {
    final key = _cacheKey(path, version ?? _versions[path]);
    try {
      final thumbnail = await artworkThumbnail(bytes);
      _store(key, thumbnail);
      await ArtworkDiskCache.write(key, thumbnail);
    } catch (_) {
      // A bad image must not prevent the download or library update.
    }
  }

  static void evictPath(String path) {
    final normalizedPath = _identities[path.trim()] ?? path.trim();
    if (normalizedPath.isEmpty) return;
    final versionedPrefix = '$normalizedPath\u0000';
    final matches = _cache.keys
        .where(
          (key) => key == normalizedPath || key.startsWith(versionedPrefix),
        )
        .toList(growable: false);
    for (final key in matches) {
      _cachedBytes -= _cache.remove(key)?.length ?? 0;
      unawaited(ArtworkDiskCache.remove(key));
    }

    final pendingOrActive = _loads.values
        .where(
          (load) =>
              (load.key == normalizedPath ||
              load.key.startsWith(versionedPrefix)),
        )
        .toList(growable: false);
    for (final load in pendingOrActive) {
      load.invalidated = true;
      if (!load.active) _cancelPending(load);
    }
    final version = _versions.remove(normalizedPath);
    unawaited(ArtworkDiskCache.remove(_cacheKey(normalizedPath, version)));
  }

  static String _cacheKey(String path, Object? version) {
    final identity = _identities[path] ?? path;
    return version == null ? identity : '$identity\u0000$version';
  }

  static void _pump() {
    while (_activeReads < _maxConcurrentReads && _pending.isNotEmpty) {
      final load = _pending.removeFirst();
      if (load.invalidated || load.consumers == 0) {
        _complete(load, null);
        continue;
      }
      load.active = true;
      _activeReads++;
      unawaited(_run(load));
    }
  }

  static Future<void> _run(_ArtworkLoad load) async {
    Uint8List? bytes;
    EmbeddedAudioTags? tags;
    var success = false;
    try {
      final disk = await ArtworkDiskCache.read(load.key);
      if (disk.hit && !load.needsMetadata) {
        bytes = disk.bytes;
      } else {
        final systemArtwork = load.needsMetadata
            ? null
            : await mediaArtwork(load.path).timeout(_readTimeout);
        tags = systemArtwork != null
            ? EmbeddedAudioTags(artworkBytes: systemArtwork)
            : await Tagger.readEmbeddedTags(
                load.path,
                includeLyrics: false,
              ).timeout(_readTimeout);
        final artwork = tags?.artworkBytes;
        try {
          bytes = artwork == null || artwork.isEmpty
              ? null
              : await artworkThumbnail(artwork);
        } catch (_) {
          // Invalid artwork must not discard successfully parsed text tags.
          bytes = null;
        }
        if (!load.invalidated) await ArtworkDiskCache.write(load.key, bytes);
      }
      success = true;
    } catch (_) {
      bytes = null;
    }

    if (load.invalidated) bytes = null;
    if (!load.invalidated && load.consumers > 0) _store(load.key, bytes);
    _complete(load, bytes, tags: success && !load.invalidated ? tags : null);
    _activeReads--;
    _pump();
  }

  static void _release(_ArtworkLoad load) {
    if (load.consumers > 0) load.consumers--;
    if (load.consumers == 0 && !load.active) _cancelPending(load);
  }

  static void _cancelPending(_ArtworkLoad load) {
    _pending.remove(load);
    _complete(load, null);
  }

  static void _complete(
    _ArtworkLoad load,
    Uint8List? bytes, {
    EmbeddedAudioTags? tags,
  }) {
    if (identical(_loads[load.key], load)) _loads.remove(load.key);
    if (!load.completer.isCompleted) load.completer.complete(bytes);
    if (!load.metadata.isCompleted) load.metadata.complete(tags);
  }

  static void _store(String key, Uint8List? bytes) {
    _cachedBytes -= _cache.remove(key)?.length ?? 0;
    _cache[key] = bytes;
    _cachedBytes += bytes?.length ?? 0;
    while (_cache.length > _maxEntries || _cachedBytes > _maxBytes) {
      _cachedBytes -= _cache.remove(_cache.keys.first)?.length ?? 0;
    }
  }
}

class EmbeddedArtworkRequest {
  EmbeddedArtworkRequest._(_ArtworkLoad load)
    : _load = load,
      future = load.completer.future;

  EmbeddedArtworkRequest._completed(Uint8List? bytes)
    : _load = null,
      future = Future<Uint8List?>.value(bytes);

  final _ArtworkLoad? _load;
  final Future<Uint8List?> future;
  bool _cancelled = false;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    final load = _load;
    if (load != null) EmbeddedArtworkCache._release(load);
  }
}

class _ArtworkLoad {
  _ArtworkLoad({
    required this.key,
    required this.path,
    required this.consumers,
  });

  final String key;
  final String path;
  final Completer<Uint8List?> completer = Completer<Uint8List?>();
  final Completer<EmbeddedAudioTags?> metadata =
      Completer<EmbeddedAudioTags?>();
  bool needsMetadata = false;
  int consumers;
  bool active = false;
  bool invalidated = false;
}
