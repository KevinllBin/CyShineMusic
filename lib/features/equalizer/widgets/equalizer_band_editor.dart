import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:prism_ui/prism_ui.dart' as prism;

import '../../settings/widgets/settings_action.dart';
import '../../settings/widgets/settings_menu.dart';
import '../../settings/widgets/settings_sheet.dart';
import '../equalizer_store.dart';
import 'equalizer_controls.dart';

sealed class EqualizerBandEditorResult {
  const EqualizerBandEditorResult();
}

class EqualizerBandSaved extends EqualizerBandEditorResult {
  const EqualizerBandSaved(this.band);
  final EqualizerBandSetting band;
}

class EqualizerBandDeleted extends EqualizerBandEditorResult {
  const EqualizerBandDeleted();
}

Future<EqualizerBandEditorResult?> showEqualizerBandEditor(
  BuildContext context,
  EqualizerBandSetting initial, {
  required bool adding,
}) {
  var enabled = initial.enabled;
  var filter = initial.filter;
  var frequency = initial.frequencyHz
      .clamp(equalizerMinFrequencyHz, equalizerMaxFrequencyHz)
      .toDouble();
  var gain = initial.gainDb
      .clamp(equalizerMinGainDb, equalizerMaxGainDb)
      .toDouble();
  var q = initial.q.clamp(equalizerMinQ, equalizerMaxQ).toDouble();

  return showSettingsSheet<EqualizerBandEditorResult>(
    context: context,
    heightFraction: 0.78,
    maxHeight: 680,
    builder: (sheetContext) => StatefulBuilder(
      builder: (context, setSheetState) => SettingsSheetLayout(
        title: adding ? '新增频段' : '编辑频段',
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SettingsGroup(
                children: [
                  SettingsSwitchAction(
                    icon: Icons.graphic_eq_rounded,
                    title: '启用此频段',
                    value: enabled,
                    onChanged: (value) => setSheetState(() => enabled = value),
                  ),
                  SettingsMenuAction(
                    menuId: 'equalizer-filter-type',
                    icon: Icons.tune_rounded,
                    title: '滤波器类型',
                    options: [
                      for (final type in EqualizerFilterType.values)
                        SettingsMenuOption(
                          id: type.name,
                          label: type.label,
                          selected: filter == type,
                          onSelected: () => setSheetState(() => filter = type),
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SettingsCard(
                insetContent: true,
                children: [
                  EqualizerValueSlider(
                    label: '中心频率',
                    valueLabel: equalizerFrequencyLabel(frequency),
                    value: math.log(frequency) / math.ln10,
                    min: math.log(equalizerMinFrequencyHz) / math.ln10,
                    max: math.log(equalizerMaxFrequencyHz) / math.ln10,
                    onChanged: (value) => setSheetState(
                      () => frequency = math.pow(10, value).toDouble(),
                    ),
                    onReset: () => setSheetState(() => frequency = 1000),
                  ),
                  if (filter.usesGain) ...[
                    const SizedBox(height: 12),
                    EqualizerValueSlider(
                      label: '增益',
                      valueLabel: equalizerDbLabel(gain),
                      value: gain,
                      min: equalizerMinGainDb,
                      max: equalizerMaxGainDb,
                      onChanged: (value) => setSheetState(() => gain = value),
                      onReset: () => setSheetState(() => gain = 0),
                    ),
                  ],
                  const SizedBox(height: 12),
                  EqualizerValueSlider(
                    label: '品质因数 (Q)',
                    valueLabel: q.toStringAsFixed(2),
                    value:
                        math.log(q / equalizerMinQ) /
                        math.log(equalizerMaxQ / equalizerMinQ),
                    min: 0,
                    max: 1,
                    onChanged: (value) => setSheetState(
                      () => q =
                          equalizerMinQ *
                          math.pow(equalizerMaxQ / equalizerMinQ, value),
                    ),
                    onReset: () => setSheetState(() => q = 0.707),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          prism.FilledButton(
            onPressed: () => Navigator.of(sheetContext).pop(
              EqualizerBandSaved(
                initial.copyWith(
                  enabled: enabled,
                  filter: filter,
                  frequencyHz: frequency,
                  gainDb: gain,
                  q: q,
                ),
              ),
            ),
            child: Text(adding ? '添加频段' : '保存设置'),
          ),
          if (!adding)
            prism.TextButton.icon(
              style: prism.ButtonStyle.from(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: () =>
                  Navigator.of(sheetContext).pop(const EqualizerBandDeleted()),
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              label: const Text('删除此频段'),
            ),
        ],
      ),
    ),
  );
}
