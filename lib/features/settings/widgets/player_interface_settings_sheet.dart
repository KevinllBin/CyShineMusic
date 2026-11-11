import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/settings_store.dart';
import 'lyric_settings_sheet.dart';
import 'settings_action.dart';

Future<void> showPlayerInterfaceSettingsSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _PlayerInterfaceSettingsSheet(),
    );

class _PlayerInterfaceSettingsSheet extends ConsumerWidget {
  const _PlayerInterfaceSettingsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('播放界面设置', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              SettingsSwitchAction(
                key: const ValueKey('lyric-view-blur-disabled-setting'),
                icon: Icons.blur_off_rounded,
                title: '关闭歌词视图模糊',
                subtitle: settings.lyricViewBlurDisabled
                    ? '所有歌词清晰显示'
                    : '保留歌词远近模糊效果',
                value: settings.lyricViewBlurDisabled,
                onChanged: notifier.setLyricViewBlurDisabled,
              ),
              SettingsSwitchAction(
                key: const ValueKey('square-album-cover-setting'),
                icon: Icons.crop_square_rounded,
                title: '方形专辑封面',
                subtitle: settings.squareAlbumCoverEnabled
                    ? '使用静止的方形封面'
                    : '使用随播放旋转的圆形封面',
                value: settings.squareAlbumCoverEnabled,
                onChanged: notifier.setSquareAlbumCoverEnabled,
              ),
              SettingsAction(
                key: const ValueKey('lyric-interface-setting'),
                icon: Icons.lyrics_outlined,
                title: '歌词界面设置',
                subtitle:
                    '粗细 ${settings.lyricFontWeight.round()} · 大小 ${settings.lyricFontSize.round()}',
                trailing: Icons.chevron_right_rounded,
                onTap: () async {
                  final selected = await showLyricSettingsSheet(
                    context,
                    weight: settings.lyricFontWeight,
                    size: settings.lyricFontSize,
                  );
                  await notifier.setLyricFontStyle(
                    weight: selected.weight,
                    size: selected.size,
                  );
                },
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('完成'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
