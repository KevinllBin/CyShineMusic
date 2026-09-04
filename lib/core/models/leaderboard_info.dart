import 'enums.dart';
import 'music_info.dart';

/// Lightweight, stable metadata for one platform leaderboard.
///
/// [id] is globally unique inside the app (`source__boardId`), while
/// [boardId] is the native identifier expected by the platform endpoint.
class LeaderboardSummary {
  const LeaderboardSummary({
    required this.id,
    required this.boardId,
    required this.name,
    required this.source,
    this.coverUrl,
    this.updateFrequency,
    this.previewTracks = const <MusicInfo>[],
  });

  final String id;
  final String boardId;
  final String name;
  final MusicSource source;
  final String? coverUrl;
  final String? updateFrequency;
  final List<MusicInfo> previewTracks;

  String get key => '${source.code}:$boardId';

  LeaderboardSummary copyWith({
    String? coverUrl,
    String? updateFrequency,
    List<MusicInfo>? previewTracks,
  }) {
    return LeaderboardSummary(
      id: id,
      boardId: boardId,
      name: name,
      source: source,
      coverUrl: coverUrl ?? this.coverUrl,
      updateFrequency: updateFrequency ?? this.updateFrequency,
      previewTracks: previewTracks ?? this.previewTracks,
    );
  }
}
