import 'package:flutter/material.dart';

import '../../../theme/app_motion.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/color_style.dart';
import 'settings_style.dart';

typedef _PreviewKey = ({int seed, Brightness brightness, AppColorStyle style});

/// 每个风格的预览都要把种子色完整展开一次，而 `ColorScheme.fromSeed` 内部是
/// HCT 量化；4 个风格逐帧重算会掉帧，所以按 (种子, 亮度, 风格) 缓存。
const int _previewCacheLimit = 32;
final Map<_PreviewKey, ColorScheme> _previewSchemes = {};

ColorScheme _previewScheme(
  Color seed,
  Brightness brightness,
  AppColorStyle style,
) {
  final key = (seed: seed.toARGB32(), brightness: brightness, style: style);
  final cached = _previewSchemes[key];
  if (cached != null) return cached;
  if (_previewSchemes.length >= _previewCacheLimit) {
    _previewSchemes.remove(_previewSchemes.keys.first);
  }
  final scheme = AppTheme.schemeFor(seed, brightness, style);
  _previewSchemes[key] = scheme;
  return scheme;
}

class ColorStyleRow extends StatelessWidget {
  const ColorStyleRow({
    super.key,
    required this.value,
    required this.seed,
    required this.onPick,
    this.enabled = true,
  });

  final AppColorStyle value;
  final Color seed;
  final ValueChanged<AppColorStyle> onPick;

  /// Material You 动态色接管配色时，种子色和风格都不参与生成，此时整行置灰。
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const SettingsSymbolBubble(icon: Icons.gradient_outlined),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '配色风格',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: scheme.onSurface,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      height: 1.16,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    enabled ? value.description : '动态色开启时由系统配色接管',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: scheme.outline,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Opacity(
          opacity: enabled ? 1 : 0.45,
          child: IgnorePointer(
            ignoring: !enabled,
            child: Row(
              children: [
                for (final style in AppColorStyle.values) ...[
                  if (style != AppColorStyle.values.first)
                    const SizedBox(width: 8),
                  Expanded(
                    child: _StyleCard(
                      style: style,
                      seed: seed,
                      selected: style == value,
                      onTap: () => onPick(style),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _StyleCard extends StatelessWidget {
  const _StyleCard({
    required this.style,
    required this.seed,
    required this.selected,
    required this.onTap,
  });

  final AppColorStyle style;
  final Color seed;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final preview = _previewScheme(seed, scheme.brightness, style);

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      overlayColor: choiceOverlay(scheme),
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: AppMotion.medium,
            curve: AppMotion.emphasized,
            height: 46,
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: preview.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? scheme.primary : scheme.outlineVariant,
                width: selected ? 2 : 1,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: preview.primary,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _PreviewBar(color: preview.secondaryContainer),
                      const SizedBox(height: 4),
                      _PreviewBar(color: preview.tertiaryContainer),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            style.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: selected ? scheme.primary : scheme.outline,
              fontSize: 11,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewBar extends StatelessWidget {
  const _PreviewBar({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 6,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }
}
