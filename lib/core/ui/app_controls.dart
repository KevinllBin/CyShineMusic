import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';

import '../storage/settings_store.dart';

class AppSwitch extends ConsumerWidget {
  const AppSwitch({super.key, required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final glass = ref.watch(
      settingsProvider.select((settings) => settings.liquidGlassEnabled),
    );
    if (!glass) return Switch(value: value, onChanged: onChanged);
    return Semantics(
      toggled: value,
      enabled: onChanged != null,
      onTap: onChanged == null ? null : () => onChanged!(!value),
      child: ExcludeSemantics(
        child: IgnorePointer(
          ignoring: onChanged == null,
          child: Opacity(
            opacity: onChanged == null ? 0.38 : 1,
            child: SizedBox(
              width: 64,
              height: 48,
              child: Center(
                child: LiquidGlassSwitch(
                  activeColor: Theme.of(context).colorScheme.primary,
                  inactiveColor: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.22),
                  value: value,
                  onChanged: (next) => onChanged?.call(next),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AppSwitchListTile extends ConsumerWidget {
  const AppSwitchListTile({
    super.key,
    required this.value,
    required this.onChanged,
    this.title,
    this.subtitle,
    this.contentPadding,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final Widget? title;
  final Widget? subtitle;
  final EdgeInsetsGeometry? contentPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final glass = ref.watch(
      settingsProvider.select((settings) => settings.liquidGlassEnabled),
    );
    if (!glass) {
      return SwitchListTile(
        value: value,
        onChanged: onChanged,
        title: title,
        subtitle: subtitle,
        contentPadding: contentPadding,
      );
    }
    return MergeSemantics(
      child: ListTile(
        title: title,
        subtitle: subtitle,
        contentPadding: contentPadding,
        enabled: onChanged != null,
        onTap: onChanged == null ? null : () => onChanged!(!value),
        trailing: AppSwitch(value: value, onChanged: onChanged),
      ),
    );
  }
}

class AppSlider extends ConsumerWidget {
  const AppSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 1,
    this.divisions,
    this.label,
    this.onChangeStart,
    this.onChangeEnd,
    this.semanticFormatterCallback,
    this.padding,
  });

  final double value;
  final double min;
  final double max;
  final int? divisions;
  final String? label;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeStart;
  final ValueChanged<double>? onChangeEnd;
  final SemanticFormatterCallback? semanticFormatterCallback;
  final EdgeInsetsGeometry? padding;

  double _snap(double next) {
    if (divisions == null || divisions! <= 0 || max <= min) return next;
    return min +
        ((next - min) / (max - min) * divisions!).round() *
            (max - min) /
            divisions!;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final glass = ref.watch(
      settingsProvider.select((settings) => settings.liquidGlassEnabled),
    );
    if (!glass) {
      return Slider(
        value: value,
        min: min,
        max: max,
        divisions: divisions,
        label: label,
        padding: padding,
        onChanged: onChanged,
        onChangeStart: onChangeStart,
        onChangeEnd: onChangeEnd,
        semanticFormatterCallback: semanticFormatterCallback,
      );
    }
    final scheme = Theme.of(context).colorScheme;
    final theme = SliderTheme.of(context);
    final enabled = onChanged != null && max > min;
    final step = (max - min) / (divisions ?? 20);
    return Semantics(
      slider: true,
      enabled: enabled,
      value:
          semanticFormatterCallback?.call(value) ??
          label ??
          '${(max <= min ? 0 : (value - min) / (max - min) * 100).round()}%',
      onIncrease: !enabled
          ? null
          : () {
              final next = _snap((value + step).clamp(min, max));
              onChangeStart?.call(value);
              onChanged?.call(next);
              onChangeEnd?.call(next);
            },
      onDecrease: !enabled
          ? null
          : () {
              final next = _snap((value - step).clamp(min, max));
              onChangeStart?.call(value);
              onChanged?.call(next);
              onChangeEnd?.call(next);
            },
      child: ExcludeSemantics(
        child: IgnorePointer(
          ignoring: !enabled,
          child: Padding(
            padding: padding ?? EdgeInsets.zero,
            child: LayoutBuilder(
              builder: (context, constraints) => LiquidGlassSlider(
                width: constraints.hasBoundedWidth ? constraints.maxWidth : 280,
                value: value.clamp(min, max),
                minimumValue: min,
                maximumValue: max > min ? max : min + 1,
                // Keep all three callbacks distinct: seek commits on end,
                // whereas EQ and settings update continuously on changed.
                onChangeStart: enabled && onChangeStart != null
                    ? (next) => onChangeStart!(_snap(next))
                    : null,
                onChanged: (next) => onChanged?.call(_snap(next)),
                onChangeEnd: enabled && onChangeEnd != null
                    ? (next) => onChangeEnd!(_snap(next))
                    : null,
                activeColor: theme.activeTrackColor ?? scheme.primary,
                inactiveColor:
                    theme.inactiveTrackColor ??
                    scheme.onSurface.withValues(alpha: 0.18),
                thumbColor: theme.thumbColor ?? scheme.primary,
                layout: const LiquidGlassSliderLayout(
                  trackHeight: 4,
                  thumbWidth: 24,
                  thumbHeight: 16,
                  liftedThumbWidth: 38,
                  liftedThumbHeight: 24,
                  height: 28,
                ),
                motion: const LiquidGlassLensMotionSpec(maxDeformation: 0.10),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
