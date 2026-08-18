import 'embedded_audio_tags.dart';
import 'tagger_models.dart';

TaggerPlatformBackend createTaggerPlatformBackend() =>
    const TaggerPlatformBackend();

class TaggerPlatformBackend {
  const TaggerPlatformBackend();

  Future<EmbeddedAudioTags?> read(
    String path, {
    required bool includeLyrics,
    required bool includeArtwork,
  }) async => null;

  Future<TaggingVerifyResult?> write(
    String path,
    TaggingPayload payload, {
    required bool hasLyrics,
    required bool hasArtwork,
    required String? artworkMimeType,
  }) async => null;
}
