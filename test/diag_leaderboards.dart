// Standalone diagnostic: loads the first live leaderboard from each platform.
//
//   dart test test/diag_leaderboards.dart -r expanded

// ignore_for_file: avoid_print

import 'package:test/test.dart';

import 'package:cy_shine_music/core/models/enums.dart';
import 'package:cy_shine_music/core/sdk/leaderboard_catalog.dart';
import 'package:cy_shine_music/core/sdk/leaderboard_sdk.dart';

void main() {
  for (final source in const [
    MusicSource.kw,
    MusicSource.kg,
    MusicSource.tx,
    MusicSource.wy,
    MusicSource.mg,
  ]) {
    test(
      '${source.code} live leaderboard detail',
      () async {
        final board = leaderboardCatalogFor(source).first;
        final detail = await LeaderboardSdk.get(
          source: source,
          boardId: board.boardId,
          maxTracks: 3,
        );
        print(
          '[${source.code}] ${detail.name} '
          'tracks=${detail.tracks.length}/${detail.totalTracks} '
          'cover=${detail.coverUrl}',
        );
        for (final track in detail.tracks) {
          print(
            '  ${track.name} - ${track.singer} '
            '[${track.meta.qualitys.map((quality) => quality.type.code).join(', ')}]',
          );
        }
        expect(detail.tracks, isNotEmpty);
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }
}
