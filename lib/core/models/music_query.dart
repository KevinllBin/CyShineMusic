import 'music_info.dart';

List<MusicInfo> filterMusicByQuery(List<MusicInfo> tracks, String query) {
  final terms = query
      .trim()
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((s) => s.isNotEmpty)
      .toList();
  if (terms.isEmpty) return tracks;
  return tracks.where((song) {
    final text = '${song.name}\n${song.singer}\n${song.meta.albumName}'
        .toLowerCase();
    return terms.every(text.contains);
  }).toList();
}
