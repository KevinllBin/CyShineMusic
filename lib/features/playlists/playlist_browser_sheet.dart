import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_ui/prism_ui.dart' as prism;

import '../../core/ui/app_scrollbar.dart';
import '../../core/ui/app_sheet.dart';
import '../../core/ui/widgets/app_navigation_button.dart';
import 'playlist_models.dart';
import 'playlist_store.dart';
import 'widgets/playlist_artwork.dart';

enum PlaylistBrowserMode { browse, addSongs }

Future<String?> showPlaylistBrowserSheet(
  BuildContext context, {
  PlaylistBrowserMode mode = PlaylistBrowserMode.browse,
  bool fromPlayer = false,
}) {
  if (fromPlayer) {
    return showAppSheet<String>(
      context: context,
      detents: prism.snapSheetDetents,
      fitsContent: true,
      neutralSurface: true,
      builder: (_) =>
          _PlaylistBrowserSheet(mode: mode, controller: null, fromPlayer: true),
    );
  }
  return prism.showSnapSheet<String>(
    Navigator.of(context, rootNavigator: true).context,
    builder: (_, controller) =>
        _PlaylistBrowserSheet(mode: mode, controller: controller),
  );
}

class _PlaylistBrowserSheet extends ConsumerStatefulWidget {
  const _PlaylistBrowserSheet({
    required this.mode,
    required this.controller,
    this.fromPlayer = false,
  });

  final PlaylistBrowserMode mode;
  final ScrollController? controller;
  final bool fromPlayer;

  @override
  ConsumerState<_PlaylistBrowserSheet> createState() =>
      _PlaylistBrowserSheetState();
}

class _PlaylistBrowserSheetState extends ConsumerState<_PlaylistBrowserSheet> {
  final _desktopController = ScrollController();

  @override
  void dispose() {
    _desktopController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = prism.Theme.of(context).colorScheme;
    final playlists = ref.watch(localPlaylistsProvider);
    final selecting = widget.mode == PlaylistBrowserMode.addSongs;
    final scrollController = widget.controller ?? _desktopController;
    if (widget.fromPlayer) {
      final controller =
          PrimaryScrollController.maybeOf(context) ?? _desktopController;
      return AppSheetLayout(
        title: '添加到歌单',
        centerTitle: true,
        subtitle: '${playlists.length} 个歌单',
        body: AppScrollbar(
          controller: controller,
          child: playlists.isEmpty
              ? _EmptyPlaylists(
                  controller: controller,
                  selecting: true,
                  shrinkWrap: true,
                )
              : prism.PrismListView(
                  controller: controller,
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                  itemCount: playlists.length,
                  itemBuilder: (context, index) => prism.ItemPositionProvider(
                    position: prism.ItemPosition.get(index, playlists.length),
                    child: _PlaylistSheetTile(
                      playlist: playlists[index],
                      selecting: true,
                      grouped: true,
                      onTap: () => Navigator.of(
                        context,
                      ).pop('/playlists/${playlists[index].id}'),
                    ),
                  ),
                ),
        ),
      );
    }
    return prism.SurfaceScope(
      level: prism.SurfaceLevel.page,
      child: prism.Surface(
        color: prism.SurfaceLevel.page.colorOf(scheme),
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              if (widget.controller != null) const prism.SheetDragHandle(),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            selecting ? '添加歌曲到' : '我的歌单',
                            style: prism.AppTextStyle.title3.of(
                              context,
                              emphasized: true,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${playlists.length} 个歌单',
                            style: TextStyle(
                              color: scheme.onSurfaceVariant,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    AppNavigationButton.close(
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              if (!selecting)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                  child: _FixedManagementTile(
                    onTap: () => Navigator.of(context).pop('/playlists'),
                  ),
                ),
              const prism.Divider(height: 1),
              Expanded(
                child: AppScrollbar(
                  controller: scrollController,
                  child: playlists.isEmpty
                      ? _EmptyPlaylists(
                          controller: scrollController,
                          selecting: selecting,
                        )
                      : prism.PrismListView(
                          controller: scrollController,
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
                          itemCount: playlists.length,
                          gap: 6,
                          itemBuilder: (context, index) {
                            final playlist = playlists[index];
                            return _PlaylistSheetTile(
                              playlist: playlist,
                              selecting: selecting,
                              onTap: () => Navigator.of(
                                context,
                              ).pop('/playlists/${playlist.id}'),
                            );
                          },
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FixedManagementTile extends StatelessWidget {
  const _FixedManagementTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = prism.Theme.of(context).colorScheme;
    return prism.Card(
      onPressed: onTap,
      radius: 20,
      child: prism.ListRow(
        minHeight: 72,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: scheme.primary,
            borderRadius: BorderRadius.circular(15),
          ),
          alignment: Alignment.center,
          child: Icon(
            Icons.library_music_rounded,
            color: scheme.onPrimary,
            size: 23,
          ),
        ),
        title: const Text(
          '歌单管理',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: const Text(
          '新建、导入、重命名与整理歌单',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
      ),
    );
  }
}

class _PlaylistSheetTile extends StatelessWidget {
  const _PlaylistSheetTile({
    required this.playlist,
    required this.selecting,
    required this.onTap,
    this.grouped = false,
  });

  final LocalPlaylist playlist;
  final bool selecting;
  final VoidCallback onTap;
  final bool grouped;

  @override
  Widget build(BuildContext context) {
    final scheme = prism.Theme.of(context).colorScheme;
    if (grouped) {
      return prism.DecorationListItem(
        onPressed: onTap,
        leading: PlaylistCover(
          playlist: playlist,
          size: 44,
          radius: 12,
          placeholder: Container(
            width: 44,
            height: 44,
            color: scheme.secondaryContainer,
            child: Icon(
              Icons.queue_music_rounded,
              color: scheme.onSecondaryContainer,
            ),
          ),
        ),
        title: Text(
          playlist.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${playlist.tracks.length} 首歌曲',
          style: prism.AppTextStyle.footnote.of(context),
        ),
        trailing: const Icon(Icons.add_rounded, size: 20),
      );
    }
    return prism.Card(
      onPressed: onTap,
      radius: 18,
      child: prism.ListRow(
        minHeight: 68,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        leading: PlaylistCover(
          playlist: playlist,
          size: 44,
          radius: 14,
          placeholder: Container(
            width: 44,
            height: 44,
            color: scheme.secondaryContainer,
            alignment: Alignment.center,
            child: Icon(
              Icons.queue_music_rounded,
              color: scheme.onSecondaryContainer,
              size: 23,
            ),
          ),
        ),
        title: Text(
          playlist.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text('${playlist.tracks.length} 首歌曲'),
        trailing: Icon(
          selecting ? Icons.add_rounded : Icons.chevron_right_rounded,
        ),
      ),
    );
  }
}

class _EmptyPlaylists extends StatelessWidget {
  const _EmptyPlaylists({
    required this.controller,
    required this.selecting,
    this.shrinkWrap = false,
  });

  final ScrollController controller;
  final bool selecting;
  final bool shrinkWrap;

  @override
  Widget build(BuildContext context) {
    final scheme = prism.Theme.of(context).colorScheme;
    return ListView(
      shrinkWrap: shrinkWrap,
      controller: controller,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(24, 36, 24, 24),
      children: [
        Icon(
          Icons.playlist_add_rounded,
          color: scheme.onSurfaceVariant,
          size: 38,
        ),
        const SizedBox(height: 12),
        Text(
          selecting ? '没有可添加的歌单' : '还没有歌单',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: scheme.onSurface,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          selecting ? '请先在歌单管理中创建或导入歌单' : '进入歌单管理即可新建或导入在线歌单',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: scheme.onSurfaceVariant,
            fontSize: 12.5,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}
