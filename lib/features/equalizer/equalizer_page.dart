import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ui/app_toast.dart';
import '../settings/widgets/settings_action.dart';
import '../shell/shell_toolbar_visibility.dart';
import 'equalizer_store.dart';

sealed class _BandEditorResult {
  const _BandEditorResult();
}

class _BandEditorSaveResult extends _BandEditorResult {
  const _BandEditorSaveResult(this.band);
  final EqualizerBandSetting band;
}

class _BandEditorDeleteResult extends _BandEditorResult {
  const _BandEditorDeleteResult();
}

class EqualizerPage extends ConsumerStatefulWidget {
  const EqualizerPage({super.key});

  @override
  ConsumerState<EqualizerPage> createState() => _EqualizerPageState();
}

class _EqualizerPageState extends ConsumerState<EqualizerPage> {
  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(equalizerProvider);
    final notifier = ref.read(equalizerProvider.notifier);
    final scheme = Theme.of(context).colorScheme;
    final activeBandCount = settings.bands.where((band) => band.enabled).length;

    return CustomScrollView(
      key: const PageStorageKey('equalizer-scroll'),
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(28, 2, 28, 126),
          sliver: SliverToBoxAdapter(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SettingsCard(
                      title: 'BASS 参数均衡器',
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: settings.enabled
                                    ? scheme.primaryContainer
                                    : scheme.surfaceContainerHighest,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.graphic_eq_rounded,
                                color: settings.enabled
                                    ? scheme.onPrimaryContainer
                                    : scheme.onSurfaceVariant,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    settings.enabled ? '均衡器已开启' : '均衡器已关闭',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    '当前为测试阶段，仅作参考使用',
                                    style: TextStyle(
                                      color: scheme.onSurfaceVariant,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              value: settings.enabled,
                              onChanged: notifier.setEnabled,
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        Container(
                          height: 196,
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerLowest,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: scheme.outlineVariant.withValues(alpha: 0.35),
                            ),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: CustomPaint(
                            painter: _EqualizerCurvePainter(
                              settings: settings,
                              scheme: scheme,
                            ),
                            child: const SizedBox.expand(),
                          ),
                        ),
                        const SizedBox(height: 18),
                        _PresetSelector(
                          selectedId: settings.presetId,
                          onSelected: (id) {
                            if (id == null || id == 'custom') return;
                            final preset = equalizerPresets.firstWhere(
                              (candidate) => candidate.id == id,
                            );
                            notifier.applyPreset(preset);
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    SettingsCard(
                      title: '增益调节',
                      children: [
                        _GainSlider(
                          label: '输入增益',
                          value: settings.inputGainDb,
                          onChanged: notifier.setInputGain,
                        ),
                        const SizedBox(height: 10),
                        _GainSlider(
                          label: '输出增益',
                          value: settings.outputGainDb,
                          onChanged: notifier.setOutputGain,
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    SettingsCard(
                      title: '滤波频段',
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '上下拖动调节增益，点击调节按钮设置频率、Q 值及开关',
                                style: TextStyle(
                                  color: scheme.onSurfaceVariant,
                                  fontSize: 12,
                                  height: 1.35,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            FilledButton.tonalIcon(
                              onPressed:
                                  settings.bands.length >= equalizerMaxBands
                                  ? null
                                  : () => _addBand(settings),
                              icon: const Icon(Icons.add_rounded, size: 18),
                              label: Text(
                                '${settings.bands.length}/$equalizerMaxBands',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Container(
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerLowest,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: scheme.outlineVariant.withValues(alpha: 0.35),
                            ),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            physics: const BouncingScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
                            child: settings.bands.isEmpty
                                ? SizedBox(
                                    height: 230,
                                    child: Center(
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 24,
                                        ),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.equalizer_rounded,
                                              size: 38,
                                              color: scheme.onSurfaceVariant
                                                  .withValues(alpha: 0.5),
                                            ),
                                            const SizedBox(height: 10),
                                            Text(
                                              '当前预设暂无滤波频段',
                                              style: TextStyle(
                                                color: scheme.onSurfaceVariant,
                                                fontSize: 13,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                            const SizedBox(height: 12),
                                            FilledButton.tonalIcon(
                                              onPressed: () => _addBand(settings),
                                              icon: const Icon(
                                                Icons.add_rounded,
                                                size: 16,
                                              ),
                                              label: const Text('添加新频段'),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  )
                                : Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      for (final band in settings.bands) ...[
                                        _BandSlider(
                                          band: band,
                                          onChanged: (value) => notifier
                                              .setBandGain(band.id, value),
                                          onEdit: () => _editBand(band),
                                        ),
                                        const SizedBox(width: 4),
                                      ],
                                    ],
                                  ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    SettingsCard(
                      title: '预设配置',
                      children: [
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            FilledButton.tonalIcon(
                              onPressed: _importSpeq,
                              icon: const Icon(Icons.file_open_rounded, size: 18),
                              label: const Text('导入 .speq'),
                            ),
                            FilledButton.tonalIcon(
                              onPressed: () => _exportSpeq(settings),
                              icon: const Icon(Icons.save_alt_rounded, size: 18),
                              label: const Text('导出 .speq'),
                            ),
                            OutlinedButton.icon(
                              onPressed: _reset,
                              icon: const Icon(Icons.restart_alt_rounded, size: 18),
                              label: const Text('恢复默认'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<T> _withHiddenToolbar<T>(Future<T> Function() action) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final toolbar = ref.read(shellToolbarVisibleProvider.notifier);
    final wasToolbarVisible = ref.read(shellToolbarVisibleProvider);
    toolbar.state = false;
    try {
      return await action();
    } finally {
      if (toolbar.mounted) toolbar.state = wasToolbarVisible;
    }
  }

  Future<void> _addBand(EqualizerSettings settings) async {
    final band = EqualizerBandSetting(
      id: 'custom-${DateTime.now().microsecondsSinceEpoch}',
      frequencyHz: nextEqualizerBandFrequency(settings.bands),
    );
    final result = await _withHiddenToolbar(
      () => _showBandEditor(band, adding: true),
    );
    if (result is _BandEditorSaveResult && mounted) {
      ref.read(equalizerProvider.notifier).addBand(result.band);
    }
  }

  Future<void> _editBand(EqualizerBandSetting band) async {
    final result = await _withHiddenToolbar(
      () => _showBandEditor(band, adding: false),
    );
    if (!mounted) return;
    if (result is _BandEditorSaveResult) {
      ref.read(equalizerProvider.notifier).updateBand(result.band);
    } else if (result is _BandEditorDeleteResult) {
      ref.read(equalizerProvider.notifier).removeBand(band.id);
    }
  }

  Future<_BandEditorResult?> _showBandEditor(
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

    return showModalBottomSheet<_BandEditorResult>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      barrierColor: Theme.of(context).colorScheme.scrim.withValues(alpha: 0.36),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final scheme = Theme.of(context).colorScheme;
          return SafeArea(
            top: false,
            child: Center(
              heightFactor: 1,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    24,
                    8,
                    24,
                    24 + MediaQuery.viewInsetsOf(context).bottom,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    adding ? '新增频段' : '编辑频段',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '设置频段滤波器、参数与开关状态',
                                    style: TextStyle(
                                      color: scheme.onSurfaceVariant,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () =>
                                  Navigator.of(sheetContext).pop(),
                              icon: const Icon(Icons.close_rounded),
                              tooltip: '关闭',
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Container(
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerHighest.withValues(
                              alpha: 0.45,
                            ),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: SwitchListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 2,
                            ),
                            title: const Text(
                              '启用此频段',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                              ),
                            ),
                            subtitle: Text(
                              enabled
                                  ? '该频段正在参与音频滤波处理'
                                  : '该频段已停用旁通（不影响声音）',
                              style: TextStyle(
                                color: enabled
                                    ? scheme.primary
                                    : scheme.onSurfaceVariant,
                                fontSize: 12,
                              ),
                            ),
                            value: enabled,
                            onChanged: (value) =>
                                setSheetState(() => enabled = value),
                          ),
                        ),
                        const SizedBox(height: 14),
                        DropdownButtonFormField<EqualizerFilterType>(
                          initialValue: filter,
                          decoration: InputDecoration(
                            labelText: '滤波器类型',
                            filled: true,
                            fillColor: scheme.surfaceContainerHighest.withValues(
                              alpha: 0.35,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(
                                color: scheme.outlineVariant,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(
                                color: scheme.outlineVariant.withValues(
                                  alpha: 0.6,
                                ),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(
                                color: scheme.primary,
                                width: 1.5,
                              ),
                            ),
                          ),
                          items: [
                            for (final type in EqualizerFilterType.values)
                              DropdownMenuItem(
                                value: type,
                                child: Text(type.label),
                              ),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setSheetState(() => filter = value);
                            }
                          },
                        ),
                        const SizedBox(height: 12),
                        _EditorSlider(
                          label: '中心频率',
                          valueLabel: _frequencyLabel(frequency),
                          value: math.log(frequency) / math.ln10,
                          min: math.log(equalizerMinFrequencyHz) / math.ln10,
                          max: math.log(equalizerMaxFrequencyHz) / math.ln10,
                          onChanged: (value) => setSheetState(
                            () => frequency = math.pow(10, value).toDouble(),
                          ),
                          onReset: () => setSheetState(() => frequency = 1000),
                        ),
                        if (filter.usesGain)
                          _EditorSlider(
                            label: '增益',
                            valueLabel: _dbLabel(gain),
                            value: gain,
                            min: equalizerMinGainDb,
                            max: equalizerMaxGainDb,
                            onChanged: (value) =>
                                setSheetState(() => gain = value),
                            onReset: () => setSheetState(() => gain = 0),
                          ),
                        _EditorSlider(
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
                        const SizedBox(height: 14),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          onPressed: () => Navigator.of(sheetContext).pop(
                            _BandEditorSaveResult(
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
                        if (!adding) ...[
                          const SizedBox(height: 8),
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              foregroundColor: scheme.error,
                              minimumSize: const Size.fromHeight(42),
                            ),
                            onPressed: () => Navigator.of(sheetContext).pop(
                              const _BandEditorDeleteResult(),
                            ),
                            icon: const Icon(
                              Icons.delete_outline_rounded,
                              size: 19,
                            ),
                            label: const Text('删除此频段'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _importSpeq() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: '导入均衡器配置',
      type: FileType.custom,
      allowedExtensions: const ['speq', 'json'],
      withData: true,
    );
    if (result == null || !mounted) return;
    try {
      final picked = result.files.single;
      final value = picked.bytes != null
          ? utf8.decode(picked.bytes!)
          : await File(picked.path!).readAsString();
      ref.read(equalizerProvider.notifier).importSpeq(value);
      if (!mounted) return;
      showAppToast(context, '均衡器配置已导入', type: AppToastType.success);
    } catch (error) {
      if (!mounted) return;
      showAppToast(context, '无法导入配置：$error', type: AppToastType.error);
    }
  }

  Future<void> _exportSpeq(EqualizerSettings settings) async {
    try {
      var path = await FilePicker.platform.saveFile(
        dialogTitle: '导出均衡器配置',
        fileName: 'CyShineMusic.speq',
        type: FileType.custom,
        allowedExtensions: const ['speq'],
      );
      if (path == null || !mounted) return;
      if (!path.toLowerCase().endsWith('.speq')) path = '$path.speq';
      await File(path).writeAsString(settings.toSpeq(), flush: true);
      if (!mounted) return;
      showAppToast(context, '均衡器配置已导出', type: AppToastType.success);
    } catch (error) {
      if (!mounted) return;
      showAppToast(context, '无法导出配置：$error', type: AppToastType.error);
    }
  }

  Future<void> _reset() async {
    final confirmed = await _withHiddenToolbar(
      () => showDialog<bool>(
        context: context,
        useRootNavigator: true,
        builder: (dialogContext) => AlertDialog(
          title: const Text('恢复默认均衡器？'),
          content: const Text('这会关闭均衡器，并恢复原声配置。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('恢复'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    ref.read(equalizerProvider.notifier).reset();
  }
}

class _PresetSelector extends StatelessWidget {
  const _PresetSelector({required this.selectedId, required this.onSelected});

  final String? selectedId;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ids = equalizerPresets.map((preset) => preset.id).toSet();
    final effectiveId = ids.contains(selectedId) ? selectedId : 'custom';
    return DropdownButtonFormField<String>(
      initialValue: effectiveId,
      decoration: InputDecoration(
        labelText: '声音预设',
        prefixIcon: const Icon(Icons.tune_rounded),
        filled: true,
        fillColor: scheme.surfaceContainerLowest,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
      ),
      items: [
        const DropdownMenuItem(value: 'custom', child: Text('自定义')),
        for (final preset in equalizerPresets)
          DropdownMenuItem(value: preset.id, child: Text(preset.label)),
      ],
      onChanged: onSelected,
    );
  }
}

class _GainSlider extends StatelessWidget {
  const _GainSlider({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isNonZero = value.abs() > 0.05;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 4,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              ),
              child: Slider(
                value: value,
                min: equalizerMinGainDb,
                max: equalizerMaxGainDb,
                label: _dbLabel(value),
                onChanged: onChanged,
              ),
            ),
          ),
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: isNonZero ? () => onChanged(0.0) : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _dbLabel(value),
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isNonZero ? scheme.primary : scheme.onSurfaceVariant,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  if (isNonZero) ...[
                    const SizedBox(width: 4),
                    Icon(
                      Icons.refresh_rounded,
                      size: 14,
                      color: scheme.primary.withValues(alpha: 0.8),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BandSlider extends StatelessWidget {
  const _BandSlider({
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

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: band.enabled ? 1.0 : 0.45,
      child: SizedBox(
        width: 68,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: band.enabled
                    ? scheme.primaryContainer.withValues(alpha: 0.75)
                    : scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                !band.enabled
                    ? '停用'
                    : band.filter.usesGain
                        ? _dbLabel(band.gainDb)
                        : band.filter.label,
                style: TextStyle(
                  color: band.enabled
                      ? scheme.onPrimaryContainer
                      : scheme.onSurfaceVariant,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            SizedBox(
              width: 48,
              height: 180,
              child: RotatedBox(
                quarterTurns: 3,
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 4,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 6,
                    ),
                  ),
                  child: Slider(
                    value: band.filter.usesGain
                        ? band.gainDb.clamp(
                            equalizerMinGainDb,
                            equalizerMaxGainDb,
                          )
                        : 0,
                    min: equalizerMinGainDb,
                    max: equalizerMaxGainDb,
                    onChanged: band.enabled && band.filter.usesGain
                        ? onChanged
                        : null,
                  ),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                _frequencyLabel(band.frequencyHz),
                maxLines: 1,
                style: TextStyle(
                  color: band.enabled
                      ? scheme.onSurface
                      : scheme.onSurfaceVariant,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(height: 8),
            IconButton.filledTonal(
              tooltip: '编辑频段',
              iconSize: 18,
              style: IconButton.styleFrom(
                minimumSize: const Size(36, 36),
                padding: EdgeInsets.zero,
                backgroundColor: band.enabled
                    ? scheme.secondaryContainer
                    : scheme.surfaceContainerHighest,
                foregroundColor: band.enabled
                    ? scheme.onSecondaryContainer
                    : scheme.onSurfaceVariant,
              ),
              onPressed: onEdit,
              icon: const Icon(Icons.tune_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditorSlider extends StatelessWidget {
  const _EditorSlider({
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
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              const Spacer(),
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: onReset,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        valueLabel,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: scheme.primary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      if (onReset != null) ...[
                        const SizedBox(width: 4),
                        Icon(
                          Icons.refresh_rounded,
                          size: 14,
                          color: scheme.primary.withValues(alpha: 0.8),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _EqualizerCurvePainter extends CustomPainter {
  const _EqualizerCurvePainter({required this.settings, required this.scheme});

  final EqualizerSettings settings;
  final ColorScheme scheme;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = scheme.outlineVariant.withValues(alpha: 0.35)
      ..strokeWidth = 1;

    // Horizontal grid lines and dB labels
    const dbLines = [12.0, 0.0, -12.0];
    for (final db in dbLines) {
      final y = _gainY(db, size.height);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
      _drawText(
        canvas,
        '${db > 0 ? '+' : ''}${db.round()}dB',
        Offset(6, y - 11),
        color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
      );
    }

    // Vertical frequency grid lines and labels
    for (final frequency in const <double>[31, 125, 500, 2000, 8000, 16000]) {
      final x = _frequencyX(frequency, size.width);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
      final label = frequency >= 1000
          ? '${(frequency / 1000).round()}k'
          : '${frequency.round()}';
      _drawText(
        canvas,
        label,
        Offset(x + 3, size.height - 13),
        color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
      );
    }

    // Baseline (0 dB)
    final zeroY = _gainY(0.0, size.height);
    canvas.drawLine(
      Offset(0, zeroY),
      Offset(size.width, zeroY),
      Paint()
        ..color = scheme.outline.withValues(alpha: 0.4)
        ..strokeWidth = 1.2,
    );

    final path = Path();
    if (!settings.enabled) {
      path
        ..moveTo(0, zeroY)
        ..lineTo(size.width, zeroY);
    } else {
      for (var index = 0; index < 320; index++) {
        final normalized = index / 319;
        final frequency =
            equalizerMinFrequencyHz *
            math.pow(
              equalizerMaxFrequencyHz / equalizerMinFrequencyHz,
              normalized,
            );
        final gain = _equalizerResponseDb(
          settings,
          frequency.toDouble(),
        ).clamp(equalizerMinGainDb, equalizerMaxGainDb);
        final point = Offset(
          normalized * size.width,
          _gainY(gain.toDouble(), size.height),
        );
        if (index == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
    }

    // Gradient fill under the curve (studio EQ look)
    if (settings.enabled) {
      final fillPath = Path.from(path)
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close();
      final fillPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            scheme.primary.withValues(alpha: 0.2),
            scheme.primary.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
        ..style = PaintingStyle.fill;
      canvas.drawPath(fillPath, fillPaint);
    }

    // Response curve line
    final line = Paint()
      ..color = settings.enabled
          ? scheme.primary
          : scheme.outline.withValues(alpha: 0.5)
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    canvas.drawPath(path, line);

    // Nodes for each band
    for (final band in settings.bands) {
      final x = _frequencyX(band.frequencyHz, size.width);
      final y = _gainY(band.filter.usesGain ? band.gainDb : 0, size.height);
      if (!settings.enabled || !band.enabled) {
        canvas.drawCircle(
          Offset(x, y),
          3.5,
          Paint()
            ..color = scheme.outline.withValues(alpha: 0.5)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      } else {
        // Halo
        canvas.drawCircle(
          Offset(x, y),
          6.5,
          Paint()
            ..color = scheme.primary.withValues(alpha: 0.25)
            ..style = PaintingStyle.fill,
        );
        // Core dot
        canvas.drawCircle(
          Offset(x, y),
          3.5,
          Paint()
            ..color = scheme.primary
            ..style = PaintingStyle.fill,
        );
      }
    }

    // Subtle bypass badge in center when EQ is disabled
    if (!settings.enabled) {
      const hint = '均衡器已旁通';
      final textPainter = TextPainter(
        text: TextSpan(
          text: hint,
          style: TextStyle(
            color: scheme.onSurfaceVariant.withValues(alpha: 0.85),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final rect = Rect.fromCenter(
        center: Offset(size.width / 2, size.height / 2),
        width: textPainter.width + 24,
        height: textPainter.height + 12,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(12)),
        Paint()..color = scheme.surfaceContainerHigh.withValues(alpha: 0.8),
      );
      textPainter.paint(
        canvas,
        Offset(rect.left + 12, rect.top + 6),
      );
    }
  }

  void _drawText(
    Canvas canvas,
    String text,
    Offset offset, {
    Color? color,
    double fontSize = 9,
    FontWeight fontWeight = FontWeight.w500,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color ?? scheme.onSurfaceVariant.withValues(alpha: 0.55),
          fontSize: fontSize,
          fontWeight: fontWeight,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, offset);
  }

  double _frequencyX(double frequency, double width) {
    final normalized =
        (math.log(frequency.clamp(20, 20_000)) / math.ln10 -
            math.log(20) / math.ln10) /
        (math.log(20_000) / math.ln10 - math.log(20) / math.ln10);
    return normalized * width;
  }

  double _gainY(double gain, double height) =>
      (equalizerMaxGainDb - gain) /
      (equalizerMaxGainDb - equalizerMinGainDb) *
      height;

  @override
  bool shouldRepaint(covariant _EqualizerCurvePainter oldDelegate) {
    return oldDelegate.settings != settings || oldDelegate.scheme != scheme;
  }
}

double _equalizerResponseDb(EqualizerSettings settings, double frequency) {
  if (!settings.enabled) return 0;
  var result = settings.inputGainDb + settings.outputGainDb;
  for (final band in settings.bands) {
    if (!band.enabled) continue;
    result += _biquadResponseDb(band, frequency);
  }
  return result;
}

double _biquadResponseDb(EqualizerBandSetting band, double frequency) {
  const sampleRate = 48000.0;
  final center = band.frequencyHz.clamp(1, sampleRate / 2 - 1);
  final omega = 2 * math.pi * center / sampleRate;
  final cosOmega = math.cos(omega);
  final sinOmega = math.sin(omega);
  final q = band.q.clamp(equalizerMinQ, equalizerMaxQ);
  final amplitude = math.pow(10, band.gainDb / 40).toDouble();

  late double b0;
  late double b1;
  late double b2;
  late double a0;
  late double a1;
  late double a2;

  switch (band.filter) {
    case EqualizerFilterType.peaking:
      final alpha = sinOmega / (2 * q);
      b0 = 1 + alpha * amplitude;
      b1 = -2 * cosOmega;
      b2 = 1 - alpha * amplitude;
      a0 = 1 + alpha / amplitude;
      a1 = -2 * cosOmega;
      a2 = 1 - alpha / amplitude;
    case EqualizerFilterType.lowPass:
      final alpha = sinOmega / (2 * q);
      b0 = (1 - cosOmega) / 2;
      b1 = 1 - cosOmega;
      b2 = b0;
      a0 = 1 + alpha;
      a1 = -2 * cosOmega;
      a2 = 1 - alpha;
    case EqualizerFilterType.highPass:
      final alpha = sinOmega / (2 * q);
      b0 = (1 + cosOmega) / 2;
      b1 = -(1 + cosOmega);
      b2 = b0;
      a0 = 1 + alpha;
      a1 = -2 * cosOmega;
      a2 = 1 - alpha;
    case EqualizerFilterType.lowShelf:
    case EqualizerFilterType.highShelf:
      final slope = _shelfSlope(band.gainDb, q);
      final alpha =
          sinOmega /
          2 *
          math.sqrt((amplitude + 1 / amplitude) * (1 / slope - 1) + 2);
      final rootAAlpha = 2 * math.sqrt(amplitude) * alpha;
      if (band.filter == EqualizerFilterType.lowShelf) {
        b0 =
            amplitude *
            ((amplitude + 1) - (amplitude - 1) * cosOmega + rootAAlpha);
        b1 = 2 * amplitude * ((amplitude - 1) - (amplitude + 1) * cosOmega);
        b2 =
            amplitude *
            ((amplitude + 1) - (amplitude - 1) * cosOmega - rootAAlpha);
        a0 = (amplitude + 1) + (amplitude - 1) * cosOmega + rootAAlpha;
        a1 = -2 * ((amplitude - 1) + (amplitude + 1) * cosOmega);
        a2 = (amplitude + 1) + (amplitude - 1) * cosOmega - rootAAlpha;
      } else {
        b0 =
            amplitude *
            ((amplitude + 1) + (amplitude - 1) * cosOmega + rootAAlpha);
        b1 = -2 * amplitude * ((amplitude - 1) + (amplitude + 1) * cosOmega);
        b2 =
            amplitude *
            ((amplitude + 1) + (amplitude - 1) * cosOmega - rootAAlpha);
        a0 = (amplitude + 1) - (amplitude - 1) * cosOmega + rootAAlpha;
        a1 = 2 * ((amplitude - 1) - (amplitude + 1) * cosOmega);
        a2 = (amplitude + 1) - (amplitude - 1) * cosOmega - rootAAlpha;
      }
  }

  final targetOmega =
      2 * math.pi * frequency.clamp(1, sampleRate / 2 - 1) / sampleRate;
  final cos1 = math.cos(targetOmega);
  final sin1 = math.sin(targetOmega);
  final cos2 = math.cos(2 * targetOmega);
  final sin2 = math.sin(2 * targetOmega);
  final numeratorReal = b0 + b1 * cos1 + b2 * cos2;
  final numeratorImag = -b1 * sin1 - b2 * sin2;
  final denominatorReal = a0 + a1 * cos1 + a2 * cos2;
  final denominatorImag = -a1 * sin1 - a2 * sin2;
  final numerator =
      numeratorReal * numeratorReal + numeratorImag * numeratorImag;
  final denominator =
      denominatorReal * denominatorReal + denominatorImag * denominatorImag;
  final power = math.max(numerator / denominator, 1e-12);
  return 10 * math.log(power) / math.ln10;
}

double _shelfSlope(double gainDb, double q) {
  final amplitude = math.pow(10, gainDb / 40).toDouble();
  final slope = 1 / (((1 / (q * q) - 2) / (1 / amplitude + amplitude)) + 1);
  return math.max(slope, 0.1);
}

String _dbLabel(double value) =>
    '${value >= 0 ? '+' : ''}${value.toStringAsFixed(1)} dB';

String _frequencyLabel(double value) {
  if (value >= 1000) {
    final kilo = value / 1000;
    return '${kilo >= 10 ? kilo.toStringAsFixed(0) : kilo.toStringAsFixed(1)}k';
  }
  return value.toStringAsFixed(0);
}
