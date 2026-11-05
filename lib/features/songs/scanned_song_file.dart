import '../../core/services/tagger.dart';
import 'local_song_scan_cache.dart';

String _baseNameOf(String fileName) {
  final dot = fileName.lastIndexOf('.');
  return dot > 0 ? fileName.substring(0, dot) : fileName;
}

class ScannedSongFile {
  const ScannedSongFile({
    required this.path,
    required this.fileName,
    required this.extension,
    required this.createdAt,
    required this.modifiedAt,
    required this.sizeBytes,
    this.tags,
    this.metadataRead = false,
    String? identityPath,
  }) : _identityPath = identityPath;

  factory ScannedSongFile.fromSnapshot(LocalSongFileSnapshot snapshot) {
    return ScannedSongFile(
      path: snapshot.playbackPath,
      identityPath: snapshot.path,
      fileName: snapshot.fileName,
      extension: snapshot.extension,
      createdAt: snapshot.createdAt,
      modifiedAt: snapshot.modifiedAt,
      sizeBytes: snapshot.sizeBytes,
      tags: snapshot.tags,
      metadataRead: snapshot.metadataRead,
    );
  }

  final String path;
  final String? _identityPath;
  String get identityPath => _identityPath ?? path;
  final String fileName;
  final String extension;
  final DateTime createdAt;
  final DateTime modifiedAt;
  final int sizeBytes;
  final EmbeddedAudioTags? tags;
  final bool metadataRead;
  String get fingerprint => '${modifiedAt.microsecondsSinceEpoch}:$sizeBytes';

  LocalSongFileSnapshot toSnapshot() => LocalSongFileSnapshot(
    path: identityPath,
    contentUri: path == identityPath ? null : path,
    fileName: fileName,
    extension: extension,
    createdAt: createdAt,
    modifiedAt: modifiedAt,
    sizeBytes: sizeBytes,
    tags: tags,
    metadataRead: metadataRead,
  );

  String get baseName => _baseNameOf(fileName);

  String get title {
    final sep = baseName.indexOf(' - ');
    final value = sep > 0
        ? baseName.substring(sep + 3).trim()
        : baseName.trim();
    return value.isEmpty ? fileName : value;
  }

  String get artist {
    final sep = baseName.indexOf(' - ');
    if (sep <= 0) return '未知歌手';
    final value = baseName.substring(0, sep).trim();
    return value.isEmpty ? '未知歌手' : value;
  }
}
