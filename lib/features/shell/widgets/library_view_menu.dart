import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_ui/prism_ui.dart' as prism;
import 'package:prism_ui/icons/prism_glyphs.dart' as prism_glyphs;
import 'package:prism_ui/icons/icons.dart' as glyph;

import '../../playlists/playlist_store.dart';

/// Header title that doubles as a library view switcher: tapping it opens a
/// menu listing "本地歌曲" plus every local playlist. Selection is handed
/// back to SongsPage so the list can switch in place.
///
/// The playlist list is read lazily when the menu opens, so rendering the
/// header never touches [localPlaylistsProvider] (which requires
/// SharedPreferences and would throw in detached widget tests).
class LibraryViewMenu extends ConsumerWidget {
  const LibraryViewMenu({
    super.key,
    required this.title,
    required this.activePlaylistId,
    required this.scheme,
    required this.onSelected,
  });

  final String title;

  /// Currently displayed playlist id, or null when the local library is shown.
  final String? activePlaylistId;
  final ColorScheme scheme;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = this.scheme;
    final titleText = Text(
      title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
        color: scheme.onSurface,
        fontSize: 22,
        fontWeight: FontWeight.w600,
        height: 1.05,
      ),
    );
    return prism.PopupAnchor(
      key: const ValueKey('library-view-menu-anchor'),
      targetBuilder: (open) => Semantics(
        button: true,
        hint: '切换歌单视图',
        child: prism.TextButton(
          onPressed: open,
          style: prism.ButtonStyle.from(
            foregroundColor: scheme.onSurface,
            padding: const EdgeInsets.fromLTRB(2, 4, 0, 4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: titleText),
              const glyph.GlyphIcon(prism_glyphs.AppGlyphs.chevronDown, size: 20),
            ],
          ),
        ),
      ),
      popupBuilder: (_) {
        final playlists = ref.read(localPlaylistsProvider);
        return prism.PopupMenu(
          maxVisibleItems: 7,
          items: [
            prism.PopupMenuItem(
              label: '本地歌曲',
              checked: activePlaylistId == null,
              executeImmediately: true,
              onPressed: () => onSelected(null),
            ),
            for (final playlist in playlists)
              prism.PopupMenuItem(
                label: playlist.name,
                checked: playlist.id == activePlaylistId,
                executeImmediately: true,
                onPressed: () => onSelected(playlist.id),
              ),
          ],
        );
      },
    );
  }
}
