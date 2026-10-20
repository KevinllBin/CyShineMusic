import '../downloads/download_history_entry.dart';
import '../player/player_models.dart';
import '../playlists/playlist_models.dart';

/// Null means no library contains the track; a null playlistId means local songs.
({String? playlistId})? findPlayingLibrary({
  required PlayerState player,
  required String? sourcePlaylistId,
  required String? selectedPlaylistId,
  required List<LocalPlaylist> playlists,
  required List<DownloadHistoryEntry> localSongs,
}) {
  final playing = player.track;
  if (playing == null) return null;
  final entry =
      player.queueIndex >= 0 && player.queueIndex < player.queue.length
      ? player.queue[player.queueIndex]
      : null;
  bool samePath(String? a, String? b) =>
      a != null &&
      a.trim().isNotEmpty &&
      b != null &&
      b.trim().isNotEmpty &&
      normalizePlaylistPath(a) == normalizePlaylistPath(b);
  bool contains(LocalPlaylist playlist) => playlist.tracks.any((track) {
    if (samePath(track.localPath, playing.localPath) ||
        samePath(track.localPath, entry?.savedPath)) {
      return true;
    }
    if (track.musicId.isEmpty) return false;
    return (entry != null &&
            track.sourceCode == entry.sourceCode &&
            track.musicId == entry.musicId) ||
        playing.id == '${track.sourceCode}:${track.musicId}:remote';
  });

  // Prefer the actual playback source even when another collection also
  // contains the same song. Deleting/removing it must not block fallbacks.
  for (final playlist in playlists) {
    if (playlist.id == sourcePlaylistId && contains(playlist)) {
      return (playlistId: playlist.id);
    }
  }
  // Older sessions may already encode the origin in their queue entry ids.
  for (final playlist in playlists) {
    if (entry?.id.startsWith('playlist:${playlist.id}:') == true &&
        contains(playlist)) {
      return (playlistId: playlist.id);
    }
  }
  if (localSongs.any(
    (candidate) =>
        matchesPlayingEntry(candidate, entry, playing.localPath, playing.id),
  )) {
    return (playlistId: null);
  }
  for (final playlist in playlists) {
    if (playlist.id == selectedPlaylistId && contains(playlist)) {
      return (playlistId: playlist.id);
    }
  }
  for (final playlist in playlists) {
    if (contains(playlist)) return (playlistId: playlist.id);
  }
  return null;
}

bool matchesPlayingEntry(
  DownloadHistoryEntry entry,
  DownloadHistoryEntry? queueEntry,
  String? playerLocalPath,
  String? playerTrackId,
) {
  if (queueEntry != null) {
    if (queueEntry.id == entry.id) return true;
    final queuedPath = queueEntry.savedPath?.trim();
    final entryPath = entry.savedPath?.trim();
    if (queuedPath != null &&
        queuedPath.isNotEmpty &&
        entryPath != null &&
        entryPath.isNotEmpty &&
        normalizePlaylistPath(queuedPath) == normalizePlaylistPath(entryPath)) {
      return true;
    }
    if (queueEntry.sourceCode == entry.sourceCode &&
        queueEntry.musicId.isNotEmpty &&
        queueEntry.musicId == entry.musicId) {
      return true;
    }
  }

  if (playerTrackId == '${entry.id}:local' ||
      (entry.musicId.isNotEmpty &&
          playerTrackId == '${entry.sourceCode}:${entry.musicId}:remote')) {
    return true;
  }
  final entryPath = entry.savedPath?.trim();
  final activePath = playerLocalPath?.trim();
  return entryPath != null &&
      entryPath.isNotEmpty &&
      activePath != null &&
      activePath.isNotEmpty &&
      normalizePlaylistPath(entryPath) == normalizePlaylistPath(activePath);
}
