import 'package:test/test.dart';

import 'package:cy_shine_music/core/models/lyric_info.dart';
import 'package:cy_shine_music/features/player/lyric_parser.dart';
import 'package:cy_shine_music/features/player/vivo_music_metadata.dart';

void main() {
  test('online word lyrics become plain timed LRC for the system card', () {
    final parsed = KaraokeLyricsParser.parse(
      const LyricInfo(
        lyric: '[00:05.230]你好\n[01:05.004]World',
        lxlyric:
            '[00:05.230]<0,240>你<240,360>好\n'
            '[01:05.004]<0,500>World',
        tlyric: '[00:05.230]Hello',
      ),
    );

    expect(VivoLyricEncoder().encode(parsed), '[00:05.23]你好\n[01:05.00]World');
  });

  test('embedded enhanced lyrics keep only the main timeline', () {
    final parsed = KaraokeLyricsParser.parseEmbedded(
      '[00:05.230]<00:05.230>你<00:05.470>好<00:05.830>\n'
      '[00:05.230]Hello\n'
      '[00:05.230]ni hao',
    );

    expect(VivoLyricEncoder().encode(parsed), '[00:05.23]你好');
  });

  test('changing to an empty lyric document clears the previous song', () {
    final encoder = VivoLyricEncoder();
    final oldSong = KaraokeLyricsParser.parse(
      const LyricInfo(lyric: '[00:01.000]Previous song'),
    );
    final newSong = KaraokeLyricsParser.parse(
      const LyricInfo(lyric: '[00:02.000]Next song'),
    );

    expect(encoder.encode(oldSong), '[00:01.00]Previous song');
    expect(encoder.encode(const KaraokeLyrics([])), isEmpty);
    expect(encoder.encode(newSong), '[00:02.00]Next song');
  });
}
