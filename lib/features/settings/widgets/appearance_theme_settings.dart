import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/settings_store.dart';
import '../../../theme/liquid_glass_mode.dart';
import 'settings_action.dart';
import 'settings_menu.dart';
import 'theme_color_settings.dart';

class AppearanceThemeSettings extends ConsumerWidget {
  const AppearanceThemeSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsCard(
          title: '主题',
          children: [
            SettingsMenuAction(
              menuId: 'theme-mode-menu',
              applyImmediately: true,
              showSubtitle: false,
              icon: Icons.dark_mode_outlined,
              title: '主题模式',
              options: [
                for (final item in const {
                  ThemeMode.system: '跟随系统',
                  ThemeMode.light: '浅色',
                  ThemeMode.dark: '深色',
                }.entries)
                  SettingsMenuOption(
                    id: item.key.name,
                    label: item.value,
                    selected: settings.themeMode == item.key,
                    onSelected: () => notifier.setThemeMode(item.key),
                  ),
              ],
            ),
            SettingsSwitchAction(
              icon: Icons.auto_awesome_outlined,
              title: '动态取色',
              value: settings.useDynamicColor,
              onChanged: notifier.setUseDynamicColor,
            ),
          ],
        ),
        const ThemeColorSettings(),
        SettingsCard(
          title: '材质',
          children: [
            SettingsMenuAction(
              key: const ValueKey('liquid-glass-menu'),
              menuId: 'liquid-glass-menu',
              applyImmediately: true,
              icon: Icons.blur_on_rounded,
              title: '液态玻璃',
              options: [
                for (final mode in LiquidGlassMode.values)
                  SettingsMenuOption(
                    id: mode.code,
                    label: mode.label,
                    selected: settings.liquidGlassMode == mode,
                    onSelected: () => notifier.setLiquidGlassMode(mode),
                  ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}
