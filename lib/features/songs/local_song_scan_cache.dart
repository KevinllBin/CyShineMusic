import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/services/app_logger.dart';
import '../../core/services/artwork_disk_cache.dart';
import '../../core/services/embedded_artwork_cache.dart';
import '../../core/services/local_audio_library_events.dart';
import '../../core/services/permission_service.dart';
import '../../core/services/saf_storage.dart';
import '../../core/services/storage_location.dart';
import '../../core/storage/settings_store.dart';
import 'local_song_scan_models.dart';
import 'local_song_scanner.dart';

export 'local_song_scan_models.dart';

/// A durable library index. Only first import, folder changes and explicit
/// refresh enumerate storage; downloads and deletions update individual rows.
class LocalSongScanCache extends ChangeNotifier {
  LocalSongScanCache({List<String> Function()? directories})
    : _directories = directories {
    _stopListening = LocalAudioLibraryEvents.listen(_handleFileChange);
  }

  static const _fileName = 'local_song_scan_v1.json';
  final List<String> Function()? _directories;
  late final void Function() _stopListening;
  final _mutations = <String, ({int revision, LocalSongFileSnapshot? file})>{};
  final _eventRevisions = <String, int>{};
  final _aliases = <String, String>{};
  LocalSongScanSnapshot? _snapshot;
  Future<void>? _loadFuture;
  Future<void>? _scanFuture;
  Future<void>? _metadataFuture;
  Future<void> _writeFuture = Future.value();
  List<String>? _scanDirectories;
  Timer? _saveTimer;
  Timer? _notifyTimer;
  int _scanGeneration = 0;
  int _revision = 0;
  bool _disposed = false;

  LocalSongScanSnapshot? get snapshot => _snapshot;

  String pathKey(String path) {
    final key = localSongPathKey(path);
    return _aliases[key] ?? key;
  }

  Future<void> ensureLoaded() => _loadFuture ??= _load();

  Future<void> _load() async {
    try {
      final file = await _cacheFile();
      if (!await file.exists()) return;
      final decoded = jsonDecode(await file.readAsString());
      if (_disposed) return;
      if (decoded is Map) {
        _snapshot = LocalSongScanSnapshot.fromJson(
          Map<String, dynamic>.from(decoded),
        );
        _registerArtwork();
        notifyListeners();
        if (!Platform.isAndroid || _snapshot!.backend == 'compatibility') {
          _warmMetadata();
        }
        unawaited(
          AppLogger.write(
            'local-library',
            'restore files=${_snapshot!.files.length}',
          ),
        );
      }
    } catch (_) {
      // A damaged index is rebuilt once. Failed scans preserve known rows.
    }
  }

  Future<void> ensureScan({
    String? directory,
    List<String>? directories,
  }) async {
    final selected = _scanRoots(directory, directories);
    await ensureLoaded();
    if (_disposed) return;
    final current = _snapshot;
    if (current != null &&
        current.initialized &&
        current.matchesDirectories(selected)) {
      final upgrade =
          Platform.isAndroid &&
          current.backend == 'filesystem' &&
          (await PermissionService.hasAudioLibraryRead() ||
              await PermissionService.hasExternalStorageWrite());
      if (!upgrade) {
        _warmMetadata();
        return;
      }
    }
    await refresh(directories: selected);
  }

  Future<void> refresh({String? directory, List<String>? directories}) async {
    final selected = _scanRoots(directory, directories);
    await ensureLoaded();
    if (_disposed) return;
    final running = _scanFuture;
    if (running != null && listEquals(_scanDirectories, selected)) {
      return running;
    }
    final generation = ++_scanGeneration;
    final startedRevision = _revision;
    _scanDirectories = selected;
    final future = _scanDirectoryContents(
      selected,
      generation,
      startedRevision,
    );
    _scanFuture = future;
    await future;
  }

  Future<void> _scanDirectoryContents(
    List<String> directories,
    int generation,
    int startedRevision,
  ) async {
    final watch = Stopwatch()..start();
    final previous = {
      for (final file in _snapshot?.files ?? const <LocalSongFileSnapshot>[])
        file.key: file,
    };
    try {
      final result = await LocalSongScanner.scan(
        directories,
        previous,
        () => _disposed || generation != _scanGeneration,
      );
      if (_disposed || generation != _scanGeneration) return;
      final files = result.files;
      final errors = result.errors;
      // Retain metadata completed during enumeration, then merge file operations
      // newer than this scan. A successful deletion always wins over old rows.
      final latest = {
        for (final row in _snapshot?.files ?? const <LocalSongFileSnapshot>[])
          row.key: row,
      };
      for (final entry in files.entries.toList()) {
        if (entry.value.contentUri == null) {
          files[entry.key] = entry.value.retainingMetadata(
            latest[entry.key],
            retryEmpty: true,
          );
        }
      }
      for (final entry in _mutations.entries) {
        final file = entry.value.file;
        if (entry.value.revision <= startedRevision) {
          if (file == null ||
              files.containsKey(entry.key) ||
              !directories.any(
                (root) => isFileInScanDirectory(file.path, root),
              )) {
            continue;
          }
          try {
            if (await SafStorage.exists(file.playbackPath)) {
              files[entry.key] = file;
            }
          } catch (_) {
            /* Keep the scan result if this old handle is unavailable. */
          }
          continue;
        }
        if (file == null) {
          files.remove(entry.key);
        } else if (directories.any(
          (root) => isFileInScanDirectory(file.path, root),
        )) {
          files[entry.key] = file;
        }
      }
      for (final old in previous.values) {
        final next = files[old.key];
        if (next == null || next.fingerprint != old.fingerprint) {
          EmbeddedArtworkCache.evictPath(old.path);
        }
      }
      final enumerationMs = watch.elapsedMilliseconds;
      await save(
        directories: directories,
        files: files.values.toList(),
        error: errors.isEmpty ? null : '无法读取本地音乐文件夹：${errors.join('\n')}',
        backend: result.backend,
      );
      _warmMetadata();
      await _metadataFuture;
      if (!_disposed && generation == _scanGeneration) await flush();
      unawaited(
        AppLogger.write(
          'local-library',
          'scan backend=${result.backend} files=${files.length} errors=${errors.length} enumerationMs=$enumerationMs totalMs=${watch.elapsedMilliseconds}',
        ),
      );
    } finally {
      if (generation == _scanGeneration) _scanFuture = null;
    }
  }

  Future<void> _handleFileChange(LocalAudioLibraryChange event) async {
    if (event.deletedPaths.isNotEmpty) {
      final revision = ++_revision;
      for (final path in event.deletedPaths) {
        _eventRevisions[localSongPathKey(path)] = revision;
      }
      if (_snapshot == null) await ensureLoaded();
      removePaths(
        event.deletedPaths.where(
          (path) => _eventRevisions[localSongPathKey(path)] == revision,
        ),
        revision: revision,
      );
      await flush();
      return;
    }
    if (event.path.isEmpty) return;
    final eventKey = localSongPathKey(event.path);
    final revision = ++_revision;
    _eventRevisions[eventKey] = revision;
    try {
      await ensureLoaded();
      if (_disposed || _eventRevisions[eventKey] != revision) return;
      final directories = normalizeScanDirectories(
        _directories?.call() ?? _snapshot?.directories ?? [],
      );
      final file = await savedLibraryFile(event.path, directories);
      if (file == null ||
          _disposed ||
          _eventRevisions[eventKey] != revision ||
          (_mutations[file.key]?.revision ?? 0) > revision) {
        return;
      }
      final key = file.key;
      final row = event.tags == null ? file : file.withMetadata(event.tags);
      _mutations[key] = (revision: revision, file: row);
      for (final alias in row.aliases) {
        _aliases[localSongPathKey(alias)] = key;
      }
      final old = _snapshot;
      final files = {
        for (final f in old?.files ?? const <LocalSongFileSnapshot>[]) f.key: f,
      };
      files[key] = row;
      _snapshot = LocalSongScanSnapshot(
        directories: old?.directories ?? directories,
        cachedAt: old?.cachedAt ?? DateTime.now(),
        files: List.unmodifiable(files.values),
        error: old?.error,
        initialized: old?.initialized ?? false,
        pathsLinked: old?.pathsLinked ?? false,
        backend: old?.backend ?? 'filesystem',
      );
      _registerFile(row);
      if (event.tags?.hasArtwork == true) {
        await EmbeddedArtworkCache.seed(
          row.playbackPath,
          event.tags!.artworkBytes!,
          version: row.fingerprint,
        );
      } else {
        await EmbeddedArtworkCache.load(
          row.playbackPath,
          version: row.fingerprint,
        );
      }
      if (_disposed) return;
      notifyListeners();
      await flush();
      _warmMetadata();
    } catch (error) {
      unawaited(AppLogger.write('local-library', 'file update failed: $error'));
    }
  }

  void removePaths(Iterable<String> paths, {int? revision}) {
    if (_disposed) return;
    final keys = paths.map(pathKey).toSet();
    final current = _snapshot;
    for (final key in keys) {
      _mutations[key] = (revision: revision ?? ++_revision, file: null);
    }
    if (current == null) return;
    final files = current.files.where((file) {
      if (!keys.contains(file.key)) return true;
      EmbeddedArtworkCache.evictPath(file.path);
      return false;
    }).toList();
    _snapshot = current.withFiles(files);
    notifyListeners();
    _scheduleSave();
  }

  void _registerFile(LocalSongFileSnapshot file) {
    EmbeddedArtworkCache.registerVersion(file.path, file.fingerprint);
    EmbeddedArtworkCache.registerVersion(
      file.playbackPath,
      file.fingerprint,
      identity: file.path,
    );
    for (final alias in [...file.aliases, file.playbackPath]) {
      _aliases[localSongPathKey(alias)] = file.key;
    }
  }

  void _registerArtwork() {
    for (final file in _snapshot?.files ?? const <LocalSongFileSnapshot>[]) {
      _registerFile(file);
    }
  }

  void _warmMetadata() {
    if (_disposed || _metadataFuture != null) return;
    _metadataFuture = _hydrateMetadata().whenComplete(() {
      _metadataFuture = null;
      if (!_disposed &&
          (_snapshot?.files.any(
                (file) => !file.metadataRead && !isContentLocation(file.path),
              ) ??
              false)) {
        _warmMetadata();
      }
    });
  }

  Future<void> _hydrateMetadata() async {
    final watch = Stopwatch()..start();
    var read = 0;
    while (!_disposed) {
      final pending =
          _snapshot?.files
              .where(
                (file) => !file.metadataRead && !isContentLocation(file.path),
              )
              .take(2)
              .toList() ??
          [];
      if (pending.isEmpty) break;
      await Future.wait(
        pending.map((file) async {
          final tags = await EmbeddedArtworkCache.readForIndex(
            file.path,
            version: file.fingerprint,
          );
          if (_disposed) return;
          final current = _snapshot;
          if (current == null) return;
          final index = current.files.indexWhere((row) => row.key == file.key);
          if (index < 0 ||
              current.files[index].fingerprint != file.fingerprint ||
              current.files[index].metadataRead) {
            return;
          }
          final files = [...current.files];
          files[index] = current.files[index].withMetadata(tags);
          _snapshot = current.withFiles(files);
          read++;
          _notifyTimer ??= Timer(const Duration(milliseconds: 120), () {
            _notifyTimer = null;
            if (!_disposed) notifyListeners();
          });
          _scheduleSave();
        }),
      );
    }
    if (read > 0) {
      unawaited(
        AppLogger.write(
          'local-library',
          'metadata files=$read elapsedMs=${watch.elapsedMilliseconds}',
        ),
      );
    }
  }

  Future<void> save({
    String? directory,
    List<String>? directories,
    required List<LocalSongFileSnapshot> files,
    String? error,
    String backend = 'filesystem',
  }) async {
    if (_disposed) return;
    _snapshot = LocalSongScanSnapshot(
      directories: _scanRoots(directory, directories),
      cachedAt: DateTime.now(),
      files: List.unmodifiable(files),
      error: error,
      backend: backend,
    );
    _registerArtwork();
    notifyListeners();
    await flush();
  }

  void _scheduleSave() {
    _saveTimer ??= Timer(const Duration(milliseconds: 250), () {
      _saveTimer = null;
      unawaited(flush());
    });
  }

  Future<void> flush() {
    _saveTimer?.cancel();
    _saveTimer = null;
    _writeFuture = _writeFuture.then((_) async {
      if (_disposed || _snapshot == null) return;
      try {
        final file = await _cacheFile();
        if (_disposed) return;
        final serialized = jsonEncode(_snapshot!.toJson());
        await file.parent.create(recursive: true);
        final temporary = File('${file.path}.tmp');
        await temporary.writeAsString(serialized, flush: true);
        await temporary.rename(file.path);
      } catch (_) {
        // Preserve the last complete index if a write is interrupted.
      }
    });
    return _writeFuture;
  }

  /// Link older SAF download records to the same files in the direct index.
  /// Resolved aliases are persisted, so subsequent starts perform no lookups.
  Future<void> linkKnownPaths(Iterable<String> paths) async {
    if (_snapshot?.pathsLinked ?? false) return;
    final added = <String, List<String>>{};
    for (final path in paths.toSet()) {
      if (!isContentLocation(path) ||
          _aliases.containsKey(localSongPathKey(path))) {
        continue;
      }
      final local = await SafStorage.resolveLocalPath(
        path,
        requireReadable: false,
      );
      if (_disposed) return;
      if (local == null) continue;
      final key = localSongPathKey(local);
      if (!(_snapshot?.files.any((file) => file.key == key) ?? false)) continue;
      _aliases[localSongPathKey(path)] = key;
      (added[key] ??= []).add(path);
    }
    final current = _snapshot;
    if (current == null || _disposed) return;
    _snapshot = current.withFiles([
      for (final file in current.files)
        if (added.containsKey(file.key))
          file.withAliases([...file.aliases, ...added[file.key]!])
        else
          file,
    ], pathsLinked: true);
    if (added.isNotEmpty) notifyListeners();
    await flush();
  }

  Future<File> _cacheFile() async {
    final support = await getApplicationSupportDirectory();
    ArtworkDiskCache.configure(support.path);
    return File(p.join(support.path, _fileName));
  }

  @override
  void dispose() {
    _disposed = true;
    _scanGeneration++;
    _saveTimer?.cancel();
    _notifyTimer?.cancel();
    _stopListening();
    super.dispose();
  }
}

List<String> _scanRoots(String? directory, List<String>? directories) {
  final normalized = normalizeScanDirectories(directories ?? [?directory]);
  if (normalized.isEmpty) throw ArgumentError('至少需要一个本地音乐文件夹');
  return normalized;
}

final localSongScanCacheProvider = ChangeNotifierProvider<LocalSongScanCache>(
  (ref) => LocalSongScanCache(
    directories: () => ref.read(settingsProvider).localMusicDirs,
  ),
);
