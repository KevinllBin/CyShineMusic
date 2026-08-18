import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'embedded_audio_tags.dart';
import 'flac_metadata_writer.dart';
import 'tagger_models.dart';
import 'tagger_platform_stub.dart'
    if (dart.library.ui) 'tagger_platform_flutter.dart'
    as platform;

export 'embedded_audio_tags.dart';
export 'tagger_models.dart';

class Tagger {
  const Tagger._();

  static final platform.TaggerPlatformBackend _platform = platform
      .createTaggerPlatformBackend();

  /// Reads back the LYRICS tag written by [write], without touching audio
  /// frames. Used to show local-history lyrics without a network round trip.
  static Future<String?> readLyrics(String path) async {
    final tags = await readEmbeddedTags(path, includeArtwork: false);
    final lyrics = tags?.lyrics;
    return (lyrics != null && lyrics.isNotEmpty) ? lyrics : null;
  }

  /// Reads the small embedded tag payload needed by the local player. The
  /// FLAC path stays pure Dart so it can also be exercised by `dart test`.
  static Future<EmbeddedAudioTags?> readEmbeddedTags(
    String path, {
    bool includeLyrics = true,
    bool includeArtwork = true,
  }) async {
    if (await _isFlacStream(path)) {
      final summary = await Isolate.run(
        () => FlacMetadataWriter.readSummary(
          path,
          includeLyrics: includeLyrics,
          includeArtwork: includeArtwork,
        ),
      );
      if (summary == null) return null;
      final tags = EmbeddedAudioTags(
        title: summary.firstComment('TITLE'),
        artist: summary.firstComment('ARTIST'),
        album: summary.firstComment('ALBUM'),
        lyrics: includeLyrics ? summary.firstComment('LYRICS') : null,
        artworkBytes: includeArtwork ? summary.artworkBytes : null,
      );
      return tags.isEmpty ? null : tags;
    }

    return _platform.read(
      path,
      includeLyrics: includeLyrics,
      includeArtwork: includeArtwork,
    );
  }

  static Future<TaggingVerifyResult?> write(
    String path,
    TaggingPayload payload,
  ) async {
    final hasLyrics = payload.lyrics != null && payload.lyrics!.isNotEmpty;
    final artworkMimeType = imageMimeTypeFromBytes(payload.coverBytes);
    final hasArtwork = artworkMimeType != null;
    final isFlac = await _isFlacStream(path);

    if (isFlac) {
      try {
        final result = await FlacMetadataWriter.write(
          path,
          title: payload.title.isEmpty ? null : payload.title,
          artist: payload.artist.isEmpty ? null : payload.artist,
          album: payload.album.isEmpty ? null : payload.album,
          lyrics: hasLyrics ? payload.lyrics : null,
          pictureBytes: hasArtwork ? payload.coverBytes : null,
          pictureMimeType: artworkMimeType ?? 'image/jpeg',
        );
        if (result != null) {
          return TaggingVerifyResult(
            lyricsLength: result.lyricsLength,
            artworkLength: result.artworkLength,
          );
        }
      } catch (e) {
        throw StateError('flac native tagger failed: $e');
      }
    }

    return _platform.write(
      path,
      payload,
      hasLyrics: hasLyrics,
      hasArtwork: hasArtwork,
      artworkMimeType: artworkMimeType,
    );
  }

  static Future<bool> _isFlacStream(String path) async {
    RandomAccessFile? file;
    try {
      file = await File(path).open(mode: FileMode.read);
      final magic = await file.read(4);
      return magic.length == 4 &&
          magic[0] == 0x66 &&
          magic[1] == 0x4C &&
          magic[2] == 0x61 &&
          magic[3] == 0x43;
    } catch (_) {
      return false;
    } finally {
      await file?.close();
    }
  }
}

String? imageMimeTypeFromBytes(Uint8List? bytes) {
  if (bytes == null || bytes.isEmpty) return null;

  bool matches(int offset, List<int> signature) {
    if (offset < 0 || offset + signature.length > bytes.length) return false;
    for (var index = 0; index < signature.length; index++) {
      if (bytes[offset + index] != signature[index]) return false;
    }
    return true;
  }

  if (matches(0, const [0xFF, 0xD8, 0xFF])) return 'image/jpeg';
  if (matches(0, const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) {
    return 'image/png';
  }
  if (matches(0, const [0x47, 0x49, 0x46, 0x38, 0x37, 0x61]) ||
      matches(0, const [0x47, 0x49, 0x46, 0x38, 0x39, 0x61])) {
    return 'image/gif';
  }
  if (matches(0, const [0x52, 0x49, 0x46, 0x46]) &&
      matches(8, const [0x57, 0x45, 0x42, 0x50])) {
    return 'image/webp';
  }
  if (matches(0, const [0x42, 0x4D])) return 'image/bmp';

  // ISO BMFF images identify their major and compatible brands after `ftyp`.
  if (matches(4, const [0x66, 0x74, 0x79, 0x70])) {
    final scanEnd = bytes.length < 40 ? bytes.length : 40;
    for (var offset = 8; offset + 4 <= scanEnd; offset += 4) {
      if (matches(offset, const [0x61, 0x76, 0x69, 0x66]) ||
          matches(offset, const [0x61, 0x76, 0x69, 0x73])) {
        return 'image/avif';
      }
      if (matches(offset, const [0x68, 0x65, 0x69, 0x63]) ||
          matches(offset, const [0x68, 0x65, 0x69, 0x78]) ||
          matches(offset, const [0x68, 0x65, 0x76, 0x63]) ||
          matches(offset, const [0x68, 0x65, 0x76, 0x78]) ||
          matches(offset, const [0x6D, 0x69, 0x66, 0x31])) {
        return 'image/heic';
      }
    }
  }
  return null;
}
