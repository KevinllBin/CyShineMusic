import 'package:flutter/material.dart';
import 'package:prism_ui/prism_ui.dart' as prism;
import 'package:prism_ui/icons/prism_glyphs.dart';
import 'package:prism_ui/icons/icons.dart' as prism_glyph;

import '../../downloads/download_progress.dart';
import '../../../core/ui/music_action_glyphs.dart';

/// The action sets used by local songs, saved playlists and online results.
class SongActionsMenu extends StatelessWidget {
  const SongActionsMenu._({super.key, required this.items});

  factory SongActionsMenu.local({
    Key? key,
    required VoidCallback onDelete,
    required VoidCallback onAddToPlaylist,
    required VoidCallback onAddNext,
  }) => SongActionsMenu._(
    key: key,
    items: [
      prism.PopupMenuItem(
        label: '删除',
        glyph: MusicActionGlyphs.trash,
        executeImmediately: true,
        onPressed: onDelete,
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
    items: [
      prism.PopupMenuItem(
        label: '移出歌单',
        glyph: MusicActionGlyphs.playlistRemove,
        executeImmediately: true,
        onPressed: onRemove,
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
    items: [
      _download(onDownload, downloadTask),
      _addToPlaylist(onAddToPlaylist),
    ],
  );

  final List<prism.PopupMenuItem> items;

  static prism.PopupMenuItem _addToPlaylist(VoidCallback? onPressed) =>
      prism.PopupMenuItem(
        label: '添加到歌单',
        glyph: MusicActionGlyphs.playlistAdd,
        executeImmediately: true,
        onPressed: onPressed,
      );

  static prism.PopupMenuItem _addNext(
    VoidCallback? onPressed, {
    String label = '添加到下一首播放',
  }) => prism.PopupMenuItem(
    label: label,
    glyph: MusicActionGlyphs.playNext,
    executeImmediately: true,
    onPressed: onPressed,
  );

  static prism.PopupMenuItem _download(
    VoidCallback? onPressed,
    DownloadTask? task, {
    bool downloaded = false,
  }) {
    final busy = task?.isBusy ?? false;
    final done = downloaded || task?.stage == DownloadStage.done;
    final fraction = task?.fraction;
    return prism.PopupMenuItem(
      label: done
          ? '已下载'
          : busy
          ? fraction == null
                ? '正在下载'
                : '正在下载 ${(fraction * 100).round()}%'
          : '下载',
      glyph: done ? MusicActionGlyphs.downloaded : MusicActionGlyphs.download,
      executeImmediately: true,
      onPressed: busy || done ? null : onPressed,
    );
  }

  @override
  Widget build(BuildContext context) => prism.PopupAnchor(
    targetBuilder: (open) => prism.IconButton(
      tooltip: '歌曲操作',
      onPressed: open,
      icon: const prism_glyph.GlyphIcon(AppGlyphs.more),
    ),
    popupBuilder: (_) => prism.PopupMenu(items: items),
  );
}
