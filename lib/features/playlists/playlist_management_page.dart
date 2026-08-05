import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/enums.dart';
import '../../core/ui/app_toast.dart';
import '../../theme/app_motion.dart';
import 'playlist_name_dialog.dart';
import 'playlist_models.dart';
import 'playlist_store.dart';
import 'widgets/playlist_artwork.dart';

class PlaylistManagementPage extends ConsumerWidget {
  const PlaylistManagementPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlists = ref.watch(localPlaylistsProvider);
    return Scaffold(
      body: CustomScrollView(
        key: const PageStorageKey('playlists-manage-scroll'),
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
            sliver: SliverToBoxAdapter(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: _ManagementActions(
                    count: playlists.length,
                    onCreate: () => _createPlaylist(context, ref),
                    onImport: () => context.go('/playlists/import'),
                  ),
                ),
              ),
            ),
          ),
          if (playlists.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: _EmptyManagement(),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 116),
              sliver: SliverList.separated(
                itemCount: playlists.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final playlist = playlists[index];
                  return Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 760),
                      child: _PlaylistManagementTile(
                        playlist: playlist,
                        onOpen: () =>
                            context.go(_managementDetailLocation(playlist.id)),
                        onRename: () => _renamePlaylist(context, ref, playlist),
                        onDelete: () => _deletePlaylist(context, ref, playlist),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _createPlaylist(BuildContext context, WidgetRef ref) async {
    final name = await showPlaylistNameDialog(
      context,
      title: '新建歌单',
      actionLabel: '创建',
    );
    if (name == null || !context.mounted) return;
    try {
      final playlist = await ref
          .read(localPlaylistsProvider.notifier)
          .create(name);
      if (!context.mounted) return;
      showAppToast(
        context,
        '歌单“${playlist.name}”已创建',
        type: AppToastType.success,
      );
      context.go(_managementDetailLocation(playlist.id));
    } on PlaylistStoreException catch (error) {
      if (context.mounted) {
        showAppToast(context, error.message, type: AppToastType.warning);
      }
    }
  }

  Future<void> _renamePlaylist(
    BuildContext context,
    WidgetRef ref,
    LocalPlaylist playlist,
  ) async {
    final name = await showPlaylistNameDialog(
      context,
      title: '重命名歌单',
      actionLabel: '保存',
      initialValue: playlist.name,
    );
    if (name == null || !context.mounted) return;
    try {
      await ref.read(localPlaylistsProvider.notifier).rename(playlist.id, name);
      if (context.mounted) {
        showAppToast(context, '歌单名称已更新', type: AppToastType.success);
      }
    } on PlaylistStoreException catch (error) {
      if (context.mounted) {
        showAppToast(context, error.message, type: AppToastType.warning);
      }
    }
  }

  Future<void> _deletePlaylist(
    BuildContext context,
    WidgetRef ref,
    LocalPlaylist playlist,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.delete_outline_rounded),
        title: const Text('删除这个歌单？'),
        content: Text('“${playlist.name}”会被删除，本地音乐文件和下载记录不会受到影响。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await ref.read(localPlaylistsProvider.notifier).delete(playlist.id);
    if (context.mounted) {
      showAppToast(context, '歌单已删除', type: AppToastType.success);
    }
  }
}

class _ManagementActions extends StatelessWidget {
  const _ManagementActions({
    required this.count,
    required this.onCreate,
    required this.onImport,
  });

  final int count;
  final VoidCallback onCreate;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.22),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.queue_music_rounded,
                  color: scheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '整理你的音乐收藏',
                      style: TextStyle(
                        color: scheme.onSurface,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '$count 个本地歌单',
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          LayoutBuilder(
            builder: (context, constraints) {
              final useVerticalLayout =
                  constraints.maxWidth < 340 ||
                  MediaQuery.textScalerOf(context).scale(1) > 1.3;
              final createButton = FilledButton.icon(
                style: const ButtonStyle(
                  minimumSize: WidgetStatePropertyAll(Size(72, 48)),
                ),
                onPressed: onCreate,
                icon: const Icon(Icons.add_rounded),
                label: const Text('新建歌单'),
              );
              final importButton = FilledButton.tonalIcon(
                style: const ButtonStyle(
                  minimumSize: WidgetStatePropertyAll(Size(72, 48)),
                ),
                onPressed: onImport,
                icon: const Icon(Icons.cloud_download_outlined),
                label: const Text('在线导入'),
              );
              if (useVerticalLayout) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    createButton,
                    const SizedBox(height: 8),
                    importButton,
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: createButton),
                  const SizedBox(width: 10),
                  Expanded(child: importButton),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

String _managementDetailLocation(String playlistId) {
  return Uri(
    path: '/playlists/$playlistId',
    queryParameters: const {'from': 'manage'},
  ).toString();
}

enum _PlaylistMenuAction { rename, delete }

class _PlaylistManagementTile extends StatelessWidget {
  const _PlaylistManagementTile({
    required this.playlist,
    required this.onOpen,
    required this.onRename,
    required this.onDelete,
  });

  final LocalPlaylist playlist;
  final VoidCallback onOpen;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final importedSource = MusicSource.fromCode(
      playlist.originSourceCode ?? '',
    );
    return AnimatedContainer(
      duration: AppMotion.short,
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.22),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 4, 10),
            child: Row(
              children: [
                _PlaylistCover(playlist: playlist),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        playlist.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: scheme.onSurface,
                          fontSize: 15.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        playlist.isOnlineImport
                            ? '${importedSource.label}导入 · ${playlist.tracks.length} 首'
                            : '${playlist.tracks.length} 首歌曲',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<_PlaylistMenuAction>(
                  tooltip: '歌单选项',
                  onSelected: (action) {
                    switch (action) {
                      case _PlaylistMenuAction.rename:
                        onRename();
                      case _PlaylistMenuAction.delete:
                        onDelete();
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: _PlaylistMenuAction.rename,
                      child: ListTile(
                        leading: Icon(Icons.edit_outlined),
                        title: Text('重命名'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    PopupMenuItem(
                      value: _PlaylistMenuAction.delete,
                      child: ListTile(
                        leading: Icon(Icons.delete_outline_rounded),
                        title: Text('删除'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                  icon: const Icon(Icons.more_vert_rounded),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PlaylistCover extends StatelessWidget {
  const _PlaylistCover({required this.playlist});

  final LocalPlaylist playlist;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final placeholder = Container(
      width: 58,
      height: 58,
      color: scheme.secondaryContainer,
      alignment: Alignment.center,
      child: Icon(
        playlist.isOnlineImport
            ? Icons.cloud_done_outlined
            : Icons.music_note_rounded,
        color: scheme.onSecondaryContainer,
        size: 25,
      ),
    );
    return PlaylistCover(
      playlist: playlist,
      size: 58,
      radius: 16,
      placeholder: placeholder,
    );
  }
}

class _EmptyManagement extends StatelessWidget {
  const _EmptyManagement();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 26, 28, 108),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              color: scheme.secondaryContainer,
              borderRadius: BorderRadius.circular(28),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.playlist_add_rounded,
              color: scheme.onSecondaryContainer,
              size: 38,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '从第一个歌单开始',
            style: TextStyle(
              color: scheme.onSurface,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '新建空歌单，或从酷我、酷狗、QQ、网易云和咪咕导入公开歌单。',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontSize: 13,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}
