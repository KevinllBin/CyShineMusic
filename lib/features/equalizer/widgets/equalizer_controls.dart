import 'package:flutter/material.dart';
import 'package:prism_ui/prism_ui.dart' as prism;
import 'package:prism_ui/icons/icons.dart';

import '../../settings/widgets/settings_action.dart';
import '../equalizer_store.dart';

class EqualizerValueSlider extends StatelessWidget {
  const EqualizerValueSlider({
    super.key,
    required this.label,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.onReset,
  });

  final String label;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(fontSize: 15))),
            const SizedBox(width: 8),
            Text(
              valueLabel,
              style: TextStyle(
                color: scheme.primary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 4),
            prism.IconButton(
              tooltip: '重置$label',
              onPressed: onReset,
              icon: const GlyphIcon(AppGlyphs.reset, size: 18),
            ),
          ],
        ),
        Semantics(
          label: label,
          child: prism.Slider(
            value: value,
            min: min,
            max: max,
            label: valueLabel,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

class EqualizerBandsSection extends StatelessWidget {
  const EqualizerBandsSection({
    super.key,
    required this.bands,
    required this.onAdd,
    required this.onEdit,
    required this.onGainChanged,
  });

  final List<EqualizerBandSetting> bands;
  final VoidCallback onAdd;
  final ValueChanged<EqualizerBandSetting> onEdit;
  final void Function(String id, double value) onGainChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        prism.ListHeader(
          title: '滤波频段 · ${bands.length}/$equalizerMaxBands',
          trailing: prism.TextButton.icon(
            onPressed: bands.length < equalizerMaxBands ? onAdd : null,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('添加'),
          ),
        ),
        SettingsGroup(
          children: [
            if (bands.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 28,
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GlyphIcon(
                        AppGlyphs.sliders,
                        size: 30,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 12),
                      const Text('暂无滤波频段', style: TextStyle(fontSize: 15)),
                      const SizedBox(height: 6),
                      Text(
                        '选择声音预设，或添加频段自行调节',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              SingleChildScrollView(
                key: const PageStorageKey('equalizer-bands-scroll'),
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(12, 20, 12, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final band in bands)
                      _BandSlider(
                        key: ValueKey(band.id),
                        band: band,
                        onChanged: (value) => onGainChanged(band.id, value),
                        onEdit: () => onEdit(band),
                      ),
                  ],
                ),
              ),
          ],
        ),
        if (bands.isNotEmpty)
          const prism.ListFooter(text: '上下拖动调节增益，左右滑动查看更多频段。'),
      ],
    );
  }
}

class _BandSlider extends StatelessWidget {
  const _BandSlider({
    super.key,
    required this.band,
    required this.onChanged,
    required this.onEdit,
  });

  final EqualizerBandSetting band;
  final ValueChanged<double> onChanged;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final frequency = equalizerFrequencyLabel(band.frequencyHz);
    final valueColor = band.enabled ? scheme.primary : scheme.onSurfaceVariant;
    return SizedBox(
      width: MediaQuery.textScalerOf(context).scale(80).clamp(80, 144),
      child: Column(
        children: [
          Text(
            !band.enabled
                ? '停用'
                : band.filter.usesGain
                ? equalizerDbLabel(band.gainDb)
                : band.filter.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: valueColor,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 8),
          Semantics(
            label: '$frequency 频段增益',
            child: SizedBox(
              width: 48,
              height: 164,
              child: RotatedBox(
                quarterTurns: 3,
                child: prism.Slider(
                  value: band.filter.usesGain ? band.gainDb : 0,
                  min: equalizerMinGainDb,
                  max: equalizerMaxGainDb,
                  onChanged: band.enabled && band.filter.usesGain
                      ? onChanged
                      : null,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            frequency,
            style: TextStyle(
              fontSize: 12,
              color: scheme.onSurfaceVariant,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          prism.IconButton(
            tooltip: '编辑 $frequency 频段',
            icon: const GlyphIcon(AppGlyphs.sliders, size: 18),
            onPressed: onEdit,
          ),
        ],
      ),
    );
  }
}

String equalizerDbLabel(double value) =>
    '${value >= 0 ? '+' : ''}${value.toStringAsFixed(1)} dB';

String equalizerFrequencyLabel(double value) {
  if (value >= 1000) {
    final kilo = value / 1000;
    return '${kilo >= 10 ? kilo.toStringAsFixed(0) : kilo.toStringAsFixed(1)} kHz';
  }
  return '${value.toStringAsFixed(0)} Hz';
}
