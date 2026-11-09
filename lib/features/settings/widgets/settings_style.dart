import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:prism_ui/icons/icons.dart';

Color selectedFill(ColorScheme scheme) => scheme.secondaryContainer;

Color selectedOnFill(ColorScheme scheme) => scheme.onSecondaryContainer;

Color choiceFill(ColorScheme scheme, bool selected) => selected
    ? selectedFill(scheme)
    : scheme.surfaceContainerHighest.withValues(alpha: 0.44);

WidgetStateProperty<Color?> choiceOverlay(ColorScheme scheme) {
  return WidgetStateProperty.resolveWith((states) {
    if (states.contains(WidgetState.pressed)) {
      return scheme.secondaryContainer.withValues(alpha: 0.30);
    }
    if (states.contains(WidgetState.hovered) ||
        states.contains(WidgetState.focused)) {
      return scheme.secondaryContainer.withValues(alpha: 0.22);
    }
    return null;
  });
}

class SettingsSymbolBubble extends StatelessWidget {
  const SettingsSymbolBubble({super.key, required this.icon});
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    final shape = switch (icon) {
      Icons.cloud_outlined || Icons.cable_rounded => AppGlyphs.proxies,
      Icons.cloud_sync_outlined => AppGlyphs.cloudSync,
      Icons.palette_outlined => AppGlyphs.paintbrush,
      Icons.info_outline_rounded => AppGlyphs.info,
      Icons.bug_report_outlined => AppGlyphs.cpu,
      Icons.folder_shared_outlined ||
      Icons.folder_outlined => AppGlyphs.resources,
      Icons.terminal_rounded => AppGlyphs.logs,
      Icons.timer_outlined => AppGlyphs.clock,
      Icons.manage_search_rounded => Glyphs.search,
      Icons.graphic_eq_rounded => AppGlyphs.sliders,
      Icons.view_day_outlined => AppGlyphs.layers,
      Icons.auto_awesome_outlined ||
      Icons.auto_awesome_rounded => AppGlyphs.sparkle,
      Icons.apps_rounded => AppGlyphs.iconTile,
      Icons.display_settings_rounded => AppGlyphs.devices,
      Icons.system_update_alt_rounded => AppGlyphs.cloudDownload,
      Icons.format_size_rounded => AppGlyphs.textSize,
      Icons.blur_on_rounded || Icons.blur_off_rounded => AppGlyphs.blur,
      Icons.gradient_outlined => AppGlyphs.palette,
      Icons.dark_mode_outlined => AppGlyphs.pureBlack,
      Icons.explore_outlined => AppGlyphs.proxies,
      _ => null,
    };
    return SizedBox(
      width: 24,
      height: 28,
      child: Center(
        child: shape != null
            ? GlyphIcon(shape, size: 20, color: color)
            : icon.fontFamily?.startsWith('MaterialSymbols') == true
            ? VariedIcon.varied(icon, size: 20, weight: 300, color: color)
            : Icon(icon, size: 20, color: color),
      ),
    );
  }
}
