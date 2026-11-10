import 'package:flutter/material.dart';
import 'package:prism_ui/prism_ui.dart' as prism;

import '../../models/enums.dart';
import '../../models/music_info.dart';

class QualityOptionTile extends StatelessWidget {
  const QualityOptionTile({
    super.key,
    required this.option,
    required this.selected,
    required this.onPressed,
    this.showSelection = true,
  });

  final QualityOption option;
  final bool selected;
  final bool showSelection;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final size = option.size?.trim();
    final colors = prism.Theme.of(context).colorScheme;
    return prism.DecorationListItem(
      isSelected: selected,
      onPressed: onPressed,
      title: Text(qualityName(option.type)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 10,
        children: [
          if (size != null && size.isNotEmpty)
            Text(
              size,
              style: prism.AppTextStyle.subheadline
                  .of(context)
                  .copyWith(color: colors.onSurfaceVariant),
            ),
          if (showSelection)
            selected
                ? const prism.SelectionCheck()
                : const SizedBox.square(dimension: prism.SelectionCheck.size),
        ],
      ),
    );
  }
}

String qualityName(Quality quality) => switch (quality) {
  Quality.master => '母带音质',
  Quality.atmosPlus => 'Atmos Plus',
  Quality.atmos => '杜比全景声',
  Quality.hires => 'Hi-Res',
  Quality.flac24bit => '24-bit FLAC',
  Quality.flac => '无损 FLAC',
  Quality.wav => 'WAV',
  Quality.ape => 'APE',
  Quality.k320 => '高品质 320K',
  Quality.k192 => '较高品质 192K',
  Quality.k128 => '标准品质 128K',
};
