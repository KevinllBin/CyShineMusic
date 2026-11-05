import 'lyric_parser.dart';
import 'player_models.dart';

/// MusicWidgetMix's private protocol, shared by metadata and custom actions.
class VivoMusicMetadata {
  const VivoMusicMetadata._();

  // Transport, song information, artwork, lyrics, seeking, mode and current queue.
  // Favorites and the local-library browser are not advertised.
  static const supportEvents = 0x19f;
  static const supportEventsKey = 'vivomusicmix.media.metadata.support_event';
  static const loopModeKey = 'vivomusicmix.media.metadata.LOOP_MODE';
  static const playModeAction = 'vivomusicmix.media.action.PLAY_MODE';
  static const lyricKey = 'vivomusicmix.extra.key.lyric';
  static const currentListId = 'vivomusicmix_current_list';
  static const pageKey = 'vivomusicmix_key_media_page';
  static const hasMoreKey = 'vivomusicmix_key_has_more';
  // Preserve song labels when the Bluetooth option uses lyrics as the title.
  static const songTitleKey = 'cyshine.media.title';
  static const songArtistKey = 'cyshine.media.artist';

  static int loopModeFor(PlayerPlaybackMode mode) => switch (mode) {
    PlayerPlaybackMode.sequence => 1,
    PlayerPlaybackMode.repeatOne => 2,
    PlayerPlaybackMode.shuffle => 3,
  };

  static PlayerPlaybackMode? playbackModeFor(int mode) => switch (mode) {
    1 => PlayerPlaybackMode.sequence,
    2 => PlayerPlaybackMode.repeatOne,
    3 => PlayerPlaybackMode.shuffle,
    _ => null,
  };
}

/// Reuses the parsed timeline for online and embedded lyrics. Vivo consumes
/// whole-song LRC and follows MediaSession playback position itself.
class VivoLyricEncoder {
  KaraokeLyrics? _document;
  String _lrc = '';

  String encode(KaraokeLyrics lyrics) {
    if (identical(_document, lyrics)) return _lrc;
    _document = lyrics;
    final lines = <String>[];
    for (final line in lyrics.lines) {
      if (line.startMs < 0) continue;
      final text = line.text.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
      if (text.isEmpty) continue;
      final centiseconds = line.startMs ~/ 10;
      final minutes = (centiseconds ~/ 6000).toString().padLeft(2, '0');
      final seconds = (centiseconds ~/ 100 % 60).toString().padLeft(2, '0');
      final fraction = (centiseconds % 100).toString().padLeft(2, '0');
      lines.add('[$minutes:$seconds.$fraction]$text');
    }
    return _lrc = lines.join('\n');
  }
}
