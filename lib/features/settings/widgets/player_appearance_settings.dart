import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_ui/prism_ui.dart' as prism;
import 'package:prism_ui/icons/prism_glyphs.dart';

import '../../../core/storage/settings_store.dart';
import 'lyrics_appearance_settings.dart';
import 'settings_action.dart';

/// Player options and their lyric typography subsection, expanded on Appearance.
class PlayerAppearanceSettings extends ConsumerWidget {
  const PlayerAppearanceSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final options = ref.watch(
      settingsProvider.select(
        (settings) => (
          blurDisabled: settings.lyricViewBlurDisabled,
          squareCover: settings.squareAlbumCoverEnabled,
        ),
      ),
    );
    final notifier = ref.read(settingsProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const prism.InfoHeader(
          padding: EdgeInsets.only(top: 24, bottom: 8),
          info: prism.Info(label: '播放界面设置', glyph: AppGlyphs.devices),
        ),
        SettingsGroup(
          children: [
            SettingsSwitchAction(
              key: const ValueKey('lyric-view-blur-disabled-setting'),
              icon: Icons.blur_off_rounded,
              title: '关闭歌词视图模糊',
              value: options.blurDisabled,
              onChanged: notifier.setLyricViewBlurDisabled,
            ),
            SettingsSwitchAction(
              key: const ValueKey('square-album-cover-setting'),
              icon: Icons.crop_square_rounded,
              title: '方形专辑封面',
              value: options.squareCover,
              onChanged: notifier.setSquareAlbumCoverEnabled,
            ),
          ],
        ),
        const LyricsAppearanceSettings(),
      ],
    );
  }
}
