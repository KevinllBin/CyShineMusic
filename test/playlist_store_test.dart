import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cy_shine_music/core/api/music_api.dart';
import 'package:cy_shine_music/core/models/enums.dart';
import 'package:cy_shine_music/core/models/music_info.dart';
import 'package:cy_shine_music/core/models/playlist_info.dart';
import 'package:cy_shine_music/core/storage/settings_store.dart';
import 'package:cy_shine_music/features/downloads/download_history_store.dart';
import 'package:cy_shine_music/features/playlists/lx_playlist_import.dart';
import 'package:cy_shine_music/features/playlists/online_playlist_updater.dart';
import 'package:cy_shine_music/features/playlists/playlist_models.dart';
import 'package:cy_shine_music/features/playlists/playlist_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LocalPlaylistNotifier', () {
    late SharedPreferences prefs;
    late ProviderContainer container;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      container = _containerWith(prefs);
    });

    tearDown(() {
      container.dispose();
    });

    test('creates, renames, and rejects duplicate names', () async {
      final notifier = container.read(localPlaylistsProvider.notifier);
      final created = await notifier.create('  通勤  ');

      expect(created.name, '通勤');
      expect(container.read(localPlaylistsProvider), [created]);
      expect(await notifier.rename(created.id, '夜间'), isTrue);
      expect(container.read(localPlaylistsProvider).single.name, '夜间');

      await notifier.create('通勤');
      expect(
        notifier.rename(created.id, ' 通勤 '),
        throwsA(isA<PlaylistStoreException>()),
      );
      expect(notifier.create('夜间'), throwsA(isA<PlaylistStoreException>()));
      expect(notifier.create('   '), throwsA(isA<PlaylistStoreException>()));
    });

    test('adds local entries in bulk, deduplicates, and restores', () async {
      final notifier = container.read(localPlaylistsProvider.notifier);
      final playlist = await notifier.create('本地收藏');
      final first = _historyEntry(
        id: 'history-1',
        musicId: 'song-1',
        path: r'D:\Music\one.flac',
        name: '第一首',
      );
      final sameMusicNewSnapshot = _historyEntry(
        id: 'history-2',
        musicId: 'song-1',
        path: r'D:\Music\renamed.flac',
        name: '第一首（新标签）',
      );
      final second = _historyEntry(
        id: 'history-3',
        musicId: 'song-2',
        path: r'D:\Music\two.flac',
        name: '第二首',
      );

      expect(
        await notifier.addEntries(playlist.id, [
          first,
          sameMusicNewSnapshot,
          second,
          second,
        ]),
        2,
      );
      final stored = container.read(localPlaylistsProvider).single;
      expect(stored.tracks, hasLength(2));
      expect(stored.tracks.first.name, '第一首（新标签）');
      expect(stored.tracks.first.localPath, r'D:\Music\renamed.flac');

      container.dispose();
      container = _containerWith(prefs);
      final restored = container.read(localPlaylistsProvider).single;
      expect(restored.id, playlist.id);
      expect(restored.name, '本地收藏');
      expect(restored.tracks, hasLength(2));
      expect(restored.tracks.first.musicId, 'song-1');
      expect(restored.tracks.last.musicId, 'song-2');
    });

    test(
      'imports an online playlist and merges the same source and id',
      () async {
        final notifier = container.read(localPlaylistsProvider.notifier);
        final firstImport = await notifier.importOnline(
          PlaylistInfo(
            id: '3778678',
            name: '热歌榜',
            source: MusicSource.wy,
            coverUrl: 'https://example.com/old.jpg',
            creator: '网易云音乐',
            tracks: [_music('1', '旧歌名'), _music('2', '第二首')],
          ),
        );
        final secondImport = await notifier.importOnline(
          PlaylistInfo(
            id: '3778678',
            name: '热歌榜（线上改名）',
            source: MusicSource.wy,
            coverUrl: 'https://example.com/new.jpg',
            description: '更新后的简介',
            tracks: [_music('1', '更新后的歌名'), _music('3', '第三首')],
          ),
        );

        final playlists = container.read(localPlaylistsProvider);
        expect(playlists, hasLength(1));
        expect(secondImport.id, firstImport.id);
        expect(playlists.single.name, '热歌榜');
        expect(playlists.single.coverUrl, 'https://example.com/new.jpg');
        expect(playlists.single.description, '更新后的简介');
        expect(playlists.single.tracks, hasLength(3));
        expect(
          playlists.single.tracks
              .firstWhere((track) => track.musicId == '1')
              .name,
          '更新后的歌名',
        );
      },
    );

    test('updates an online playlist from its saved origin', () async {
      final notifier = container.read(localPlaylistsProvider.notifier);
      final imported = await notifier.importOnline(
        PlaylistInfo(
          id: '3778678',
          name: '热歌榜',
          source: MusicSource.wy,
          tracks: [
            _music('1', '旧歌名'),
            _music('removed', '线上已移除'),
            _music('3', '移到前面的歌曲'),
          ],
        ),
      );
      await notifier.rename(imported.id, '我的榜单');
      await notifier.attachDownload(
        music: _music('1', '旧歌名'),
        quality: Quality.flac,
        localPath: r'D:\Music\song-1.flac',
      );
      final api = _RecordingPlaylistMusicApi(
        PlaylistInfo(
          id: '3778678',
          name: '线上新名称',
          source: MusicSource.wy,
          tracks: [
            _music('3', '移到前面的歌曲'),
            _music('1', '更新后的歌名'),
            _music('2', '新增歌曲'),
          ],
        ),
      );

      final result = await OnlinePlaylistUpdater(
        api,
      ).update(playlist: notifier.byId(imported.id)!, store: notifier);

      expect(api.inputs, ['3778678']);
      expect(api.sources, [MusicSource.wy]);
      expect(api.maxTracks, [isNull]);
      expect(result.addedTrackCount, 1);
      expect(result.removedTrackCount, 1);
      expect(result.playlist.name, '我的榜单');
      expect(result.playlist.tracks.map((track) => track.musicId), [
        '3',
        '1',
        '2',
      ]);
      expect(result.playlist.tracks[1].name, '更新后的歌名');
      expect(result.playlist.tracks[1].localPath, r'D:\Music\song-1.flac');
      expect(onlinePlaylistUpdateMessage(result), '歌单已更新，新增 1 首，移除 1 首，共 3 首');
    });

    test('rejects playlists without a valid online origin', () async {
      final notifier = container.read(localPlaylistsProvider.notifier);
      final local = await notifier.create('本地歌单');
      final api = _RecordingPlaylistMusicApi(
        const PlaylistInfo(
          id: 'unused',
          name: '不会请求',
          source: MusicSource.wy,
          tracks: [],
        ),
      );

      await expectLater(
        OnlinePlaylistUpdater(api).update(playlist: local, store: notifier),
        throwsA(
          isA<PlaylistStoreException>().having(
            (error) => error.message,
            'message',
            '只有在线歌单可以更新',
          ),
        ),
      );
      expect(api.inputs, isEmpty);
    });

    test(
      'imports multiple LX playlists with unique names and dedupes',
      () async {
        final notifier = container.read(localPlaylistsProvider.notifier);
        await notifier.create('我的收藏');

        final imported = await notifier.importLxPlaylists([
          LxPlaylistData(
            sourceId: 'love',
            name: '我的收藏',
            tracks: [_music('1', '旧歌名'), _music('1', '更新后的歌名')],
          ),
          const LxPlaylistData(sourceId: 'empty', name: '我的收藏', tracks: []),
        ]);

        expect(imported.map((playlist) => playlist.name), [
          '我的收藏 (2)',
          '我的收藏 (3)',
        ]);
        expect(imported.first.id, startsWith('lx-'));
        expect(imported.first.tracks, hasLength(1));
        expect(imported.first.tracks.single.name, '更新后的歌名');
        expect(imported.last.tracks, isEmpty);

        container.dispose();
        container = _containerWith(prefs);
        expect(
          container
              .read(localPlaylistsProvider)
              .map((playlist) => playlist.name),
          ['我的收藏', '我的收藏 (2)', '我的收藏 (3)'],
        );
      },
    );

    test(
      'persists a resolved cover in both playlist track snapshots',
      () async {
        final music = MusicInfo.fromJson({
          'id': 'kg-cover-1',
          'name': '缺少封面的歌曲',
          'singer': '歌手',
          'source': MusicSource.kg.code,
          'interval': '03:30',
          'meta': {
            'songId': 'kg-cover-1',
            'albumName': '专辑',
            'hash': 'hash-1',
            'qualitys': [
              {'type': Quality.k320.code, 'size': '1024'},
            ],
          },
        });
        final notifier = container.read(localPlaylistsProvider.notifier);
        final imported = await notifier.importLxPlaylists([
          LxPlaylistData(sourceId: 'love', name: '待补图歌单', tracks: [music]),
        ]);
        final track = imported.single.tracks.single;

        expect(
          await notifier.updateTrackCover(
            playlistId: imported.single.id,
            trackId: track.identityKey,
            picUrl: 'https://img.test/kg-cover-1.jpg',
          ),
          isTrue,
        );

        final updated = notifier.byId(imported.single.id)!.tracks.single;
        expect(updated.picUrl, 'https://img.test/kg-cover-1.jpg');
        expect(
          (updated.musicJson!['meta'] as Map)['picUrl'],
          'https://img.test/kg-cover-1.jpg',
        );
        expect((updated.musicJson!['meta'] as Map)['hash'], 'hash-1');
        expect(music.meta.picUrl, isNull);

        container.dispose();
        container = _containerWith(prefs);
        final restored = container
            .read(localPlaylistsProvider)
            .single
            .tracks
            .single;
        expect(restored.picUrl, 'https://img.test/kg-cover-1.jpg');
        expect(
          restored.musicInfo?.meta.picUrl,
          'https://img.test/kg-cover-1.jpg',
        );
      },
    );

    test('online re-import preserves an attached local path', () async {
      final notifier = container.read(localPlaylistsProvider.notifier);
      await notifier.importOnline(
        PlaylistInfo(
          id: '3778678',
          name: '热歌榜',
          source: MusicSource.wy,
          tracks: [_music('1', '旧歌名')],
        ),
      );

      expect(
        await notifier.attachDownload(
          music: _music('1', '下载时歌名'),
          quality: Quality.flac,
          localPath: r'D:\Music\one.flac',
        ),
        1,
      );
      await notifier.importOnline(
        PlaylistInfo(
          id: '3778678',
          name: '热歌榜',
          source: MusicSource.wy,
          tracks: [_music('1', '线上更新歌名')],
        ),
      );

      final track = container.read(localPlaylistsProvider).single.tracks.single;
      expect(track.name, '线上更新歌名');
      expect(track.localPath, r'D:\Music\one.flac');
      expect(track.qualityCode, Quality.k320.code);
    });

    test('attaches a completed download to every matching playlist', () async {
      final notifier = container.read(localPlaylistsProvider.notifier);
      final imported = await notifier.importOnline(
        PlaylistInfo(
          id: '3778678',
          name: '在线歌单',
          source: MusicSource.wy,
          tracks: [_music('1', '在线歌名'), _music('2', '其他歌曲')],
        ),
      );
      final local = await notifier.create('本地歌单');
      await notifier.addEntry(
        local.id,
        _historyEntry(
          id: 'local-copy',
          musicId: '1',
          path: r'D:\Music\old.flac',
          name: '旧的本地歌名',
          source: MusicSource.wy,
        ),
      );
      final unrelated = await notifier.create('无关歌单');
      await notifier.addEntry(
        unrelated.id,
        _historyEntry(
          id: 'unrelated',
          musicId: '1',
          path: r'D:\Music\qq.flac',
          name: 'QQ 同 ID 歌曲',
          source: MusicSource.tx,
        ),
      );

      expect(
        await notifier.attachDownload(
          music: _music('1', '下载后的歌名'),
          quality: Quality.flac,
          localPath: r'D:\Music\new.flac',
        ),
        2,
      );
      expect(
        notifier.byId(imported.id)!.tracks.first.localPath,
        r'D:\Music\new.flac',
      );
      expect(
        notifier.byId(local.id)!.tracks.single.localPath,
        r'D:\Music\new.flac',
      );
      expect(
        notifier.byId(unrelated.id)!.tracks.single.localPath,
        r'D:\Music\qq.flac',
      );

      container.dispose();
      container = _containerWith(prefs);
      expect(
        container
            .read(localPlaylistsProvider)
            .firstWhere((playlist) => playlist.id == imported.id)
            .tracks
            .first
            .localPath,
        r'D:\Music\new.flac',
      );
    });

    test(
      'deleting a file keeps online tracks but removes local-only tracks',
      () async {
        final notifier = container.read(localPlaylistsProvider.notifier);
        final imported = await notifier.importOnline(
          PlaylistInfo(
            id: '3778678',
            name: '在线歌单',
            source: MusicSource.wy,
            tracks: [_music('1', '在线歌曲')],
          ),
        );
        await notifier.attachDownload(
          music: _music('1', '在线歌曲'),
          quality: Quality.flac,
          localPath: r'D:\Music\shared.flac',
        );
        final local = await notifier.create('纯本地歌单');
        await notifier.addEntry(
          local.id,
          _historyEntry(
            id: 'local-only',
            musicId: 'local-only',
            path: r'D:\Music\shared.flac',
            name: '纯本地歌曲',
          ),
        );

        expect(
          await notifier.removeLocalPathFromAll(r'D:\Music\shared.flac'),
          2,
        );
        final onlineTrack = notifier.byId(imported.id)!.tracks.single;
        expect(onlineTrack.localPath, isNull);
        expect(onlineTrack.musicInfo?.id, '1');
        expect(notifier.byId(local.id)!.tracks, isEmpty);
      },
    );

    test('skips corrupt playlist rows and corrupt tracks', () async {
      final valid = LocalPlaylist(
        id: 'valid',
        name: '有效歌单',
        tracks: [PlaylistTrack.fromMusicInfo(_music('1', '有效歌曲'))],
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 2),
      ).toJson();
      final partlyValid = LocalPlaylist(
        id: 'partial',
        name: '部分有效',
        tracks: const [],
        createdAt: DateTime.utc(2026, 2, 1),
        updatedAt: DateTime.utc(2026, 2, 2),
      ).toJson();
      partlyValid['tracks'] = [
        null,
        'not-a-map',
        {'name': ''},
        PlaylistTrack.fromMusicInfo(_music('2', '保留下来')).toJson(),
      ];
      SharedPreferences.setMockInitialValues({
        localPlaylistsStorageKey: <String>[
          jsonEncode(valid),
          '{broken-json',
          jsonEncode({'name': '缺少 ID'}),
          jsonEncode(partlyValid),
        ],
      });
      prefs = await SharedPreferences.getInstance();
      container.dispose();
      container = _containerWith(prefs);

      final restored = container.read(localPlaylistsProvider);
      expect(restored.map((playlist) => playlist.id), ['valid', 'partial']);
      expect(restored.last.tracks, hasLength(1));
      expect(restored.last.tracks.single.name, '保留下来');
    });

    test('removes only requested tracks and preserves other data', () async {
      final notifier = container.read(localPlaylistsProvider.notifier);
      final first = await notifier.create('第一张歌单');
      final second = await notifier.create('第二张歌单');
      final one = _historyEntry(
        id: 'one',
        musicId: 'one',
        path: r'D:\Music\one.flac',
        name: 'One',
      );
      final two = _historyEntry(
        id: 'two',
        musicId: 'two',
        path: r'D:\Music\two.flac',
        name: 'Two',
      );
      await notifier.addEntries(first.id, [one, two]);
      await notifier.addEntry(second.id, one);
      final firstBefore = notifier.byId(first.id)!;
      final trackToRemove = firstBefore.tracks.first.id;

      expect(await notifier.removeTracks(first.id, [trackToRemove]), 1);
      expect(notifier.byId(first.id)!.tracks.single.musicId, 'two');
      expect(notifier.byId(first.id)!.name, '第一张歌单');
      expect(notifier.byId(second.id)!.tracks.single.musicId, 'one');
      expect(notifier.byId(second.id)!.name, '第二张歌单');

      container.dispose();
      container = _containerWith(prefs);
      expect(container.read(localPlaylistsProvider), hasLength(2));
      expect(
        container
            .read(localPlaylistsProvider)
            .firstWhere((playlist) => playlist.id == second.id)
            .tracks,
        hasLength(1),
      );
    });
  });

  group('PlaylistTrack queue entry', () {
    test('keeps an online music snapshot playable without a local file', () {
      final track = PlaylistTrack.fromMusicInfo(_music('remote-1', '在线歌曲'));

      final entry = track.toQueueEntry(playlistId: 'playlist-1');

      expect(entry, isNotNull);
      expect(entry!.savedPath, isNull);
      expect(entry.musicInfo?.id, 'remote-1');
      expect(entry.qualityCode, Quality.k320.code);
    });
  });
}

ProviderContainer _containerWith(SharedPreferences prefs) {
  return ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
}

DownloadHistoryEntry _historyEntry({
  required String id,
  required String musicId,
  required String path,
  required String name,
  MusicSource source = MusicSource.tx,
}) {
  return DownloadHistoryEntry(
    id: id,
    musicId: musicId,
    name: name,
    singer: '歌手',
    albumName: '专辑',
    sourceCode: source.code,
    qualityCode: Quality.flac.code,
    status: DownloadHistoryStatus.completed,
    createdAt: DateTime.utc(2026, 1, 1),
    savedPath: path,
  );
}

MusicInfo _music(String id, String name) {
  return MusicInfo.fromJson({
    'id': id,
    'name': name,
    'singer': '在线歌手',
    'source': MusicSource.wy.code,
    'interval': '03:30',
    'meta': {
      'songId': id,
      'albumName': '在线专辑',
      'picUrl': 'https://example.com/$id.jpg',
      'qualitys': [
        {'type': Quality.k320.code, 'size': '1024'},
      ],
    },
  });
}

class _RecordingPlaylistMusicApi extends MusicApi {
  _RecordingPlaylistMusicApi(this.result);

  final PlaylistInfo result;
  final List<String> inputs = <String>[];
  final List<MusicSource> sources = <MusicSource>[];
  final List<int?> maxTracks = <int?>[];

  @override
  Future<PlaylistInfo> parsePlaylist({
    required String input,
    MusicSource source = MusicSource.all,
    int? maxTracks,
  }) async {
    inputs.add(input);
    sources.add(source);
    this.maxTracks.add(maxTracks);
    return result;
  }
}
