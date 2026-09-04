import '../models/enums.dart';
import '../models/leaderboard_info.dart';
import 'internal/leaderboard_catalog_kg.dart';
import 'internal/leaderboard_catalog_kw.dart';
import 'internal/leaderboard_catalog_mg.dart';
import 'internal/leaderboard_catalog_tx.dart';
import 'internal/leaderboard_catalog_wy.dart';

/// Platform leaderboard directories are deliberately static. The dynamic
/// directory endpoints change shape frequently; the detail endpoints and IDs
/// are considerably more stable.
List<LeaderboardSummary> leaderboardCatalogFor(MusicSource source) {
  return switch (source) {
    MusicSource.kw => kwLeaderboards,
    MusicSource.kg => kgLeaderboards,
    MusicSource.tx => txLeaderboards,
    MusicSource.wy => wyLeaderboards,
    MusicSource.mg => mgLeaderboards,
    MusicSource.all => const <LeaderboardSummary>[],
  };
}
