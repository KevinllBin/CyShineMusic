import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../core/services/embedded_audio_tags.dart';
import '../../core/services/storage_location.dart';

@immutable
class LocalSongFileSnapshot {
  const LocalSongFileSnapshot({
    required this.path,
    required this.fileName,
    required this.extension,
    required this.createdAt,
    required this.modifiedAt,
    required this.sizeBytes,
    this.directory,
    this.contentUri,
    this.aliases = const [],
    this.tags,
    this.metadataRead = false,
  });

  final String path;
  final String fileName;
  final String extension;
  final DateTime createdAt;
  final DateTime modifiedAt;
  final int sizeBytes;
  final String? directory;
  final String? contentUri;
  String get playbackPath => contentUri ?? path;
  final List<String> aliases;
  final EmbeddedAudioTags? tags;
  final bool metadataRead;

  String get key => localSongPathKey(path);
  String get fingerprint => '${modifiedAt.microsecondsSinceEpoch}:$sizeBytes';

  LocalSongFileSnapshot withMetadata(EmbeddedAudioTags? value) =>
      LocalSongFileSnapshot(
        path: path,
        fileName: fileName,
        extension: extension,
        createdAt: createdAt,
        modifiedAt: modifiedAt,
        sizeBytes: sizeBytes,
        directory: directory,
        contentUri: contentUri,
        aliases: aliases,
        tags: value == null
            ? null
            : EmbeddedAudioTags(
                title: value.title,
                artist: value.artist,
                album: value.album,
              ),
        metadataRead: true,
      );

  LocalSongFileSnapshot retainingMetadata(
    LocalSongFileSnapshot? previous, {
    bool retryEmpty = false,
  }) {
    if (previous == null ||
        fingerprint != previous.fingerprint ||
        (retryEmpty && previous.tags == null)) {
      return this;
    }
    return LocalSongFileSnapshot(
      path: path,
      fileName: fileName,
      extension: extension,
      createdAt: createdAt,
      modifiedAt: modifiedAt,
      sizeBytes: sizeBytes,
      directory: directory,
      contentUri: contentUri,
      aliases: previous.aliases,
      tags: previous.tags,
      metadataRead: previous.metadataRead,
    );
  }

  LocalSongFileSnapshot withAliases(Iterable<String> values) =>
      LocalSongFileSnapshot(
        path: path,
        fileName: fileName,
        extension: extension,
        createdAt: createdAt,
        modifiedAt: modifiedAt,
        sizeBytes: sizeBytes,
        directory: directory,
        contentUri: contentUri,
        aliases: values.toSet().toList(),
        tags: tags,
        metadataRead: metadataRead,
      );

  factory LocalSongFileSnapshot.fromJson(Map<String, dynamic> json) {
    final tags = json['tags'];
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
      directory: json['directory'] as String?,
      contentUri: json['contentUri'] as String?,
      aliases:
          (json['aliases'] as List?)?.whereType<String>().toList() ?? const [],
      metadataRead: json['metadataRead'] == true,
      tags: tags is Map
          ? EmbeddedAudioTags(
              title: tags['title'] as String?,
              artist: tags['artist'] as String?,
              album: tags['album'] as String?,
            )
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'path': path,
    'fileName': fileName,
    'extension': extension,
    'createdAt': createdAt.toIso8601String(),
    'modifiedAt': modifiedAt.toIso8601String(),
    'sizeBytes': sizeBytes,
    if (directory != null) 'directory': directory,
    if (contentUri != null) 'contentUri': contentUri,
    if (aliases.isNotEmpty) 'aliases': aliases,
    'metadataRead': metadataRead,
    if (tags != null)
      'tags': {
        'title': tags!.title,
        'artist': tags!.artist,
        'album': tags!.album,
      },
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
    this.initialized = true,
    this.pathsLinked = false,
    this.backend = 'filesystem',
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
  final bool initialized;
  final bool pathsLinked;
  final String backend;

  LocalSongScanSnapshot withFiles(
    List<LocalSongFileSnapshot> values, {
    bool? pathsLinked,
  }) => LocalSongScanSnapshot(
    directories: directories,
    cachedAt: cachedAt,
    files: List.unmodifiable(values),
    error: error,
    initialized: initialized,
    pathsLinked: pathsLinked ?? this.pathsLinked,
    backend: backend,
  );

  bool matchesDirectories(List<String> values) =>
      listEquals(directories, normalizeScanDirectories(values));

  factory LocalSongScanSnapshot.fromJson(Map<String, dynamic> json) {
    final files = <LocalSongFileSnapshot>[];
    for (final row in json['files'] as List? ?? const []) {
      if (row is! Map) continue;
      try {
        final file = LocalSongFileSnapshot.fromJson(
          Map<String, dynamic>.from(row),
        );
        if (file.path.isNotEmpty && file.fileName.isNotEmpty) files.add(file);
      } catch (_) {
        // A damaged row must not discard the rest of the library.
      }
    }
    return LocalSongScanSnapshot(
      directories: normalizeScanDirectories(
        (json['directories'] as List?)?.whereType<String>().toList() ??
            [json['directory'] as String? ?? ''],
      ),
      cachedAt:
          DateTime.tryParse(json['cachedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      files: List.unmodifiable(files),
      error: json['error'] as String?,
      initialized: json['initialized'] != false,
      pathsLinked: json['pathsLinked'] == true,
      backend: json['backend'] as String? ?? 'filesystem',
    );
  }

  Map<String, dynamic> toJson() => {
    'directory': directory,
    'directories': directories,
    'cachedAt': cachedAt.toIso8601String(),
    'files': [for (final file in files) file.toJson()],
    'initialized': initialized,
    'pathsLinked': pathsLinked,
    'backend': backend,
    if (error != null) 'error': error,
  };
}

List<String> normalizeScanDirectories(List<String> values) =>
    List.unmodifiable({
      for (final value in values)
        if (value.trim().isNotEmpty) normalizeStorageLocation(value),
    });

String localSongPathKey(String path) {
  if (isContentLocation(path)) return contentDocumentKey(path);
  final normalized = normalizeStorageLocation(path).replaceAll('\\', '/');
  return Platform.isWindows ? normalized.toLowerCase() : normalized;
}

bool isFileInScanDirectory(String path, String directory) {
  if (isContentLocation(path) || isContentLocation(directory)) return false;
  final context = path.startsWith('/') ? p.posix : p.context;
  return context.equals(path, directory) || context.isWithin(directory, path);
}
