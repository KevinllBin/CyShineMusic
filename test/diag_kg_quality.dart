// Run explicitly: dart test test/diag_kg_quality.dart -r expanded
// Queries platform metadata only; it does not download or play audio.
// ignore_for_file: avoid_print

import 'package:test/test.dart';

import 'package:cy_shine_music/core/models/enums.dart';
import 'package:cy_shine_music/core/sdk/internal/builders.dart';
import 'package:cy_shine_music/core/sdk/kg_sdk.dart';

void main() {
  test(
    'live Wo Bu Nan Guo quality metadata and source payload',
    () async {
      final songs = await KgSdk.search('孙燕姿 我不难过', limit: 5);
      final song = songs.firstWhere(
        (song) => song.meta.hash == '3FD7E1EC51122C745C637735C8BDE716',
      );
      final byType = {
        for (final option in song.meta.qualitys) option.type: option,
      };
      for (final option in song.sortedQualities) {
        print('${option.type.code}: ${option.size}, hash=${option.hash}');
      }
      expect(byType[Quality.master]?.hash, 'DAEFA540E03EE3C70FFAFBC0BCFF252C');
      expect(byType[Quality.master]?.size, '133.72M');
      expect(byType[Quality.k320]?.size, '12.23M');
      final payload = toOldMusicInfoJson(song, quality: Quality.master);
      expect((payload['_types'] as Map)['master'], {
        'size': '133.72M',
        'hash': 'DAEFA540E03EE3C70FFAFBC0BCFF252C',
      });
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
