import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/music_info.dart';
import '../../../core/services/batch_download_controller.dart';
import '../../../core/storage/settings_store.dart';
import '../../../core/ui/app_toast.dart';
import '../../downloads/download_progress.dart';
import '../../music_sources/music_source_action_guard.dart';
import '../../playlists/playlist_browser_sheet.dart';
import '../../playlists/playlist_store.dart';
import '../../playlists/widgets/playlist_batch_download_bar.dart';

class OnlineCollectionBatchBar extends ConsumerStatefulWidget {
  const OnlineCollectionBatchBar({
    super.key,
    required this.title,
    required this.selected,
    required this.onPlay,
    required this.onFinished,
    required this.onSubmittingChanged,
  });

  final String title;
  final List<MusicInfo> selected;
  final Future<bool> Function(List<MusicInfo>) onPlay;
  final VoidCallback onFinished;
  final ValueChanged<bool> onSubmittingChanged;

  @override
  ConsumerState<OnlineCollectionBatchBar> createState() =>
      _OnlineCollectionBatchBarState();
}

class _OnlineCollectionBatchBarState
    extends ConsumerState<OnlineCollectionBatchBar> {
  bool _submitting = false;

  Future<void> _submit(Future<bool> Function(List<MusicInfo>) action) async {
    if (_submitting || widget.selected.isEmpty) return;
    final selected = List<MusicInfo>.of(widget.selected);
    setState(() => _submitting = true);
    widget.onSubmittingChanged(true);
    var finished = false;
    try {
      finished = await action(selected);
    } catch (error) {
      if (mounted) {
        showAppToast(context, '批量操作失败：$error', type: AppToastType.error);
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
        widget.onSubmittingChanged(false);
        if (finished) widget.onFinished();
      }
    }
  }

  Future<bool> _download(List<MusicInfo> selected) async {
    final progress = ref.read(downloadProgressProvider);
    final musics = selected
        .where((music) => !progress.isMusicBusy(music.id))
        .toList(growable: false);
    if (musics.isEmpty) {
      showAppToast(context, '所选歌曲已在下载中', type: AppToastType.info);
      return false;
    }
    final available = await ensureOnlineMusicSourcesAvailable(
      context,
      musics.map((music) => music.source),
    );
    if (!available || !mounted) return false;
    final task = ref
        .read(batchDownloadProvider.notifier)
        .create(
          musics: musics,
          title: widget.title,
          quality: ref.read(settingsProvider).batchDownloadQuality,
          skippedCount: selected.length - musics.length,
        );
    showAppToast(
      context,
      '已创建任务 ${task.id}：${task.items.length} 首'
      '${task.skippedCount > 0 ? '，跳过 ${task.skippedCount} 首' : ''}'
      '，可在下载页管理',
      type: task.items.isEmpty ? AppToastType.warning : AppToastType.info,
      duration: const Duration(seconds: 4),
    );
    return true;
  }

  Future<bool> _addToPlaylist(List<MusicInfo> selected) async {
    final destination = await showPlaylistBrowserSheet(
      context,
      mode: PlaylistBrowserMode.addSongs,
    );
    if (!mounted || destination == null) return false;
    const prefix = '/playlists/';
    if (!destination.startsWith(prefix)) return false;
    final playlistId = destination.substring(prefix.length);
    final store = ref.read(localPlaylistsProvider.notifier);
    final playlist = store.byId(playlistId);
    if (playlist == null) {
      showAppToast(context, '歌单不存在或已被删除', type: AppToastType.warning);
      return false;
    }
    final added = await store.addMusics(playlistId, selected);
    if (!mounted) return false;
    showAppToast(
      context,
      added == 0
          ? '所选歌曲已在「${playlist.name}」中'
          : '已加入 $added 首歌曲到「${playlist.name}」',
      type: added == 0 ? AppToastType.info : AppToastType.success,
    );
    return true;
  }

  @override
  Widget build(BuildContext context) => PlaylistBatchDownloadBar(
    selectedCount: widget.selected.length,
    downloadableCount: widget.selected.length,
    submitting: _submitting,
    showRemove: false,
    onRemove: null,
    onAddToPlaylist: widget.selected.isEmpty
        ? null
        : () => _submit(_addToPlaylist),
    onDownload: widget.selected.isEmpty ? null : () => _submit(_download),
    onPlaySelected: widget.selected.isEmpty
        ? null
        : () => _submit(widget.onPlay),
  );
}
