import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/models/enums.dart';
import '../../core/models/music_info.dart';
import '../../core/models/playlist_info.dart';
import '../../core/storage/settings_store.dart';
import '../downloads/download_history_store.dart';
import 'playlist_models.dart';

const String localPlaylistsStorageKey = 'local_playlists_v1';

class PlaylistStoreException implements Exception {
  const PlaylistStoreException(this.message);

  final String message;

  @override
  String toString() => message;
}

class LocalPlaylistNotifier extends Notifier<List<LocalPlaylist>> {
  late SharedPreferences _prefs;
  int _idSequence = 0;

  @override
  List<LocalPlaylist> build() {
    _prefs = ref.read(sharedPreferencesProvider);
    return _decodeStoredPlaylists(_prefs.get(localPlaylistsStorageKey));
  }

  LocalPlaylist? byId(String id) {
    for (final playlist in state) {
      if (playlist.id == id) return playlist;
    }
    return null;
  }

  Future<LocalPlaylist> create(String name) async {
    final normalizedName = _validatedUniqueName(name);
    final now = DateTime.now();
    final playlist = LocalPlaylist(
      id: _newId(),
      name: normalizedName,
      tracks: const [],
      createdAt: now,
      updatedAt: now,
    );
    state = List<LocalPlaylist>.unmodifiable([...state, playlist]);
    await _persist();
    return playlist;
  }

  Future<bool> rename(String id, String name) async {
    final index = state.indexWhere((playlist) => playlist.id == id);
    if (index < 0) return false;
    final normalizedName = _validatedUniqueName(name, excludingId: id);
    if (state[index].name == normalizedName) return true;

    final next = [...state];
    next[index] = state[index].copyWith(
      name: normalizedName,
      updatedAt: DateTime.now(),
    );
    state = List<LocalPlaylist>.unmodifiable(next);
    await _persist();
    return true;
  }

  Future<bool> delete(String id) async {
    final next = state.where((playlist) => playlist.id != id).toList();
    if (next.length == state.length) return false;
    state = List<LocalPlaylist>.unmodifiable(next);
    await _persist();
    return true;
  }

  Future<int> addTrack(String playlistId, DownloadHistoryEntry entry) {
    return addTracks(playlistId, [entry]);
  }

  Future<int> addEntry(String playlistId, DownloadHistoryEntry entry) {
    return addTrack(playlistId, entry);
  }

  Future<int> addTracks(
    String playlistId,
    Iterable<DownloadHistoryEntry> entries,
  ) async {
    final candidates = <PlaylistTrack>[];
    for (final entry in entries) {
      if (!entry.isCompleted || entry.savedPath?.trim().isEmpty != false) {
        continue;
      }
      candidates.add(PlaylistTrack.fromDownloadHistory(entry));
    }
    return _mergeTracks(playlistId, candidates);
  }

  Future<int> addEntries(
    String playlistId,
    Iterable<DownloadHistoryEntry> entries,
  ) {
    return addTracks(playlistId, entries);
  }

  Future<LocalPlaylist> importOnline(PlaylistInfo online) async {
    final sourceCode = online.source.code;
    final originId = online.id.trim();
    final importedTracks = online.tracks
        .map(PlaylistTrack.fromMusicInfo)
        .toList(growable: false);
    final existingIndex = state.indexWhere(
      (playlist) =>
          originId.isNotEmpty &&
          playlist.originPlaylistId == originId &&
          playlist.originSourceCode == sourceCode,
    );

    if (existingIndex >= 0) {
      final current = state[existingIndex];
      final merged = _mergeTrackLists(current.tracks, importedTracks);
      final updated = LocalPlaylist(
        id: current.id,
        name: current.name,
        tracks: merged.tracks,
        createdAt: current.createdAt,
        updatedAt: DateTime.now(),
        originPlaylistId: originId,
        originSourceCode: sourceCode,
        coverUrl: _nonEmpty(online.coverUrl) ?? current.coverUrl,
        creator: _nonEmpty(online.creator) ?? current.creator,
        description: _nonEmpty(online.description) ?? current.description,
      );
      final next = [...state]..[existingIndex] = updated;
      state = List<LocalPlaylist>.unmodifiable(next);
      await _persist();
      return updated;
    }

    final now = DateTime.now();
    final imported = LocalPlaylist(
      id: _newId(prefix: 'online'),
      name: _uniqueImportedName(online.name),
      tracks: _mergeTrackLists(const [], importedTracks).tracks,
      createdAt: now,
      updatedAt: now,
      originPlaylistId: originId.isEmpty ? null : originId,
      originSourceCode: sourceCode,
      coverUrl: _nonEmpty(online.coverUrl),
      creator: _nonEmpty(online.creator),
      description: _nonEmpty(online.description),
    );
    state = List<LocalPlaylist>.unmodifiable([...state, imported]);
    await _persist();
    return imported;
  }

  Future<bool> removeTrack(String playlistId, String trackId) async {
    return await removeTracks(playlistId, [trackId]) > 0;
  }

  Future<int> removeTracks(String playlistId, Iterable<String> trackIds) async {
    final index = state.indexWhere((playlist) => playlist.id == playlistId);
    if (index < 0) return 0;
    final keys = trackIds.toSet();
    if (keys.isEmpty) return 0;

    final current = state[index];
    final tracks = current.tracks
        .where((track) => !keys.contains(track.identityKey))
        .toList(growable: false);
    final removed = current.tracks.length - tracks.length;
    if (removed == 0) return 0;

    final next = [...state];
    next[index] = current.copyWith(
      tracks: List<PlaylistTrack>.unmodifiable(tracks),
      updatedAt: DateTime.now(),
    );
    state = List<LocalPlaylist>.unmodifiable(next);
    await _persist();
    return removed;
  }

  Future<int> removeLocalPathFromAll(String path) async {
    final normalizedPath = normalizePlaylistPath(path);
    var affected = 0;
    var changed = false;
    final now = DateTime.now();
    final next = <LocalPlaylist>[];
    for (final playlist in state) {
      var playlistChanged = false;
      final tracks = <PlaylistTrack>[];
      for (final track in playlist.tracks) {
        final localPath = track.localPath;
        final matches =
            localPath != null &&
            normalizePlaylistPath(localPath) == normalizedPath;
        if (!matches) {
          tracks.add(track);
          continue;
        }

        affected++;
        playlistChanged = true;
        final onlineFallback = track.withoutLocalPath();
        if (onlineFallback.musicInfo != null) tracks.add(onlineFallback);
      }
      if (!playlistChanged) {
        next.add(playlist);
      } else {
        changed = true;
        next.add(
          playlist.copyWith(
            tracks: List<PlaylistTrack>.unmodifiable(tracks),
            updatedAt: now,
          ),
        );
      }
    }
    if (!changed) return 0;
    state = List<LocalPlaylist>.unmodifiable(next);
    await _persist();
    return affected;
  }

  Future<int> attachDownload({
    required MusicInfo music,
    required Quality quality,
    required String localPath,
  }) async {
    final path = localPath.trim();
    if (path.isEmpty) return 0;

    final downloaded = PlaylistTrack.fromMusicInfo(
      music,
    ).copyWith(qualityCode: quality.code, localPath: path);
    final identityKey = downloaded.identityKey;
    final now = DateTime.now();
    var attached = 0;
    final next = <LocalPlaylist>[];

    for (final playlist in state) {
      var playlistChanged = false;
      final tracks = <PlaylistTrack>[];
      for (final track in playlist.tracks) {
        if (track.identityKey != identityKey) {
          tracks.add(track);
          continue;
        }

        final updated = track.mergePreferLocal(downloaded);
        tracks.add(updated);
        if (!_sameTrackSnapshot(track, updated)) {
          playlistChanged = true;
          attached++;
        }
      }

      next.add(
        playlistChanged
            ? playlist.copyWith(
                tracks: List<PlaylistTrack>.unmodifiable(tracks),
                updatedAt: now,
              )
            : playlist,
      );
    }

    if (attached == 0) return 0;
    state = List<LocalPlaylist>.unmodifiable(next);
    await _persist();
    return attached;
  }

  Future<int> _mergeTracks(
    String playlistId,
    Iterable<PlaylistTrack> candidates,
  ) async {
    final index = state.indexWhere((playlist) => playlist.id == playlistId);
    if (index < 0) return 0;
    final current = state[index];
    final merged = _mergeTrackLists(current.tracks, candidates);
    if (!merged.changed) return 0;

    final next = [...state];
    next[index] = current.copyWith(
      tracks: merged.tracks,
      updatedAt: DateTime.now(),
    );
    state = List<LocalPlaylist>.unmodifiable(next);
    await _persist();
    return merged.added;
  }

  String _validatedUniqueName(String value, {String? excludingId}) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      throw const PlaylistStoreException('歌单名称不能为空');
    }
    final folded = normalized.toLowerCase();
    final duplicate = state.any(
      (playlist) =>
          playlist.id != excludingId && playlist.name.toLowerCase() == folded,
    );
    if (duplicate) throw const PlaylistStoreException('已存在同名歌单');
    return normalized;
  }

  String _uniqueImportedName(String value) {
    final base = value.trim().isEmpty ? '导入的歌单' : value.trim();
    final used = {for (final playlist in state) playlist.name.toLowerCase()};
    if (!used.contains(base.toLowerCase())) return base;
    var suffix = 2;
    while (used.contains('$base ($suffix)'.toLowerCase())) {
      suffix++;
    }
    return '$base ($suffix)';
  }

  String _newId({String prefix = 'local'}) {
    String id;
    do {
      id = '$prefix-${DateTime.now().microsecondsSinceEpoch}-${_idSequence++}';
    } while (state.any((playlist) => playlist.id == id));
    return id;
  }

  Future<void> _persist() {
    final rows = [for (final playlist in state) jsonEncode(playlist.toJson())];
    return _prefs.setStringList(localPlaylistsStorageKey, rows);
  }
}

final localPlaylistsProvider =
    NotifierProvider<LocalPlaylistNotifier, List<LocalPlaylist>>(
      LocalPlaylistNotifier.new,
    );

final playlistStoreProvider = localPlaylistsProvider;

List<LocalPlaylist> _decodeStoredPlaylists(Object? stored) {
  final values = <Object?>[];
  if (stored is List) {
    values.addAll(stored);
  } else if (stored is String) {
    try {
      final decoded = jsonDecode(stored);
      if (decoded is List) {
        values.addAll(decoded);
      } else {
        values.add(decoded);
      }
    } catch (_) {
      return const [];
    }
  } else {
    return const [];
  }

  final playlists = <LocalPlaylist>[];
  final seenIds = <String>{};
  for (final value in values) {
    Object? decoded = value;
    if (value is String) {
      try {
        decoded = jsonDecode(value);
      } catch (_) {
        continue;
      }
    }
    final playlist = LocalPlaylist.tryFromJson(decoded);
    if (playlist != null && seenIds.add(playlist.id)) {
      playlists.add(playlist);
    }
  }
  return List<LocalPlaylist>.unmodifiable(playlists);
}

_TrackMergeResult _mergeTrackLists(
  Iterable<PlaylistTrack> current,
  Iterable<PlaylistTrack> incoming,
) {
  final tracks = current.toList();
  final indexByKey = <String, int>{
    for (var index = 0; index < tracks.length; index++)
      tracks[index].identityKey: index,
  };
  var added = 0;
  var changed = false;
  for (final track in incoming) {
    final key = track.identityKey;
    final existingIndex = indexByKey[key];
    if (existingIndex == null) {
      indexByKey[key] = tracks.length;
      tracks.add(track);
      added++;
      changed = true;
    } else {
      final merged = tracks[existingIndex].mergePreferLocal(track);
      if (!_sameTrackSnapshot(tracks[existingIndex], merged)) {
        tracks[existingIndex] = merged;
        changed = true;
      }
    }
  }
  return _TrackMergeResult(
    List<PlaylistTrack>.unmodifiable(tracks),
    added: added,
    changed: changed,
  );
}

bool _sameTrackSnapshot(PlaylistTrack left, PlaylistTrack right) {
  return jsonEncode(left.toJson()) == jsonEncode(right.toJson());
}

class _TrackMergeResult {
  const _TrackMergeResult(
    this.tracks, {
    required this.added,
    required this.changed,
  });

  final List<PlaylistTrack> tracks;
  final int added;
  final bool changed;
}

String? _nonEmpty(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}
