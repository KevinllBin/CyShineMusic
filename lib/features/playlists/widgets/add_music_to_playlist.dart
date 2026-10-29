import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/music_info.dart';
import '../../../core/ui/app_toast.dart';
import '../playlist_browser_sheet.dart';
import '../playlist_store.dart';

Future<void> showAddMusicToPlaylist(
  BuildContext context,
  WidgetRef ref,
  MusicInfo music,
) async {
  final destination = await showPlaylistBrowserSheet(
    context,
    mode: PlaylistBrowserMode.addSongs,
  );
  if (!context.mounted || destination == null) return;

  const prefix = '/playlists/';
  if (!destination.startsWith(prefix)) return;
  final playlistId = destination.substring(prefix.length);
  final store = ref.read(localPlaylistsProvider.notifier);
  final playlist = store.byId(playlistId);
  if (playlist == null) {
    showAppToast(context, '歌单不存在或已被删除', type: AppToastType.warning);
    return;
  }

  try {
    final added = await store.addMusic(playlistId, music);
    if (!context.mounted) return;
    showAppToast(
      context,
      added == 0 ? '歌曲已在「${playlist.name}」中' : '已添加到「${playlist.name}」',
      type: added == 0 ? AppToastType.info : AppToastType.success,
    );
  } catch (error) {
    if (!context.mounted) return;
    showAppToast(context, '添加到歌单失败：$error', type: AppToastType.error);
  }
}
