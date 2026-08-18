import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_audio_tagger/flutter_audio_tagger.dart';
import 'package:flutter_audio_tagger/tag.dart';

import 'app_logger.dart';
import 'embedded_audio_tags.dart';
import 'tagger_models.dart';

TaggerPlatformBackend createTaggerPlatformBackend() => TaggerPlatformBackend();

class TaggerPlatformBackend {
  TaggerPlatformBackend();

  final FlutterAudioTagger _tagger = FlutterAudioTagger();
  static const MethodChannel _nativeTagger = MethodChannel(
    'cy_shine_music/native_tagger',
  );

  Future<EmbeddedAudioTags?> read(
    String path, {
    required bool includeLyrics,
    required bool includeArtwork,
  }) async {
    if (Platform.isAndroid) {
      try {
        final result = await _nativeTagger
            .invokeMapMethod<String, Object?>('read', <String, Object?>{
              'path': path,
              'includeLyrics': includeLyrics,
              'includeArtwork': includeArtwork,
            });
        // A non-null map is a successful native read even when the requested
        // projection is empty. Falling back would re-read excluded fields.
        if (result != null) return _tagsFromMap(result);
      } on MissingPluginException {
        await AppLogger.write(
          'tagger',
          'android native metadata reader missing, falling back to plugin',
        );
      } catch (e) {
        await AppLogger.write(
          'tagger',
          'android native metadata read FAIL: $e',
        );
      }
    }

    try {
      final tags = await _tagger.getAllTags(path);
      if (tags == null) return null;
      final embedded = EmbeddedAudioTags(
        title: _emptyToNull(tags.title),
        artist: _emptyToNull(tags.artist),
        album: _emptyToNull(tags.album),
        lyrics: includeLyrics ? _emptyToNull(tags.lyrics) : null,
        artworkBytes: includeArtwork ? tags.artwork : null,
      );
      return embedded.isEmpty ? null : embedded;
    } catch (_) {
      return null;
    }
  }

  Future<TaggingVerifyResult?> write(
    String path,
    TaggingPayload payload, {
    required bool hasLyrics,
    required bool hasArtwork,
    required String? artworkMimeType,
  }) async {
    final beforeSize = _safeFileSize(path);
    await AppLogger.write(
      'tagger',
      'write start path=$path beforeSize=$beforeSize '
          'lyrics=${payload.lyrics?.length ?? 0} '
          'artwork=${payload.coverBytes?.length ?? 0} '
          'hasArtwork=$hasArtwork',
    );

    if (Platform.isAndroid) {
      try {
        final result = await _writeWithNativeTagger(
          path,
          payload,
          hasLyrics: hasLyrics,
          hasArtwork: hasArtwork,
          artworkMimeType: artworkMimeType,
        );
        if (result != null) {
          await AppLogger.write(
            'tagger',
            'android native metadata OK lyricsLen=${result.lyricsLength} '
                'artworkLen=${result.artworkLength}',
          );
          return result;
        }
      } on MissingPluginException {
        await AppLogger.write(
          'tagger',
          'android native metadata missing, falling back to plugin',
        );
      } catch (e, s) {
        await AppLogger.write('tagger', 'android native metadata FAIL: $e');
        await AppLogger.write('tagger', 'android native metadata stack: $s');
        throw StateError('android native tagger failed: $e');
      }
    }

    var tagsOk = false;
    var artworkOk = false;
    try {
      await _tagger.editTags(
        Tag(
          artist: payload.artist.isEmpty ? null : payload.artist,
          title: payload.title.isEmpty ? null : payload.title,
          album: payload.album.isEmpty ? null : payload.album,
          lyrics: hasLyrics ? payload.lyrics : null,
        ),
        path,
      );
      tagsOk = true;
    } catch (e, s) {
      await AppLogger.write('tagger', 'editTags FAIL: $e');
      await AppLogger.write('tagger', 'editTags stack: $s');
    }

    if (hasArtwork) {
      try {
        await _tagger.setArtWork(payload.coverBytes, path);
        artworkOk = true;
      } catch (e, s) {
        await AppLogger.write('tagger', 'setArtWork FAIL: $e');
        await AppLogger.write('tagger', 'setArtWork stack: $s');
      }
    }

    final afterSize = _safeFileSize(path);
    await AppLogger.write(
      'tagger',
      'write done tagsOk=$tagsOk artworkOk=$artworkOk '
          'afterSize=$afterSize delta=${afterSize - beforeSize}',
    );
    if (afterSize <= 0) {
      throw StateError(
        'tagger produced an empty file (size=$afterSize, was=$beforeSize)',
      );
    }
    if (!tagsOk && !artworkOk) {
      throw StateError('tagger: both tags and artwork passes failed');
    }

    try {
      final written = await _tagger.getAllTags(path);
      final result = TaggingVerifyResult(
        lyricsLength: written?.lyrics?.length ?? 0,
        artworkLength: written?.artwork?.length ?? 0,
      );
      await AppLogger.write(
        'tagger',
        'verify lyricsLen=${result.lyricsLength} '
            'artworkLen=${result.artworkLength}',
      );
      return result;
    } catch (e) {
      await AppLogger.write('tagger', 'verify skipped (read failed): $e');
      return null;
    }
  }

  Future<TaggingVerifyResult?> _writeWithNativeTagger(
    String path,
    TaggingPayload payload, {
    required bool hasLyrics,
    required bool hasArtwork,
    required String? artworkMimeType,
  }) async {
    final result = await _nativeTagger
        .invokeMapMethod<String, Object?>('write', <String, Object?>{
          'path': path,
          'title': payload.title.isEmpty ? null : payload.title,
          'artist': payload.artist.isEmpty ? null : payload.artist,
          'album': payload.album.isEmpty ? null : payload.album,
          'lyrics': hasLyrics ? payload.lyrics : null,
          'artwork': hasArtwork ? payload.coverBytes : null,
          'artworkMimeType': hasArtwork ? artworkMimeType : null,
        });
    if (result == null) return null;
    return TaggingVerifyResult(
      lyricsLength: _asInt(result['lyricsLength']),
      artworkLength: _asInt(result['artworkLength']),
    );
  }

  static EmbeddedAudioTags? _tagsFromMap(Map<String, Object?> map) {
    final tags = EmbeddedAudioTags(
      title: _emptyToNull(map['title'] as String?),
      artist: _emptyToNull(map['artist'] as String?),
      album: _emptyToNull(map['album'] as String?),
      lyrics: _emptyToNull(map['lyrics'] as String?),
      artworkBytes: map['artwork'] as Uint8List?,
    );
    return tags.isEmpty ? null : tags;
  }

  static String? _emptyToNull(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  static int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return 0;
  }

  static int _safeFileSize(String path) {
    try {
      return File(path).lengthSync();
    } catch (_) {
      return -1;
    }
  }
}
