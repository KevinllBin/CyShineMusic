import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_ui/prism_ui.dart' as prism;
import 'package:prism_ui/icons/icons.dart';

import '../../../core/storage/settings_store.dart';
import 'lyric_font_controls.dart';
import 'settings_action.dart';

class LyricsAppearanceSettings extends ConsumerWidget {
  const LyricsAppearanceSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final typography = ref.watch(
      settingsProvider.select(
        (settings) =>
            (weight: settings.lyricFontWeight, size: settings.lyricFontSize),
      ),
    );
    final notifier = ref.read(settingsProvider.notifier);
    final isDefault =
        typography.weight == kLyricFontWeightDefault &&
        typography.size == kLyricFontSizeDefault;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        prism.ListHeader(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          title: '歌词界面设置',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!isDefault)
                prism.TonalButtonTheme(
                  size: prism.TonalButtonSize.section,
                  child: prism.IconButton(
                    tooltip: '恢复默认字体',
                    icon: const GlyphIcon(AppGlyphs.reset),
                    onPressed: () {
                      FocusManager.instance.primaryFocus?.unfocus();
                      notifier.setLyricFontStyle(
                        weight: kLyricFontWeightDefault,
                        size: kLyricFontSizeDefault,
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        SettingsGroup(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  LyricStyleControl(
                    key: const ValueKey('appearance-lyric-weight'),
                    icon: Icons.format_bold_rounded,
                    label: '字体粗细',
                    value: typography.weight,
                    min: kLyricFontWeightMin,
                    max: kLyricFontWeightMax,
                    step: 100,
                    onChangeEnd: (value) => notifier.setLyricFontStyle(
                      weight: value,
                      size: ref.read(settingsProvider).lyricFontSize,
                    ),
                  ),
                  const Divider(height: 24),
                  LyricStyleControl(
                    key: const ValueKey('appearance-lyric-size'),
                    icon: Icons.format_size_rounded,
                    label: '字体大小',
                    value: typography.size,
                    min: kLyricFontSizeMin,
                    max: kLyricFontSizeMax,
                    step: 1,
                    onChangeEnd: (value) => notifier.setLyricFontStyle(
                      weight: ref.read(settingsProvider).lyricFontWeight,
                      size: value,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}
