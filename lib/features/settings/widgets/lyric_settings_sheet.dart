import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/storage/settings_store.dart';
import '../../player/widgets/lyric_typography.dart';
import '../../player/widgets/player_palette.dart';

Future<({double weight, double size})> showLyricSettingsSheet(
  BuildContext context, {
  required double weight,
  required double size,
}) async {
  var selected = (
    weight: normalizeLyricFontWeight(weight),
    size: normalizeLyricFontSize(size),
  );
  await showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _LyricSettingsSheet(
      weight: selected.weight,
      size: selected.size,
      onChanged: (value) => selected = value,
    ),
  );
  return selected;
}

class _LyricSettingsSheet extends StatefulWidget {
  const _LyricSettingsSheet({
    required this.weight,
    required this.size,
    required this.onChanged,
  });

  final double weight;
  final double size;
  final ValueChanged<({double weight, double size})> onChanged;

  @override
  State<_LyricSettingsSheet> createState() => _LyricSettingsSheetState();
}

class _LyricSettingsSheetState extends State<_LyricSettingsSheet> {
  late double _weight = widget.weight;
  late double _size = widget.size;
  final _weightKey = GlobalKey<_StyleControlState>();
  final _sizeKey = GlobalKey<_StyleControlState>();

  void _update({double? weight, double? size}) {
    if (!mounted) return;
    setState(() {
      _weight = normalizeLyricFontWeight(weight ?? _weight);
      _size = normalizeLyricFontSize(size ?? _size);
    });
    widget.onChanged((weight: _weight, size: _size));
  }

  void _reset() {
    _weightKey.currentState?.setValue(kLyricFontWeightDefault);
    _sizeKey.currentState?.setValue(kLyricFontSizeDefault);
    _update(weight: kLyricFontWeightDefault, size: kLyricFontSizeDefault);
  }

  void _finish() {
    _weightKey.currentState?.commitInput();
    _sizeKey.currentState?.commitInput();
    FocusScope.of(context).unfocus();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final media = MediaQuery.of(context);
    final isDefault =
        _weight == kLyricFontWeightDefault && _size == kLyricFontSizeDefault;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: (media.size.height - media.viewInsets.bottom) * 0.9,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                fit: FlexFit.loose,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '歌词界面设置',
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: isDefault ? null : _reset,
                            icon: const Icon(
                              Icons.restart_alt_rounded,
                              size: 18,
                            ),
                            label: const Text('重置'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '调整完整歌词页的字体与阅读体验',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 18),
                      _LyricPreview(weight: _weight, size: _size),
                      const SizedBox(height: 18),
                      Container(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: scheme.outlineVariant.withValues(
                              alpha: 0.45,
                            ),
                          ),
                        ),
                        child: Column(
                          children: [
                            _StyleControl(
                              key: _weightKey,
                              icon: Icons.format_bold_rounded,
                              label: '字体粗细',
                              value: _weight,
                              min: kLyricFontWeightMin,
                              max: kLyricFontWeightMax,
                              step: 100,
                              onChanged: (value) => _update(weight: value),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Divider(
                                height: 1,
                                color: scheme.outlineVariant.withValues(
                                  alpha: 0.4,
                                ),
                              ),
                            ),
                            _StyleControl(
                              key: _sizeKey,
                              icon: Icons.format_size_rounded,
                              label: '字体大小',
                              value: _size,
                              min: kLyricFontSizeMin,
                              max: kLyricFontSizeMax,
                              step: 1,
                              onChanged: (value) => _update(size: value),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '点击数值可直接输入 · 迷你歌词保持原样',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    onPressed: _finish,
                    child: const Text('完成'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LyricPreview extends StatelessWidget {
  const _LyricPreview({required this.weight, required this.size});

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

class _StyleControl extends StatefulWidget {
  const _StyleControl({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final double value;
  final double min;
  final double max;
  final double step;
  final ValueChanged<double> onChanged;

  @override
  State<_StyleControl> createState() => _StyleControlState();
}

class _StyleControlState extends State<_StyleControl> {
  late final _controller = TextEditingController(
    text: widget.value.round().toString(),
  );
  final _focus = FocusNode();

  double _snap(double value) =>
      ((value.clamp(widget.min, widget.max) / widget.step).round() *
              widget.step)
          .clamp(widget.min, widget.max);

  @override
  void initState() {
    super.initState();
    _focus.addListener(_handleFocus);
  }

  @override
  void didUpdateWidget(covariant _StyleControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focus.hasFocus && widget.value != oldWidget.value) {
      _controller.text = widget.value.round().toString();
    }
  }

  void _handleFocus() {
    if (!_focus.hasFocus) commitInput();
  }

  void commitInput() {
    final parsed = double.tryParse(_controller.text);
    final value = _snap(parsed ?? widget.value);
    _controller.text = value.round().toString();
    if (value != widget.value) widget.onChanged(value);
  }

  void setValue(double value) {
    final next = _snap(value);
    _controller.text = next.round().toString();
    _focus.unfocus();
    widget.onChanged(next);
  }

  void _onTextChanged(String value) {
    final parsed = double.tryParse(value);
    if (parsed != null) widget.onChanged(_snap(parsed));
  }

  @override
  void dispose() {
    _focus.removeListener(_handleFocus);
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context).textTheme;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide.none,
    );
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(widget.icon, size: 18, color: scheme.primary),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          widget.label,
                          style: theme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.step == 100 ? '100–1000 · 每次 100' : '16–56 · 每次 1',
                    style: theme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 102,
              child: Semantics(
                label: widget.label,
                child: TextField(
                  controller: _controller,
                  focusNode: _focus,
                  selectAllOnFocus: true,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  style: theme.titleMedium?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                  inputFormatters: [
                    TextInputFormatter.withFunction(
                      (oldValue, newValue) =>
                          RegExp(r'^\d{0,4}$').hasMatch(newValue.text)
                          ? newValue
                          : oldValue,
                    ),
                  ],
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: scheme.surfaceContainerHighest,
                    isDense: true,
                    contentPadding: const EdgeInsets.fromLTRB(12, 12, 0, 12),
                    border: border,
                    enabledBorder: border,
                    focusedBorder: border.copyWith(
                      borderSide: BorderSide(color: scheme.primary, width: 1.5),
                    ),
                    suffixIcon: Icon(
                      Icons.edit_outlined,
                      size: 14,
                      color: scheme.onSurfaceVariant,
                    ),
                    suffixIconConstraints: const BoxConstraints(minWidth: 28),
                  ),
                  onChanged: _onTextChanged,
                  onSubmitted: (_) {
                    commitInput();
                    _focus.unfocus();
                  },
                  onTapOutside: (_) => _focus.unfocus(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            IconButton.filledTonal(
              tooltip: '减小${widget.label}',
              onPressed: widget.value <= widget.min
                  ? null
                  : () => setValue(widget.value - widget.step),
              style: IconButton.styleFrom(
                minimumSize: const Size(40, 40),
                visualDensity: VisualDensity.compact,
              ),
              icon: const Icon(Icons.remove_rounded, size: 20),
            ),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 4,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 8,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 18,
                  ),
                  activeTickMarkColor: Colors.transparent,
                  inactiveTickMarkColor: Colors.transparent,
                  showValueIndicator: ShowValueIndicator.never,
                ),
                child: Slider(
                  value: widget.value,
                  min: widget.min,
                  max: widget.max,
                  divisions: ((widget.max - widget.min) / widget.step).round(),
                  semanticFormatterCallback: (value) =>
                      value.round().toString(),
                  onChanged: setValue,
                ),
              ),
            ),
            IconButton.filledTonal(
              tooltip: '增大${widget.label}',
              onPressed: widget.value >= widget.max
                  ? null
                  : () => setValue(widget.value + widget.step),
              style: IconButton.styleFrom(
                minimumSize: const Size(40, 40),
                visualDensity: VisualDensity.compact,
              ),
              icon: const Icon(Icons.add_rounded, size: 20),
            ),
          ],
        ),
      ],
    );
  }
}
