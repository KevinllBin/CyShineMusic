import 'dart:typed_data';

class TaggingPayload {
  const TaggingPayload({
    required this.title,
    required this.artist,
    required this.album,
    this.coverBytes,
    this.lyrics,
  });

  final String title;
  final String artist;
  final String album;
  final Uint8List? coverBytes;
  final String? lyrics;
}

class TaggingVerifyResult {
  const TaggingVerifyResult({
    required this.lyricsLength,
    required this.artworkLength,
  });

  final int lyricsLength;
  final int artworkLength;
}
