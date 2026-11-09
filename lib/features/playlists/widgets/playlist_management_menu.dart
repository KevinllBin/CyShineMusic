import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prism_ui/prism_ui.dart' as prism;
import 'package:prism_ui/icons/icons.dart';

class PlaylistManagementMenuState {
  const PlaylistManagementMenuState({
    this.owner,
    this.onCreate,
    this.onImportLx,
    this.importLabel = '洛雪导入',
  });

  final Object? owner;
  final VoidCallback? onCreate;
  final VoidCallback? onImportLx;
  final String importLabel;
}

final playlistManagementMenuProvider = StateProvider(
  (ref) => const PlaylistManagementMenuState(),
);

class PlaylistManagementMenu extends ConsumerWidget {
  const PlaylistManagementMenu({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(playlistManagementMenuProvider);
    final glass = prism.LiquidGlassScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    return prism.TonalButtonTheme(
      size: prism.TonalButtonSize.section,
      glass: glass,
      child: prism.PopupAnchor(
        targetBuilder: (open) => prism.IconButton(
          tooltip: '歌单管理操作',
          style: prism.ButtonStyle(
            shape: const CircleBorder(),
            backgroundColor: glass
                ? null
                : WidgetStatePropertyAll(
                    scheme.brightness == Brightness.light
                        ? Colors.white
                        : scheme.surfaceContainerHigh,
                  ),
            side: glass
                ? null
                : WidgetStatePropertyAll(
                    BorderSide(
                      color: scheme.outlineVariant.withValues(alpha: 0.55),
                      width: 0.8,
                    ),
                  ),
            tapTargetSize: prism.TapTargetSize.padded,
          ),
          onPressed: state.owner == null ? null : open,
          icon: const GlyphIcon(AppGlyphs.more),
        ),
        popupBuilder: (_) => prism.PopupMenu(
          items: [
            prism.PopupMenuItem(
              label: '新建歌单',
              glyph: AppGlyphs.add,
              executeImmediately: true,
              onPressed: state.onCreate,
            ),
            prism.PopupMenuItem(
              label: '在线导入',
              glyph: AppGlyphs.cloudDownload,
              executeImmediately: true,
              onPressed: () => context.go('/playlists/import'),
            ),
            prism.PopupMenuItem(
              label: state.importLabel,
              glyph: AppGlyphs.upload,
              executeImmediately: true,
              onPressed: state.onImportLx,
            ),
          ],
        ),
      ),
    );
  }
}
