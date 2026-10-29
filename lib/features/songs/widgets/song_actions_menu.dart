import 'package:flutter/material.dart';

import '../../../core/ui/widgets/morphing_menu_button.dart';
import '../../downloads/download_progress.dart';

/// The action sets used by local songs, saved playlists and online results.
class SongActionsMenu extends StatelessWidget {
  const SongActionsMenu._({super.key, required this.actions});

  factory SongActionsMenu.local({
    Key? key,
    required VoidCallback onDelete,
    required VoidCallback onAddToPlaylist,
    required VoidCallback onAddNext,
  }) => SongActionsMenu._(
    key: key,
    actions: [
      MorphingMenuAction(
        label: '删除',
        leading: const Icon(Icons.delete_outline_rounded),
        onSelected: onDelete,
        danger: true,
      ),
      _addToPlaylist(onAddToPlaylist),
      _addNext(onAddNext, label: '下一首播放'),
    ],
  );

  factory SongActionsMenu.playlist({
    Key? key,
    required VoidCallback onRemove,
    required VoidCallback? onAddNext,
    required VoidCallback? onDownload,
    DownloadTask? downloadTask,
    bool downloaded = false,
  }) => SongActionsMenu._(
    key: key,
    actions: [
      MorphingMenuAction(
        label: '移出歌单',
        leading: const Icon(Icons.playlist_remove_rounded),
        onSelected: onRemove,
        danger: true,
      ),
      _addNext(onAddNext),
      _download(onDownload, downloadTask, downloaded: downloaded),
    ],
  );

  factory SongActionsMenu.online({
    Key? key,
    required VoidCallback onDownload,
    required VoidCallback onAddToPlaylist,
    DownloadTask? downloadTask,
  }) => SongActionsMenu._(
    key: key,
    actions: [
      _download(onDownload, downloadTask),
      _addToPlaylist(onAddToPlaylist),
    ],
  );

  final List<MorphingMenuAction> actions;

  static MorphingMenuAction _addToPlaylist(VoidCallback? onSelected) =>
      MorphingMenuAction(
        label: '添加到歌单',
        leading: const Icon(Icons.playlist_add_rounded),
        onSelected: onSelected,
      );

  static MorphingMenuAction _addNext(
    VoidCallback? onSelected, {
    String label = '添加到下一首播放',
  }) => MorphingMenuAction(
    label: label,
    leading: const Icon(Icons.playlist_play_rounded),
    onSelected: onSelected,
  );

  static MorphingMenuAction _download(
    VoidCallback? onSelected,
    DownloadTask? task, {
    bool downloaded = false,
  }) {
    final busy = task?.isBusy ?? false;
    final done = downloaded || task?.stage == DownloadStage.done;
    final fraction = task?.fraction;
    return MorphingMenuAction(
      label: done
          ? '已下载'
          : busy
          ? fraction == null
                ? '正在下载'
                : '正在下载 ${(fraction * 100).round()}%'
          : '下载',
      leading: busy
          ? SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(value: fraction, strokeWidth: 2),
            )
          : Icon(done ? Icons.download_done_rounded : Icons.download_rounded),
      onSelected: busy || done ? null : onSelected,
    );
  }

  @override
  Widget build(BuildContext context) => MorphingMenuButton(
    tooltip: '歌曲操作',
    icon: Icons.more_horiz_rounded,
    motionStyle: MorphingMenuMotionStyle.list,
    actions: actions,
  );
}
