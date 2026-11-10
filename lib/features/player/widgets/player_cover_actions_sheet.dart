import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_ui/prism_ui.dart' as prism;

import '../../../core/models/music_info.dart';
import '../../../core/storage/settings_store.dart';
import '../../../core/ui/app_sheet.dart';
import '../../../core/ui/app_toast.dart';
import '../../playlists/playlist_browser_sheet.dart';
import '../../playlists/playlist_store.dart';
import '../../search/widgets/quality_picker_sheet.dart';
import '../player_controller.dart';
import 'player_quality_sheet.dart';

Future<void> showPlayerCoverActionsSheet(
  BuildContext context,
  WidgetRef ref, {
  required PlayerTrack track,
  required bool wide,
}) => showAppSheet<void>(
  context: context,
  heightFraction: 0.66,
  maxHeight: 560,
  fitsContent: true,
  floating: false,
  neutralSurface: true,
  builder: (_) => _PlayerCoverActionsSheet(track: track, wide: wide),
);

Future<void> _addCurrentMusicToPlaylist(
  BuildContext context,
  WidgetRef ref,
  MusicInfo music,
) async {
  final destination = await showPlaylistBrowserSheet(
    context,
    mode: PlaylistBrowserMode.addSongs,
    fromPlayer: true,
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

class _PlayerCoverActionsSheet extends ConsumerWidget {
  const _PlayerCoverActionsSheet({required this.track, required this.wide});

  final PlayerTrack track;
  final bool wide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final miniLyrics = ref.watch(
      settingsProvider.select((settings) => settings.showMiniLyrics),
    );
    final player = ref.watch(
      playerControllerProvider.select(
        (state) => (track: state.track, loading: state.loading),
      ),
    );
    final current = player.track ?? track;
    final music = ref.read(playerControllerProvider.notifier).currentMusic;
    final canAddToPlaylist = !current.isLocal && music != null;
    final canDownload = !current.isLocal && music != null;
    final canSwitchQuality =
        !current.isLocal &&
        music != null &&
        !player.loading &&
        availablePlaybackQualityOptions(current).length > 1;
    final colors = prism.Theme.of(context).colorScheme;
    final disabledColor = colors.onSurface.withValues(alpha: 0.38);
    final missingMusicReason = current.isLocal ? '仅在线歌曲' : '暂无歌曲信息';

    Widget action({
      required String id,
      required String title,
      required bool enabled,
      required VoidCallback onPressed,
      required String disabledReason,
      Widget? value,
    }) => Semantics(
      button: true,
      enabled: enabled,
      hint: enabled ? null : disabledReason,
      child: prism.DecorationListItem(
        key: ValueKey('player-cover-action-$id'),
        title: Text(
          title,
          style: enabled ? null : TextStyle(color: disabledColor),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 8,
          children: enabled
              ? [?value, const Icon(Icons.chevron_right_rounded, size: 18)]
              : [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 140),
                    child: Text(
                      disabledReason,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: prism.AppTextStyle.footnote
                          .of(context)
                          .copyWith(color: colors.onSurfaceVariant),
                    ),
                  ),
                  Icon(Icons.block_rounded, size: 16, color: disabledColor),
                ],
        ),
        onPressed: enabled ? onPressed : null,
      ),
    );

    final unavailable = current.isLocal
        ? '本地歌曲暂不支持添加到歌单、下载或切换音质。'
        : player.loading
        ? '正在加载歌曲，暂时无法切换音质。'
        : null;
    return AppSheetLayout(
      key: const ValueKey('player-cover-actions-sheet'),
      title: '歌曲选项',
      centerTitle: true,
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    current.title.trim().isEmpty ? '未知歌曲' : current.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: prism.AppTextStyle.callout.of(
                      context,
                      emphasized: true,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${current.artist} · ${current.isLocal ? '本地' : current.sourceLabel}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: prism.AppTextStyle.footnote
                        .of(context)
                        .copyWith(color: colors.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            prism.generateGroup([
              action(
                id: 'playlist',
                title: '添加到歌单',
                enabled: canAddToPlaylist,
                disabledReason: missingMusicReason,
                onPressed: () =>
                    unawaited(_addCurrentMusicToPlaylist(context, ref, music!)),
              ),
              action(
                id: 'download',
                title: '下载歌曲',
                enabled: canDownload,
                disabledReason: missingMusicReason,
                onPressed: () => unawaited(
                  showQualityPickerSheet(context, music!, asSheet: true),
                ),
              ),
              action(
                id: 'quality',
                title: '播放音质',
                value: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 140),
                  child: Text(
                    playerQualityLabel(current),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: prism.AppTextStyle.subheadline
                        .of(context)
                        .copyWith(color: colors.onSurfaceVariant),
                  ),
                ),
                enabled: canSwitchQuality,
                disabledReason: current.isLocal || music == null
                    ? missingMusicReason
                    : player.loading
                    ? '加载中'
                    : '暂无其他音质',
                onPressed: () => unawaited(
                  showPlaybackQualitySheet(context, ref, track: current),
                ),
              ),
            ]),
            if (unavailable != null) prism.ListFooter(text: unavailable),
            const SizedBox(height: 24),
            prism.generateGroup([
              prism.DecorationListItem(
                key: const ValueKey('player-cover-action-mini-lyrics'),
                title: const Text('迷你歌词'),
                onPressed: () => unawaited(
                  ref
                      .read(settingsProvider.notifier)
                      .setShowMiniLyrics(!miniLyrics),
                ),
                trailing: prism.Switch(
                  key: const ValueKey('player-cover-action-mini-lyrics-switch'),
                  value: miniLyrics,
                  onChanged: (value) => unawaited(
                    ref
                        .read(settingsProvider.notifier)
                        .setShowMiniLyrics(value),
                  ),
                ),
              ),
            ]),
            prism.ListFooter(text: wide ? '仅在手机播放封面页显示。' : '在封面页显示三行歌词。'),
          ],
        ),
      ),
    );
  }
}
