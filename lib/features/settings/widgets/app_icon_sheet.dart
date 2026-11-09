import 'package:flutter/material.dart';
import 'package:prism_ui/prism_ui.dart' as prism;
import 'package:prism_ui/icons/icons.dart';

import '../../../core/services/app_icon_service.dart';
import 'settings_sheet.dart';

Future<AppIconVariant?> showAppIconSheet(
  BuildContext context,
  AppIconVariant current,
) => showSettingsSheet<AppIconVariant>(
  context: context,
  heightFraction: 0.62,
  maxHeight: 400,
  builder: (_) => _AppIconSheet(current: current),
);

class _AppIconSheet extends StatefulWidget {
  const _AppIconSheet({required this.current});
  final AppIconVariant current;

  @override
  State<_AppIconSheet> createState() => _AppIconSheetState();
}

class _AppIconSheetState extends State<_AppIconSheet> {
  late AppIconVariant _selected = widget.current;

  @override
  Widget build(BuildContext context) => SettingsSheetLayout(
    title: '应用图标',
    body: GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 150,
        mainAxisExtent: 112,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: AppIconVariant.values.length,
      itemBuilder: (_, index) {
        final icon = AppIconVariant.values[index];
        final selected = _selected == icon;
        final scheme = prism.Theme.of(context).colorScheme;
        return Semantics(
          selected: selected,
          label: icon.label,
          child: prism.Card(
            isSelected: selected,
            shape: prism.AppShape.all(18).copyWith(
              side: selected
                  ? BorderSide(color: scheme.primary, width: 2)
                  : BorderSide.none,
            ),
            onPressed: () => setState(() => _selected = icon),
            child: Stack(
              children: [
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ClipRSuperellipse(
                        borderRadius: BorderRadius.circular(14),
                        child: Image.asset(
                          icon.previewAsset,
                          width: 60,
                          height: 60,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        icon.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: prism.AppTextStyle.footnote
                            .of(context)
                            .copyWith(
                              color: selected
                                  ? scheme.primary
                                  : scheme.onSurface,
                            ),
                      ),
                    ],
                  ),
                ),
                if (selected)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: GlyphIcon(
                      Glyphs.check,
                      size: 16,
                      color: scheme.primary,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    ),
    actions: [
      prism.FilledButton(
        onPressed: _selected == widget.current
            ? null
            : () => Navigator.of(context).pop(_selected),
        child: const Text('应用图标'),
      ),
    ],
  );
}
