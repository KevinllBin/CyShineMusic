import 'package:test/test.dart';

import 'package:cy_shine_music/core/models/enums.dart';
import 'package:cy_shine_music/core/sdk/internal/qs_lyric.dart';
import 'package:cy_shine_music/core/services/lyric_builder.dart';
import 'package:cy_shine_music/features/player/lyric_parser.dart';

void main() {
  test(
    'preserves millisecond precision and converts relative KRC word timings',
    () {
      final info = QsLyric.parse({
        'type': 'krc',
        'content':
            '[15,500]<0,50,0>你<50,450,0>好\n'
            '[60105,1200]<250,950,0>朋友',
      });
      expect(info.lyric, '[00:00.015]你好\n[01:00.105]朋友');
      expect(
        info.lxlyric,
        '[00:00.015]<0,50>你<50,450>好\n[01:00.105]<250,950>朋友',
      );
      final parsed = KaraokeLyricsParser.parse(info);
      expect(parsed.lines.first.startMs, 15);
      expect(parsed.lines.first.words[1].startMs, 65);
      expect(parsed.lines.first.words[1].endMs, 515);
      expect(parsed.lines.last.words.single.startMs, 60355);
      expect(parsed.lines.last.words.single.endMs, 61305);
    },
  );

  test('keeps credit lines and aligns the supplied Chinese translation', () {
    final info = QsLyric.parse({
      'content': '[0,1000]作词：测试作者\r\n[1234,1000]<0,1000,0>Hello',
      'translations': {'cn': '[00:01.234]你好'},
    });
    final parsed = KaraokeLyricsParser.parse(info);
    expect(parsed.lines.first.text, '作词：测试作者');
    expect(parsed.lines.first.words, isEmpty);
    expect(parsed.lines.last.translation, '你好');
    expect(info.rlyric, isNull);
  });

  test('line-only LRC remains usable without fabricated word timings', () {
    final info = QsLyric.parse({
      'type': 'lrc',
      'content': '[ti:测试歌曲]\n[00:01.050]第一句\n[00:02.100]第二句',
    });
    expect(info.lyric, '[00:01.050]第一句\n[00:02.100]第二句');
    expect(info.lxlyric, isNull);
    expect(KaraokeLyricsParser.parse(info).lines.first.startMs, 1050);
  });

  test(
    'empty, untimed and unsupported payloads do not become visible lyrics',
    () {
      for (final content in [
        null,
        '',
        '  ',
        '[ti:测试歌曲]',
        '没有时间信息',
        <String>[],
      ]) {
        final info = QsLyric.parse({'content': content});
        expect(info.isEmpty, isTrue);
        expect(info.lxlyric, isNull);
      }
      final info = QsLyric.parse({'content': '[0,100]<0,100,0>'});
      expect(info.isEmpty, isTrue);
    },
  );

  test(
    'normalizes two-field word tags without removing literal angle text',
    () {
      final info = QsLyric.parse({'content': '[1005,1000]<0,1000>Love <3'});
      expect(info.lyric, '[00:01.005]Love <3');
      expect(info.lxlyric, '[00:01.005]<0,1000>Love <3');
    },
  );

  test(
    'downloaded Qishui lyrics retain word timing and translation in auto mode',
    () {
      final info = QsLyric.parse({
        'content': '[1005,1000]<10,400,0>Hel<410,590,0>lo',
        'translations': {'cn': '[00:01.005]你好'},
      });
      final embedded = LyricBuilder.build(
        info,
        const LyricEmbedOptions(source: MusicSource.qs),
      );
      final parsed = KaraokeLyricsParser.parseEmbedded(embedded);
      expect(parsed.lines.single.text, 'Hello');
      expect(parsed.lines.single.words.first.startMs, 1015);
      expect(parsed.lines.single.words.last.endMs, 2005);
      expect(parsed.lines.single.translation, '你好');
    },
  );
}
