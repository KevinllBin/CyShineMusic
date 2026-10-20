import 'package:flutter_test/flutter_test.dart';

import 'package:cy_shine_music/features/downloads/download_history_entry.dart';
import 'package:cy_shine_music/features/player/player_models.dart';
import 'package:cy_shine_music/features/playlists/playlist_models.dart';
import 'package:cy_shine_music/features/songs/songs_playback_location.dart';

void main() {
  const track = PlayerTrack(
    id: 'wy:song:remote',
    kind: PlayerTrackKind.remote,
    title: 'Song',
    artist: 'Artist',
    album: '',
    sourceLabel: '',
    qualityLabel: '',
  );
  const player = PlayerState(track: track);
  final a = _playlist('a');
  final b = _playlist('b');

  test(
    'duplicate songs return to the source playlist rather than the browsed one',
    () {
      expect(
        findPlayingLibrary(
          player: player,
          sourcePlaylistId: 'a',
          selectedPlaylistId: 'b',
          playlists: [b, a],
          localSongs: [_entry('download')],
        ),
        (playlistId: 'a'),
      );
    },
  );

  test('legacy queue entry identifies its original playlist', () {
    final restored = player.copyWith(
      queue: [_entry('playlist:a:music:wy:song')],
      queueIndex: 0,
    );
    expect(
      findPlayingLibrary(
        player: restored,
        sourcePlaylistId: null,
        selectedPlaylistId: 'b',
        playlists: [b, a],
        localSongs: [],
      ),
      (playlistId: 'a'),
    );
  });

  test(
    'local playback returns to local songs across another playlist view',
    () {
      expect(
        findPlayingLibrary(
          player: player,
          sourcePlaylistId: null,
          selectedPlaylistId: 'b',
          playlists: [b],
          localSongs: [_entry('download')],
        ),
        (playlistId: null),
      );
    },
  );

  test(
    'removed source and missing source track fall back to a containing playlist',
    () {
      for (final playlists in [
        [b],
        [_playlist('a', songId: 'other'), b],
      ]) {
        expect(
          findPlayingLibrary(
            player: player,
            sourcePlaylistId: 'a',
            selectedPlaylistId: null,
            playlists: playlists,
            localSongs: [],
          ),
          (playlistId: 'b'),
        );
      }
    },
  );

  test('standalone playback matches saved playlists without a queue', () {
    expect(
      findPlayingLibrary(
        player: player,
        sourcePlaylistId: null,
        selectedPlaylistId: null,
        playlists: [a],
        localSongs: [],
      ),
      (playlistId: 'a'),
    );
  });

  test(
    'unavailable tracks and empty playback do not select an unrelated playlist',
    () {
      for (final state in [player, const PlayerState()]) {
        expect(
          findPlayingLibrary(
            player: state,
            sourcePlaylistId: 'a',
            selectedPlaylistId: 'a',
            playlists: [_playlist('a', songId: 'other')],
            localSongs: [],
          ),
          isNull,
        );
      }
    },
  );
}

LocalPlaylist _playlist(String id, {String songId = 'song'}) => LocalPlaylist(
  id: id,
  name: id,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  tracks: [
    PlaylistTrack(
      musicId: songId,
      name: 'Song',
      singer: 'Artist',
      albumName: '',
      sourceCode: 'wy',
      qualityCode: 'flac',
    ),
  ],
);

DownloadHistoryEntry _entry(String id) => DownloadHistoryEntry(
  id: id,
  musicId: 'song',
  name: 'Song',
  singer: 'Artist',
  albumName: '',
  sourceCode: 'wy',
  qualityCode: 'flac',
  status: DownloadHistoryStatus.completed,
  createdAt: DateTime(2026),
);
