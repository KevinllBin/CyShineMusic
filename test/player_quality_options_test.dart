import 'package:flutter_test/flutter_test.dart';

import 'package:cy_shine_music/core/models/enums.dart';
import 'package:cy_shine_music/core/sdk/internal/builders.dart';
import 'package:cy_shine_music/features/player/player_models.dart';
import 'package:cy_shine_music/features/player/widgets/player_quality_sheet.dart';

void main() {
  test(
    'source-declared playback qualities survive missing catalogue sizes',
    () {
      final music = buildMusicInfo(
        name: '测试',
        singer: '测试歌手',
        source: MusicSource.qs,
        songId: '123456',
        qualitys: const [],
      );
      final track = PlayerTrack.fromMusic(
        music: music,
        quality: Quality.k128,
        url: 'https://audio.test/track',
        coverUrl: null,
        availableQualities: [Quality.k128, Quality.k320, Quality.flac],
      );
      final options = availablePlaybackQualityOptions(track);
      expect(options.map((q) => q.type), [
        Quality.flac,
        Quality.k320,
        Quality.k128,
      ]);
      expect(options.every((q) => q.size == null), isTrue);
    },
  );

  test(
    'a genuinely single-quality source does not gain fabricated choices',
    () {
      final music = buildMusicInfo(
        name: '测试',
        singer: '测试歌手',
        source: MusicSource.qs,
        songId: '123456',
        qualitys: const [],
      );
      final track = PlayerTrack.fromMusic(
        music: music,
        quality: Quality.k128,
        url: 'https://audio.test/track',
        coverUrl: null,
        availableQualities: [Quality.k128],
      );
      expect(availablePlaybackQualityOptions(track).single.type, Quality.k128);
    },
  );
}
