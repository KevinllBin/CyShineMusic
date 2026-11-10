import 'lyric_font_controls.dart';
import 'settings_sheet.dart';
import 'package:flutter/material.dart';
import 'package:prism_ui/prism_ui.dart' as prism;

import '../../../core/storage/settings_store.dart';

Future<({double weight, double size})> showLyricSettingsSheet(
  BuildContext context, {
  required double weight,
  required double size,
}) async {
  var selected = (
    weight: normalizeLyricFontWeight(weight),
    size: normalizeLyricFontSize(size),
  );
  await showSettingsSheet<void>(
    context: context,
    useRootNavigator: true,

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
  final _weightKey = GlobalKey<LyricStyleControlState>();
  final _sizeKey = GlobalKey<LyricStyleControlState>();

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
    final isDefault =
        _weight == kLyricFontWeightDefault && _size == kLyricFontSizeDefault;
    return SettingsSheetLayout(
      title: '歌词界面设置',
      onClose: _finish,
      trailing: prism.TextButton.icon(
        onPressed: isDefault ? null : _reset,
        icon: const Icon(Icons.restart_alt_rounded, size: 18),
        label: const Text('重置'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: Column(
          children: [
            LyricFontPreview(weight: _weight, size: _size),
            const SizedBox(height: 16),
            prism.Card(
              inert: true,
              radius: 18,
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  LyricStyleControl(
                    key: _weightKey,
                    icon: Icons.format_bold_rounded,
                    label: '字体粗细',
                    value: _weight,
                    min: kLyricFontWeightMin,
                    max: kLyricFontWeightMax,
                    step: 100,
                    onChanged: (value) => _update(weight: value),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: prism.Divider(height: 1),
                  ),
                  LyricStyleControl(
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
          ],
        ),
      ),
      actions: [
        prism.FilledButton(onPressed: _finish, child: const Text('完成')),
      ],
    );
  }
}
