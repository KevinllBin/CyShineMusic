import 'package:flutter/material.dart';

import '../../../core/services/app_icon_service.dart';

Future<AppIconVariant?> showAppIconSheet(
  BuildContext context,
  AppIconVariant current,
) {
  return showModalBottomSheet<AppIconVariant>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _AppIconSheet(current: current),
  );
}

class _AppIconSheet extends StatefulWidget {
  const _AppIconSheet({required this.current});

  final AppIconVariant current;

  @override
  State<_AppIconSheet> createState() => _AppIconSheetState();
}

class _AppIconSheetState extends State<_AppIconSheet> {
  late AppIconVariant _selected = widget.current;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('应用图标', style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                '选一个喜欢的桌面图标，随时可以切回经典白。',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 3,
                crossAxisSpacing: 10,
                mainAxisSpacing: 12,
                childAspectRatio: 0.82,
                children: [
                  for (final icon in AppIconVariant.values)
                    _IconOption(
                      icon: icon,
                      selected: _selected == icon,
                      onTap: () => setState(() => _selected = icon),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                '桌面可能需要稍等片刻才会刷新。开启系统主题图标时，颜色可能跟随壁纸。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _selected == widget.current
                    ? null
                    : () => Navigator.of(context).pop(_selected),
                child: const Text('应用图标'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IconOption extends StatelessWidget {
  const _IconOption({
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final AppIconVariant icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      selected: selected,
      child: Material(
        color: selected
            ? scheme.primaryContainer.withValues(alpha: 0.55)
            : scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: Column(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Image.asset(icon.previewAsset, fit: BoxFit.contain),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        icon.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: selected ? scheme.primary : scheme.onSurface,
                          fontSize: 13,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                    if (selected) ...[
                      const SizedBox(width: 3),
                      Icon(
                        Icons.check_circle_rounded,
                        size: 15,
                        color: scheme.primary,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
