// SPDX-License-Identifier: GPL-3.0-only
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_ui/prism_ui.dart' as prism;
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_color_swatches.dart';
import 'package:prism_ui/prism_palette.dart';

import '../../../core/storage/settings_store.dart';
import '../../../theme/color_style.dart';
import '../../../theme/dynamic_color_status.dart';
import '../../../theme/seed_palette.dart';
import 'settings_menu.dart';
import 'settings_sheet.dart';

class ThemeColorSettings extends ConsumerWidget {
  const ThemeColorSettings({super.key});

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref, {
    int? replacing,
  }) async {
    final initial = replacing == null
        ? ref.read(settingsProvider).themeSeed
        : Color(replacing);
    ModalRoute<dynamic>? route;
    final result = await showSettingsSheet<int>(
      context: context,
      showDragHandle: true,
      heightFraction: 0.9,
      maxHeight: 720,
      detents: const [0.9],
      builder: (context) {
        route = ModalRoute.of(context);
        return _ThemeColorEditor(initial: initial);
      },
    );
    if (route != null) await route!.completed;
    if (result == null || !context.mounted) return;
    await ref
        .read(settingsProvider.notifier)
        .saveThemeColor(Color(result), replacing: replacing);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final dynamicColor = ref.watch(dynamicColorStatusProvider);
    final currentStyle = switch (settings.colorStyle) {
      AppColorStyle.faithful => AppColorStyle.tinted,
      AppColorStyle.creative => AppColorStyle.vivid,
      final style => style,
    };
    final isDefault =
        !settings.useDynamicColor &&
        settings.themeSeed == SeedPalette.defaultSeed &&
        listEquals(settings.themePalette, SeedPalette.defaultColors) &&
        currentStyle == AppColorStyle.vivid;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        prism.InfoHeader(
          padding: const EdgeInsets.only(top: 24, bottom: 8),
          info: const prism.Info(label: '主题色彩', glyph: AppGlyphs.palette),
          actions: [
            if (!isDefault)
              prism.TonalButtonTheme(
                size: prism.TonalButtonSize.section,
                child: prism.ElasticPress(
                  child: prism.IconButton(
                    tooltip: '恢复默认颜色',
                    onPressed: notifier.resetThemeColors,
                    icon: const GlyphIcon(AppGlyphs.reset),
                  ),
                ),
              ),
          ],
        ),
        Padding(
          // The page already supplies Prism UI's 16dp section inset.
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 8,
            children: [
              PrismColorSwatches(
                colors: [null, ...settings.themePalette],
                selected: settings.useDynamicColor
                    ? null
                    : settings.themeSeed.toARGB32(),
                systemColor: dynamicColor.seed ?? settings.themeSeed,
                onSelect: (color) => notifier.selectThemeColor(
                  color == null ? null : Color(color),
                ),
                onEdit: (color) => _edit(context, ref, replacing: color),
                onDelete: notifier.deleteThemeColor,
                onAdd: () => _edit(context, ref),
              ),
              prism.generateGroup([
                SettingsMenuAction(
                  menuId: 'color-style-menu',
                  applyImmediately: true,
                  icon: Icons.palette_outlined,
                  showIcon: false,
                  showSubtitle: false,
                  title: '配色风格',
                  options: [
                    for (final style in AppColorStyle.choices)
                      SettingsMenuOption(
                        id: style.code,
                        label: style.label,
                        selected: currentStyle == style,
                        onSelected: () => notifier.setColorStyle(style),
                      ),
                  ],
                ),
              ]),
            ],
          ),
        ),
      ],
    );
  }
}

class _ThemeColorEditor extends StatefulWidget {
  const _ThemeColorEditor({required this.initial});
  final Color initial;

  @override
  State<_ThemeColorEditor> createState() => _ThemeColorEditorState();
}

class _ThemeColorEditorState extends State<_ThemeColorEditor> {
  late final _color = ValueNotifier(widget.initial);

  @override
  void dispose() {
    _color.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SettingsSheetLayout(
    title: '自定义颜色',
    body: ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      children: [
        ValueListenableBuilder(
          valueListenable: _color,
          builder: (_, color, _) => prism.Card(
            inert: true,
            shape: prism.AppShape.xl,
            padding: const EdgeInsets.all(12),
            child: Row(
              spacing: 16,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                Expanded(
                  child: HexColorField(
                    color: color,
                    onChanged: (value) => _color.value = value,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Palette(controller: _color),
      ],
    ),
    actions: [
      prism.TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('取消'),
      ),
      prism.FilledButton(
        onPressed: () => Navigator.of(context).pop(_color.value.toARGB32()),
        child: const Text('应用'),
      ),
    ],
  );
}
