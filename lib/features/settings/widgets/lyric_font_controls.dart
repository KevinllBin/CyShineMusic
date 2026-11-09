import 'package:flutter/material.dart';
import 'package:prism_ui/prism_ui.dart' as prism;

import '../../../core/storage/settings_store.dart';
import '../../player/widgets/lyric_typography.dart';
import '../../player/widgets/player_palette.dart';

class LyricFontPreview extends StatelessWidget {
  const LyricFontPreview({super.key, required this.weight, required this.size});

  final double weight;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final scaler = MediaQuery.textScalerOf(context);
    final secondaryWeight = lyricSecondaryFontWeight(weight);
    final height =
        scaler.scale(kLyricFontSizeMax) * 1.2 +
        scaler.scale(lyricTranslationFontSize(kLyricFontSizeMax)) * 1.3 +
        scaler.scale(12) +
        56;
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(
              scheme.primary.withValues(alpha: 0.07),
              scheme.surfaceContainerLow,
            ),
            scheme.surfaceContainerHighest.withValues(alpha: 0.65),
          ],
        ),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.09)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.graphic_eq_rounded, size: 14, color: scheme.primary),
              const SizedBox(width: 6),
              Text(
                '实时预览',
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(color: scheme.primary),
              ),
            ],
          ),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '听见热爱',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontFamilyFallback: kPlayerFontFallback,
                    fontSize: size,
                    fontWeight: FontWeight(weight.round()),
                    fontVariations: [FontVariation.weight(weight)],
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Every word matters',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: scheme.onSurface.withValues(alpha: 0.38),
                    fontFamilyFallback: kPlayerFontFallback,
                    fontSize: lyricTranslationFontSize(size),
                    fontWeight: FontWeight(secondaryWeight.round()),
                    fontVariations: [FontVariation.weight(secondaryWeight)],
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Prism UI text scaling layout: live sample, value pill and gapped Prism slider.
class LyricStyleControl extends StatefulWidget {
  const LyricStyleControl({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    this.onChanged,
    this.onChangeEnd,
  });

  final IconData icon;
  final String label;
  final double value;
  final double min;
  final double max;
  final double step;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeEnd;

  @override
  State<LyricStyleControl> createState() => LyricStyleControlState();
}

class LyricStyleControlState extends State<LyricStyleControl> {
  double? _draft;
  double get _value => _draft ?? widget.value;
  double _snap(double value) => ((value / widget.step).round() * widget.step)
      .clamp(widget.min, widget.max);

  @override
  void didUpdateWidget(covariant LyricStyleControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) _draft = null;
  }

  void commitInput() {
    if (_draft case final value?) {
      (widget.onChangeEnd ?? widget.onChanged)?.call(value);
      setState(() => _draft = null);
    }
  }

  void setValue(double value) {
    setState(() => _draft = _snap(value));
    if (widget.onChangeEnd == null) widget.onChanged?.call(_value);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = prism.Theme.of(context).colorScheme;
    final weightControl = widget.step == 100;
    final value = _value;
    final sample = weightControl
        ? TextStyle(
            fontSize: 24,
            fontWeight: FontWeight(value.round()),
            fontVariations: [FontVariation.weight(value)],
          )
        : TextStyle(fontSize: value, fontWeight: FontWeight.w200);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: MediaQuery.textScalerOf(
                      context,
                    ).scale(widget.max > 100 ? 32 : widget.max * 1.25),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '听见热爱 Aa',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: sample.copyWith(
                          color: scheme.onSurface,
                          fontFamilyFallback: kPlayerFontFallback,
                        ),
                      ),
                    ),
                  ),
                  Text(
                    widget.label,
                    style: prism.AppTextStyle.subheadline
                        .of(context)
                        .copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: ShapeDecoration(
                color: prism.SurfaceLevel.block.colorOf(scheme),
                shape: prism.AppShape.full,
              ),
              child: Text(
                value.round().toString(),
                style: prism.AppTextStyle.subheadline
                    .of(context, emphasized: true)
                    .copyWith(
                      color: scheme.onSurfaceVariant,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        MediaQuery.withNoTextScaling(
          child: Row(
            spacing: 12,
            children: [
              ExcludeSemantics(
                child: Text(
                  'A',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w200,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              Expanded(
                child: Semantics(
                  label: widget.label,
                  child: prism.Slider(
                    min: widget.min,
                    max: widget.max,
                    divisions: ((widget.max - widget.min) / widget.step)
                        .round(),
                    value: value.clamp(widget.min, widget.max),
                    label: value.round().toString(),
                    onChanged: setValue,
                    onChangeEnd: (_) => commitInput(),
                  ),
                ),
              ),
              ExcludeSemantics(
                child: Text(
                  'A',
                  style: TextStyle(
                    fontSize: weightControl ? 22 : 26,
                    fontWeight: weightControl
                        ? FontWeight.w900
                        : FontWeight.w400,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
