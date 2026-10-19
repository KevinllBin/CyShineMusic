import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';

import '../../../core/storage/settings_store.dart';

class SongsOverflowMenu extends ConsumerWidget {
  const SongsOverflowMenu({
    super.key,
    this.onOpenHistory,
    this.searchLabel = '搜索本地歌曲',
    this.onSearch,
    this.onUpdatePlaylist,
    this.updatingPlaylist = false,
  });

  final VoidCallback? onOpenHistory;
  final String searchLabel;
  final VoidCallback? onSearch;
  final VoidCallback? onUpdatePlaylist;
  final bool updatingPlaylist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final glass = ref.watch(
      settingsProvider.select((settings) => settings.liquidGlassEnabled),
    );
    final actions = [
      _SongsMenuAction(
        label: searchLabel,
        icon: Icons.search_rounded,
        onPressed: onSearch == null
            ? null
            : () {
                FocusManager.instance.primaryFocus?.unfocus();
                onSearch!();
              },
      ),
      if (onUpdatePlaylist != null)
        _SongsMenuAction(
          label: updatingPlaylist ? '正在更新' : '更新歌单',
          icon: Icons.refresh_rounded,
          loading: updatingPlaylist,
          onPressed: updatingPlaylist ? null : onUpdatePlaylist,
        ),
      _SongsMenuAction(
        label: '下载历史',
        icon: Icons.history_rounded,
        onPressed: onOpenHistory ?? () => context.go('/downloads'),
      ),
    ];

    if (glass) {
      // Retained tab pages must not leave their portal above another page.
      return ValueListenableBuilder<RouteInformation>(
        valueListenable: GoRouter.of(context).routeInformationProvider,
        builder: (context, route, _) => route.uri.path == '/songs'
            ? _MorphingSongsMenu(actions: actions)
            : const SizedBox.square(dimension: 44),
      );
    }

    return MenuAnchor(
      key: const ValueKey('songs-overflow-menu'),
      useRootOverlay: true,
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(scheme.surfaceContainerHigh),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(3),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(vertical: 6),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      menuChildren: [
        for (final action in actions)
          MenuItemButton(
            leadingIcon: action.leading,
            onPressed: action.onPressed,
            child: Text(action.label),
          ),
      ],
      builder: (context, controller, child) => SizedBox.square(
        dimension: 44,
        child: IconButton(
          tooltip: '更多歌曲操作',
          onPressed: () =>
              controller.isOpen ? controller.close() : controller.open(),
          icon: const Icon(Icons.more_vert_rounded, size: 21),
          visualDensity: VisualDensity.compact,
        ),
      ),
    );
  }
}

class _SongsMenuAction {
  const _SongsMenuAction({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.loading = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool loading;

  Widget get leading => loading
      ? const SizedBox.square(
          dimension: 20,
          child: CircularProgressIndicator(strokeWidth: 2.2),
        )
      : Icon(icon, size: 20);
}

class _MorphingSongsMenu extends StatefulWidget {
  const _MorphingSongsMenu({required this.actions});

  final List<_SongsMenuAction> actions;

  @override
  State<_MorphingSongsMenu> createState() => _MorphingSongsMenuState();
}

class _MorphingSongsMenuState extends State<_MorphingSongsMenu> {
  // Keep the same morph mounted for the button, opening, menu, and closing.
  final _portal = OverlayPortalController()..show();
  LocalHistoryEntry? _historyEntry;
  bool _open = false;
  bool _wide = false;

  void _openMenu() {
    if (_open) return;
    setState(() {
      _open = true;
      _wide = true;
    });
    final route = ModalRoute.of(context);
    if (route == null) return;
    late final LocalHistoryEntry entry;
    entry = LocalHistoryEntry(
      onRemove: () {
        if (!identical(_historyEntry, entry)) return;
        _historyEntry = null;
        _closeMenu();
      },
    );
    _historyEntry = entry;
    route.addLocalHistoryEntry(entry);
  }

  void _closeMenu() {
    if (!_open) return;
    setState(() => _open = false);
    final entry = _historyEntry;
    _historyEntry = null;
    entry?.remove();
  }

  void _selectAction(_SongsMenuAction action) {
    final onPressed = action.onPressed;
    if (!_open || onPressed == null) return;
    _closeMenu();
    // An animation's spring tail must never delay the requested operation.
    onPressed();
  }

  void _onMorphEnd() {
    if (_open || !_wide) return;
    setState(() => _wide = false);
  }

  @override
  void dispose() {
    final entry = _historyEntry;
    _historyEntry = null;
    entry?.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final media = MediaQuery.of(context);
    final rowHeight = math.max(48.0, media.textScaler.scale(15) * 1.25 + 24);
    final naturalHeight = widget.actions.length * rowHeight + 12;

    return OverlayPortal.overlayChildLayoutBuilder(
      controller: _portal,
      overlayLocation: OverlayChildLocation.rootOverlay,
      child: const SizedBox.square(dimension: 44),
      overlayChildBuilder: (context, info) {
        final anchor = MatrixUtils.transformRect(
          info.childPaintTransform,
          Offset.zero & info.childSize,
        );
        final width = math.max(44.0, math.min(248.0, anchor.right - 12));
        final height = math.max(
          44.0,
          math.min(
            naturalHeight,
            info.overlaySize.height -
                anchor.top -
                media.viewPadding.bottom -
                12,
          ),
        );

        return Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: [
            if (_open)
              Positioned.fill(
                key: const ValueKey('songs-menu-barrier'),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _closeMenu,
                ),
              ),
            Positioned(
              // Adding the barrier must not re-create the morph's element.
              key: const ValueKey('songs-menu-morph-slot'),
              top: anchor.top,
              right: info.overlaySize.width - anchor.right,
              width: _wide ? width : 44,
              height: _wide ? height : 44,
              child: LiquidGlassMorph(
                key: const ValueKey('songs-menu-morph'),
                alignment: Alignment.topRight,
                motion: LiquidGlassMorphMotion.fluid,
                smoothness: 28,
                style: LiquidGlassStyle(
                  shape: LiquidGlassShape.continuousRoundedRectangle(
                    cornerRadius: _open ? 24 : 22,
                  ),
                  color: scheme.surfaceContainerHigh.withValues(alpha: 0.32),
                  blur: 4,
                  saturation: 1.2,
                ),
                onEnd: _onMorphEnd,
                child: _open
                    ? SizedBox(
                        key: const ValueKey('songs-menu-open'),
                        width: width,
                        height: height,
                        child: Material(
                          type: MaterialType.transparency,
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                for (final action in widget.actions)
                                  InkWell(
                                    onTap: action.onPressed == null
                                        ? null
                                        : () => _selectAction(action),
                                    child: SizedBox(
                                      height: rowHeight,
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                        ),
                                        child: Row(
                                          children: [
                                            action.leading,
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Text(
                                                action.label,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 15,
                                                  color:
                                                      action.onPressed == null
                                                      ? scheme.onSurface
                                                            .withValues(
                                                              alpha: 0.38,
                                                            )
                                                      : scheme.onSurface,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      )
                    : SizedBox.square(
                        key: const ValueKey('songs-menu-closed'),
                        dimension: 44,
                        child: IconButton(
                          tooltip: '更多歌曲操作',
                          onPressed: _openMenu,
                          icon: Icon(
                            Icons.more_vert_rounded,
                            size: 21,
                            color: scheme.onSurface,
                          ),
                        ),
                      ),
              ),
            ),
          ],
        );
      },
    );
  }
}
