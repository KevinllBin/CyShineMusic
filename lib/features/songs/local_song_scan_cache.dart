import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const _audioExtensions = {
  'mp3',
  'flac',
  'm4a',
  'aac',
  'ogg',
  'wav',
  'ape',
  'wma',
};

@immutable
class LocalSongFileSnapshot {
  const LocalSongFileSnapshot({
    required this.path,
    required this.fileName,
    required this.extension,
    required this.createdAt,
    required this.modifiedAt,
    required this.sizeBytes,
  });

  final String path;
  final String fileName;
  final String extension;
  final DateTime createdAt;
  final DateTime modifiedAt;
  final int sizeBytes;

  factory LocalSongFileSnapshot.fromJson(Map<String, dynamic> json) {
    return LocalSongFileSnapshot(
      path: json['path'] as String? ?? '',
      fileName: json['fileName'] as String? ?? '',
      extension: json['extension'] as String? ?? '',
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      modifiedAt:
          DateTime.tryParse(json['modifiedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'path': path,
    'fileName': fileName,
    'extension': extension,
    'createdAt': createdAt.toIso8601String(),
    'modifiedAt': modifiedAt.toIso8601String(),
    'sizeBytes': sizeBytes,
  };
}

@immutable
class LocalSongScanSnapshot {
  const LocalSongScanSnapshot({
    String? directory,
    List<String>? directories,
    required this.cachedAt,
    required this.files,
    this.error,
  }) : _directory = directory,
       _directories = directories;

  final String? _directory;
  final List<String>? _directories;
  List<String> get directories =>
      _directories ?? [if (_directory?.isNotEmpty ?? false) _directory!];
  String get directory => directories.firstOrNull ?? '';
  final DateTime cachedAt;
  final List<LocalSongFileSnapshot> files;
  final String? error;

  bool matchesDirectories(List<String> values) =>
      listEquals(directories, _normalizeDirectories(values));

  factory LocalSongScanSnapshot.fromJson(Map<String, dynamic> json) {
    final rawFiles = json['files'];
    final files = <LocalSongFileSnapshot>[];
    if (rawFiles is List) {
      for (final item in rawFiles) {
        if (item is Map) {
          final file = LocalSongFileSnapshot.fromJson(
            Map<String, dynamic>.from(item),
          );
          if (file.path.isNotEmpty && file.fileName.isNotEmpty) files.add(file);
        }
      }
    }
    final rawDirectories = json['directories'];
    return LocalSongScanSnapshot(
      directories: _normalizeDirectories(
        rawDirectories is List
            ? rawDirectories.whereType<String>().toList()
            : [json['directory'] as String? ?? ''],
      ),
      cachedAt:
          DateTime.tryParse(json['cachedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      files: List.unmodifiable(files),
      error: json['error'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'directory': directory,
    'directories': directories,
    'cachedAt': cachedAt.toIso8601String(),
    'files': [for (final file in files) file.toJson()],
    if (error != null) 'error': error,
  };
}

class LocalSongScanCache extends ChangeNotifier {
  static const _fileName = 'local_song_scan_v1.json';

  LocalSongScanSnapshot? _snapshot;
  Future<void>? _loadFuture;
  Future<void>? _scanFuture;
  List<String>? _scanDirectories;
  int _scanGeneration = 0;

  LocalSongScanSnapshot? get snapshot => _snapshot;

  Future<void> ensureLoaded() => _loadFuture ??= _load();

  Future<void> _load() async {
    try {
      final file = await _cacheFile();
      if (!await file.exists()) return;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map) {
        _snapshot = LocalSongScanSnapshot.fromJson(
          Map<String, dynamic>.from(decoded),
        );
        notifyListeners();
      }
    } catch (_) {
      // A corrupt cache must never prevent the library from being rescanned.
      _snapshot = null;
    }
  }

  Future<void> ensureScan({
    String? directory,
    List<String>? directories,
  }) async {
    final selectedDirectories = _scanRoots(directory, directories);
    await ensureLoaded();
    final snapshot = _snapshot;
    final fresh =
        snapshot != null &&
        snapshot.matchesDirectories(selectedDirectories) &&
        snapshot.error == null &&
        DateTime.now().difference(snapshot.cachedAt) <
            const Duration(seconds: 12);
    if (fresh) return;
    await refresh(directories: selectedDirectories);
  }

  Future<void> refresh({String? directory, List<String>? directories}) {
    final selectedDirectories = _scanRoots(directory, directories);
    final running = _scanFuture;
    if (running != null && listEquals(_scanDirectories, selectedDirectories)) {
      return running;
    }

    final generation = ++_scanGeneration;
    _scanDirectories = selectedDirectories;
    final future = _scanDirectoryContents(selectedDirectories, generation);
    _scanFuture = future;
    return future;
  }

  Future<void> _scanDirectoryContents(
    List<String> directories,
    int generation,
  ) async {
    final files = <String, LocalSongFileSnapshot>{};
    final errors = <String>[];
    try {
      final roots = [...directories]
        ..sort((a, b) => a.length.compareTo(b.length));
      final completedRoots = <String>[];
      for (final directory in roots) {
        if (completedRoots.any((root) => p.isWithin(root, directory))) continue;
        try {
          final dir = Directory(directory);
          if (!await dir.exists()) continue;
          await for (final item in dir.list(
            recursive: true,
            followLinks: false,
          )) {
            if (generation != _scanGeneration) return;
            if (item is! File) continue;
            final fileName = p.basename(item.path);
            final extension = p.extension(fileName).replaceFirst('.', '');
            if (!_audioExtensions.contains(extension.toLowerCase())) continue;
            final key = p.canonicalize(item.path);
            if (files.containsKey(key)) continue;
            final stat = await item.stat();
            files[key] = LocalSongFileSnapshot(
              path: item.path,
              fileName: fileName,
              extension: extension,
              createdAt: stat.changed,
              modifiedAt: stat.modified,
              sizeBytes: stat.size,
            );
          }
          completedRoots.add(directory);
        } catch (error) {
          errors.add('$directory：$error');
        }
      }
      if (generation != _scanGeneration) return;
      await save(
        directories: directories,
        files: files.values.toList(),
        error: errors.isEmpty ? null : '无法读取本地音乐文件夹：${errors.join('\n')}',
      );
    } finally {
      if (generation == _scanGeneration) _scanFuture = null;
    }
  }

  Future<void> save({
    String? directory,
    List<String>? directories,
    required List<LocalSongFileSnapshot> files,
    String? error,
  }) async {
    final snapshot = LocalSongScanSnapshot(
      directories: _scanRoots(directory, directories),
      cachedAt: DateTime.now(),
      files: List.unmodifiable(files),
      error: error,
    );
    _snapshot = snapshot;
    notifyListeners();
    try {
      final file = await _cacheFile();
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(snapshot.toJson()), flush: true);
    } catch (_) {
      // The in-memory snapshot remains useful even when disk persistence fails.
    }
  }

  Future<File> _cacheFile() async {
    final support = await getApplicationSupportDirectory();
    return File(p.join(support.path, _fileName));
  }
}

List<String> _normalizeDirectories(List<String> values) {
  final directories = <String>[];
  for (final value in values) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) continue;
    final pathContext = trimmed.startsWith('/') ? p.posix : p.context;
    final directory = pathContext.normalize(trimmed);
    if (directories.any(
      (existing) => pathContext.equals(existing, directory),
    )) {
      continue;
    }
    directories.add(directory);
  }
  return List.unmodifiable(directories);
}

List<String> _scanRoots(String? directory, List<String>? directories) {
  final normalized = _normalizeDirectories(directories ?? [?directory]);
  if (normalized.isEmpty) {
    throw ArgumentError('至少需要一个本地音乐文件夹');
  }
  return normalized;
}

final localSongScanCacheProvider = ChangeNotifierProvider<LocalSongScanCache>(
  (_) => LocalSongScanCache(),
);
