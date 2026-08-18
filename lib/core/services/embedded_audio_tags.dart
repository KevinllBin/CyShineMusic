import 'dart:typed_data';

/// The small, platform-neutral metadata projection used by the player.
class EmbeddedAudioTags {
  const EmbeddedAudioTags({
    this.title,
    this.artist,
    this.album,
    this.lyrics,
    this.artworkBytes,
  });

  final String? title;
  final String? artist;
  final String? album;
  final String? lyrics;
  final Uint8List? artworkBytes;

  bool get hasLyrics => lyrics != null && lyrics!.trim().isNotEmpty;
  bool get hasArtwork => artworkBytes != null && artworkBytes!.isNotEmpty;
  bool get isEmpty =>
      !_hasText(title) &&
      !_hasText(artist) &&
      !_hasText(album) &&
      !hasLyrics &&
      !hasArtwork;

  static bool _hasText(String? value) =>
      value != null && value.trim().isNotEmpty;
}
