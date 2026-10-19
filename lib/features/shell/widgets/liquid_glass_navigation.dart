import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';

import '../../search/search_toolbar_state.dart';
import '../../settings/widgets/color_style_row.dart';
import '../../songs/songs_toolbar_state.dart';
import '../shell_navigation.dart';
import 'toolbar_metrics.dart';

/// A tab capsule with a page-specific action, within the existing dual layout.
class LiquidGlassNavigation extends ConsumerWidget {
  const LiquidGlassNavigation({
    super.key,
    required this.location,
    required this.routeLocation,
    required this.width,
    required this.height,
  });

  final String location;
  final String routeLocation;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final viewport = MediaQuery.sizeOf(context);
    final selectedIndex = switch (toolbarIndexFor(location)) {
      1 => 1,
      3 => 2,
      _ => 0,
    };
    const gap = 10.0;
    final discoveryPage = location == '/';
    final songsPage = location == '/songs';
    final settingsPage = location == '/settings';
    final showAction = discoveryPage || songsPage || settingsPage;
    final barWidth = showAction ? width - height - gap : width;
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    VoidCallback? onAction;
    if (discoveryPage) {
      onAction = ref.watch(
        searchToolbarStateProvider.select((state) => state.onSearch),
      );
    } else if (songsPage) {
      final (hasSongs, shuffle) = ref.watch(
        songsToolbarStateProvider.select(
          (state) => (state.hasSongs, state.onShuffle),
        ),
      );
      onAction = hasSongs ? shuffle : null;
    } else if (settingsPage) {
      onAction = () => showColorStyleSheet(context);
    }

    return SizedBox(
      key: const ValueKey('liquid-glass-navigation'),
      width: width,
      height: height,
      child: Row(
        children: [
          SizedBox(
            width: barWidth,
            height: height,
            // This row's outer SafeArea already consumes the system inset.
            child: MediaQuery.removePadding(
              context: context,
              removeTop: true,
              removeBottom: true,
              child: LiquidGlassTabBar(
                width: barWidth,
                height: height,
                margin: EdgeInsets.zero,
                selectedIndex: selectedIndex,
                onChanged: (index) => navigateToShellTab(
                  context,
                  ref,
                  location,
                  routeLocation,
                  const ['/', '/songs', '/settings'][index],
                ),
                itemStyle: LiquidGlassTabItemStyle(
                  selectedColor: scheme.primary,
                  unselectedColor: scheme.onSurface,
                  iconSize: toolbarIconSizeFor(viewport),
                  labelFontSize: toolbarLabelFontSizeFor(viewport),
                ),
                pillStyle: LiquidGlassTabPillStyle(
                  mode: disableAnimations
                      ? LiquidGlassPillMode.none
                      : LiquidGlassPillMode.impellerOnly,
                  animated: !disableAnimations,
                ),
                items: const [
                  LiquidGlassTabBarItem(
                    icon: Icons.explore_rounded,
                    label: '发现',
                  ),
                  LiquidGlassTabBarItem(
                    icon: Icons.library_music_rounded,
                    label: '歌曲',
                  ),
                  LiquidGlassTabBarItem(icon: Icons.tune_rounded, label: '设置'),
                ],
              ),
            ),
          ),
          if (showAction) ...[
            const SizedBox(width: gap),
            Opacity(
              opacity: onAction == null ? 0.38 : 1,
              child: LiquidGlassFab(
                key: ValueKey(
                  discoveryPage
                      ? 'liquid-glass-online-search'
                      : settingsPage
                      ? 'liquid-glass-color-style'
                      : 'liquid-glass-shuffle',
                ),
                size: height,
                icon: discoveryPage
                    ? Icons.search_rounded
                    : settingsPage
                    ? Icons.palette_outlined
                    : Icons.shuffle_rounded,
                foregroundColor: scheme.onSurface,
                tooltip: discoveryPage
                    ? '搜索在线歌曲'
                    : settingsPage
                    ? '切换配色风格'
                    : '随机播放一首',
                onPressed: onAction,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
