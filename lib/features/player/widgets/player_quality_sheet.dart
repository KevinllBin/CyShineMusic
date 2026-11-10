import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_ui/prism_ui.dart' as prism;

import '../../../core/models/enums.dart';
import '../../../core/models/music_info.dart';
import '../../../core/ui/app_sheet.dart';
import '../../../core/ui/app_toast.dart';
import '../../../core/ui/widgets/quality_option_tile.dart';
import '../player_controller.dart';

List<QualityOption> availablePlaybackQualityOptions(PlayerTrack track) {
  final parsedCurrent = Quality.tryFromCode(track.qualityLabel);
  final allOptions = track.availableQualityOptions.isEmpty
      ? [
          for (final quality
              in track.availableQualities.isEmpty
                  ? [?parsedCurrent]
                  : track.availableQualities)
            QualityOption(type: quality),
        ]
      : track.availableQualityOptions;
  return [
    for (final option in allOptions)
      if (_knownQualitySize(option) != null) option,
  ];
}

String playerQualityLabel(PlayerTrack track) {
  final quality = Quality.tryFromCode(track.qualityLabel);
  return switch (quality) {
    Quality.atmosPlus => 'Atmos+',
    Quality.flac24bit => '24-bit FLAC',
    null => track.qualityLabel,
    _ => qualityName(quality),
  };
}

Future<void> showPlaybackQualitySheet(
  BuildContext context,
  WidgetRef ref, {
  required PlayerTrack track,
}) async {
  final options = availablePlaybackQualityOptions(track);
  final current = Quality.tryFromCode(track.qualityLabel);
  if (track.isLocal || options.length < 2) return;
  final container = ProviderScope.containerOf(context, listen: false);
  final controller = ref.read(playerControllerProvider.notifier);
  final selected = await showAppSheet<Quality>(
    context: context,
    detents: prism.snapSheetDetents,
    neutralSurface: true,
    fitsContent: true,
    builder: (_) => _PlaybackQualitySheet(options: options, current: current),
  );
  if (selected == null || selected == current || !controller.mounted) return;
  if (container.read(playerControllerProvider).track?.id != track.id) {
    if (context.mounted) {
      showAppToast(context, '当前歌曲已变化，请重新选择音质');
    }
    return;
  }
  await controller.switchQuality(selected);
}

class _PlaybackQualitySheet extends StatelessWidget {
  const _PlaybackQualitySheet({required this.options, required this.current});

  final List<QualityOption> options;
  final Quality? current;

  @override
  Widget build(BuildContext context) => AppSheetLayout(
    key: const ValueKey('player-quality-sheet'),
    title: '播放音质',
    centerTitle: true,
    body: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          prism.generateGroup([
            for (final option in options)
              QualityOptionTile(
                key: ValueKey('player-quality-option-${option.type.code}'),
                option: option,
                selected: option.type == current,
                onPressed: () => Navigator.of(context).pop(option.type),
              ),
          ]),
          const prism.ListFooter(text: '切换后保留当前播放进度。'),
        ],
      ),
    ),
  );
}

String? _knownQualitySize(QualityOption option) {
  final size = option.size?.trim();
  return size == null || size.isEmpty ? null : size;
}
