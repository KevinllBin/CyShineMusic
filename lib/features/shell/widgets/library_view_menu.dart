import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/storage/settings_store.dart';
import '../../../core/ui/glass_choice_menu.dart';
import '../../../core/ui/radio_menu.dart';
import '../../../theme/app_motion.dart';
import '../../playlists/playlist_store.dart';

/// Choices are read only when the menu opens, including in glass mode.
class LibraryViewMenu extends ConsumerWidget {
  const LibraryViewMenu({
    super.key,
    required this.title,
    required this.activePlaylistId,
    required this.scheme,
    required this.onSelected,
  });

  final String title;
  final String? activePlaylistId;
  final ColorScheme scheme;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final glass = ref.watch(
      settingsProvider.select((settings) => settings.liquidGlassEnabled),
    );
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
    List<RadioMenuOption> options() {
      final playlists = ref.read(localPlaylistsProvider);
      return [
        RadioMenuOption(
          id: 'local',
          label: '本地歌曲',
          selected: activePlaylistId == null,
          onSelected: () => onSelected(null),
        ),
        for (final playlist in playlists)
          RadioMenuOption(
            id: 'playlist-${playlist.id}',
            label: playlist.name,
            selected: playlist.id == activePlaylistId,
            onSelected: () => onSelected(playlist.id),
          ),
      ];
    }

    Widget anchor(
      BuildContext context,
      bool expanded,
      GestureTapDownCallback onTapDown,
      VoidCallback onTap,
    ) => Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(glass ? 22 : 10),
        onTapDown: onTapDown,
        onTap: onTap,
        child: Semantics(
          button: true,
          expanded: expanded,
          hint: '切换歌单视图',
          child: Padding(
            padding: glass
                ? const EdgeInsets.symmetric(horizontal: 10, vertical: 4)
                : const EdgeInsets.fromLTRB(2, 4, 0, 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(child: titleText),
                AnimatedRotation(
                  turns: expanded ? 0.5 : 0,
                  duration: AppMotion.short,
                  curve: AppMotion.emphasized,
                  child: Icon(
                    Icons.arrow_drop_down_rounded,
                    color: scheme.onSurfaceVariant,
                    size: 26,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (glass) {
      return ValueListenableBuilder<RouteInformation>(
        key: const ValueKey('library-view-menu-anchor'),
        valueListenable: GoRouter.of(context).routeInformationProvider,
        builder: (context, route, _) => route.uri.path != '/songs'
            ? const SizedBox.shrink()
            : GlassChoiceMenu(
                optionsBuilder: () => [
                  for (final option in options())
                    GlassChoiceOption(
                      label: option.label,
                      selected: option.selected,
                      enabled: option.enabled,
                      onSelected: option.onSelected,
                    ),
                ],
                anchorBuilder: (expanded, onTap) =>
                    anchor(context, expanded, (_) {}, onTap),
              ),
      );
    }
    return RadioMenuAnchor(
      key: const ValueKey('library-view-menu-anchor'),
      menuId: 'library-view-menu',
      minimumWidth: 156,
      maximumWidth: 240,
      maximumHeight: 300,
      optionsBuilder: options,
      anchorBuilder: anchor,
    );
  }
}
