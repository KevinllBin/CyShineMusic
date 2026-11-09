import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prism_ui/prism_ui.dart' as prism;
import 'package:prism_ui/icons/prism_glyphs.dart' as prism_glyphs;
import 'package:prism_ui/icons/icons.dart' as glyph;

import '../../core/models/enums.dart';
import '../../core/ui/app_scrollbar.dart';
import '../../core/ui/app_toast.dart';
import '../../core/ui/car_display_layout.dart';
import '../../core/ui/music_action_glyphs.dart';
import '../shell/shell_bottom_area.dart';
import '../shell/widgets/scrolling_page_header.dart';
import 'lx_playlist_import.dart';
import 'online_playlist_updater.dart';
import 'playlist_cover_resolver.dart';
import 'playlist_name_dialog.dart';
import 'playlist_models.dart';
import 'playlist_store.dart';
import 'widgets/playlist_artwork.dart';
import 'widgets/playlist_management_menu.dart';

class PlaylistManagementPage extends ConsumerStatefulWidget {
  const PlaylistManagementPage({super.key});

  @override
  ConsumerState<PlaylistManagementPage> createState() =>
      _PlaylistManagementPageState();
}

class _PlaylistManagementPageState
    extends ConsumerState<PlaylistManagementPage> {
  final ScrollController _scrollController = ScrollController();
  final Object _menuOwner = Object();
  late final _menuState = ref.read(playlistManagementMenuProvider.notifier);

  void _syncMenu() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _menuState.state = PlaylistManagementMenuState(
        owner: _menuOwner,
        onCreate: () => unawaited(_createPlaylist(context, ref)),
        onImportLx: _importingLx ? null : () => unawaited(_importLxPlaylist()),
        importLabel: _importingLx ? _lxImportProgress ?? '正在导入' : '洛雪导入',
      );
    });
  }

  bool _importingLx = false;
  String? _lxImportProgress;
  final Set<String> _updatingPlaylistIds = <String>{};

  @override
  void dispose() {
    final menuState = _menuState;
    scheduleMicrotask(() {
      if (menuState.mounted && identical(menuState.state.owner, _menuOwner)) {
        menuState.state = const PlaylistManagementMenuState();
      }
    });
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final playlists = ref.watch(localPlaylistsProvider);
    _syncMenu();
    return Scaffold(
      body: AppScrollbar(
        controller: _scrollController,
        child: CustomScrollView(
          controller: _scrollController,
          key: const PageStorageKey('playlists-manage-scroll'),
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          slivers: [
            const SliverToBoxAdapter(child: ScrollHeaderSpacer()),
            if (playlists.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: _EmptyManagement(),
              )
            else
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  12,
                  16,
                  ShellBottomArea.contentPadding(context, 116),
                ),
                sliver: SliverList.separated(
                  itemCount: playlists.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final playlist = playlists[index];
                    return Center(
                      child: ConstrainedBox(
                        constraints: CarDisplayLayout.contentConstraints(
                          context,
                          maxWidth: 760,
                        ),
                        child: _PlaylistManagementTile(
                          playlist: playlist,
                          onOpen: () => context.go(
                            _managementDetailLocation(playlist.id),
                          ),
                          onRename: () =>
                              _renamePlaylist(context, ref, playlist),
                          onUpdate: playlist.isOnlineImport
                              ? () => _updatePlaylist(playlist)
                              : null,
                          updating: _updatingPlaylistIds.contains(playlist.id),
                          onDelete: () =>
                              _deletePlaylist(context, ref, playlist),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
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

  Future<void> _importLxPlaylist() async {
    if (_importingLx) return;
    setState(() => _importingLx = true);
    try {
      final picked = await ref.read(lxPlaylistFilePickerProvider)();
      if (picked == null || !mounted) return;

      final document = parseLxPlaylistFile(picked.bytes, fileName: picked.name);
      final coverResolution = await resolveLxPlaylistCovers(
        document.playlists,
        ref.read(playlistCoverResolverProvider),
        onProgress: (completed, total) {
          if (!mounted) return;
          setState(() => _lxImportProgress = '封面 $completed/$total');
        },
      );
      if (!mounted) return;
      final imported = await ref
          .read(localPlaylistsProvider.notifier)
          .importLxPlaylists(coverResolution.playlists);
      if (!mounted) return;

      final trackCount = imported.fold<int>(
        0,
        (total, playlist) => total + playlist.tracks.length,
      );
      final skipped = document.skippedTrackCount;
      final message = imported.length == 1
          ? '已导入“${imported.single.name}”，共 $trackCount 首'
          : '已导入 ${imported.length} 个洛雪歌单，共 $trackCount 首';
      final coverMessage = coverResolution.resolvedCount > 0
          ? '，补全 ${coverResolution.resolvedCount} 张封面'
          : '';
      final skippedParts = <String>[
        if (document.skippedPlaylistCount > 0)
          '${document.skippedPlaylistCount} 个无效歌单',
        if (skipped > 0) '$skipped 首无效或不支持的歌曲',
      ];
      showAppToast(
        context,
        skippedParts.isEmpty
            ? '$message$coverMessage'
            : '$message$coverMessage，跳过 ${skippedParts.join('、')}',
        type: AppToastType.success,
      );
    } on LxPlaylistImportException catch (error) {
      if (mounted) {
        showAppToast(context, error.message, type: AppToastType.warning);
      }
    } catch (_) {
      if (mounted) {
        showAppToast(context, '读取洛雪歌单文件失败', type: AppToastType.error);
      }
    } finally {
      if (mounted) {
        setState(() {
          _importingLx = false;
          _lxImportProgress = null;
        });
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

  Future<void> _updatePlaylist(LocalPlaylist playlist) async {
    if (_updatingPlaylistIds.contains(playlist.id)) return;
    setState(() => _updatingPlaylistIds.add(playlist.id));
    try {
      final result = await ref
          .read(onlinePlaylistUpdaterProvider)
          .update(
            playlist: playlist,
            store: ref.read(localPlaylistsProvider.notifier),
          );
      if (!mounted) return;
      showAppToast(
        context,
        onlinePlaylistUpdateMessage(result),
        type: AppToastType.success,
      );
    } catch (error) {
      if (!mounted) return;
      showAppToast(context, '更新歌单失败：$error', type: AppToastType.error);
    } finally {
      if (mounted) setState(() => _updatingPlaylistIds.remove(playlist.id));
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

String _managementDetailLocation(String playlistId) {
  return Uri(
    path: '/playlists/$playlistId',
    queryParameters: const {'from': 'manage'},
  ).toString();
}

class _PlaylistManagementTile extends StatelessWidget {
  const _PlaylistManagementTile({
    required this.playlist,
    required this.onOpen,
    required this.onRename,
    required this.onUpdate,
    required this.updating,
    required this.onDelete,
  });

  final LocalPlaylist playlist;
  final VoidCallback onOpen;
  final VoidCallback onRename;
  final VoidCallback? onUpdate;
  final bool updating;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final importedSource = MusicSource.fromCode(
      playlist.originSourceCode ?? '',
    );
    return prism.Card(
      radius: prism.AppCorner.xl,
      padding: const EdgeInsets.fromLTRB(10, 10, 4, 10),
      onPressed: onOpen,
      child: Padding(
        padding: EdgeInsets.zero,
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
                    style: prism.AppTextStyle.subheadline.of(
                      context,
                      emphasized: true,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    playlist.isOnlineImport
                        ? '${importedSource.label}导入 · ${playlist.tracks.length} 首'
                        : '${playlist.tracks.length} 首歌曲',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: prism.AppTextStyle.caption1.of(context),
                  ),
                ],
              ),
            ),
            prism.PopupAnchor(
              targetBuilder: (open) => prism.IconButton(
                tooltip: '歌单选项',
                onPressed: open,
                icon: const glyph.GlyphIcon(prism_glyphs.AppGlyphs.more),
              ),
              popupBuilder: (_) => prism.PopupMenu(
                items: [
                  if (onUpdate != null)
                    prism.PopupMenuItem(
                      label: updating ? '正在更新' : '更新歌单',
                      glyph: prism_glyphs.AppGlyphs.refresh,
                      executeImmediately: true,
                      onPressed: updating ? null : onUpdate,
                    ),
                  prism.PopupMenuItem(
                    label: '重命名',
                    glyph: prism_glyphs.AppGlyphs.edit,
                    executeImmediately: true,
                    onPressed: onRename,
                  ),
                  prism.PopupMenuItem(
                    label: '删除',
                    glyph: MusicActionGlyphs.trash,
                    executeImmediately: true,
                    onPressed: onDelete,
                    danger: true,
                  ),
                ],
              ),
            ),
          ],
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
      padding: EdgeInsets.fromLTRB(
        28,
        26,
        28,
        ShellBottomArea.contentPadding(context, 108),
      ),
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
