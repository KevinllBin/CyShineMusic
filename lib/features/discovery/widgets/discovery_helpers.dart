import '../../../core/models/playlist_summary.dart';

String discoveryPlaylistDetailPath(PlaylistSummary summary) =>
    '/discover/playlists/${summary.source.code}/${summary.id}';

String discoveryFriendlyError(Object error) {
  final text = error.toString().replaceFirst('Exception: ', '').trim();
  return text.isEmpty ? '加载失败，请稍后重试' : text;
}
