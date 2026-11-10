import '../../settings/widgets/settings_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_ui/prism_ui.dart' as prism;

import '../../shell/shell_toolbar_visibility.dart';
import '../sleep_timer_controller.dart';

String formatSleepTimerRemaining(Duration duration) {
  final seconds = duration.isNegative ? 0 : duration.inSeconds;
  String two(int value) => value.toString().padLeft(2, '0');
  final minutes = seconds ~/ 60;
  final tail = two(seconds % 60);
  if (minutes < 60) return '${two(minutes)}:$tail';
  return '${minutes ~/ 60}:${two(minutes % 60)}:$tail';
}

Future<void> showPlayerSleepTimerSheet(
  BuildContext context,
  WidgetRef ref,
) async {
  FocusManager.instance.primaryFocus?.unfocus();
  final toolbar = ref.read(shellToolbarVisibleProvider.notifier);
  final wasToolbarVisible = ref.read(shellToolbarVisibleProvider);
  toolbar.state = false;
  try {
    await showSettingsSheet<void>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      builder: (_) => const _PlayerSleepTimerSheet(),
    );
  } finally {
    if (toolbar.mounted) toolbar.state = wasToolbarVisible;
  }
}

class _PlayerSleepTimerSheet extends ConsumerStatefulWidget {
  const _PlayerSleepTimerSheet();

  @override
  ConsumerState<_PlayerSleepTimerSheet> createState() =>
      _PlayerSleepTimerSheetState();
}

class _PlayerSleepTimerSheetState
    extends ConsumerState<_PlayerSleepTimerSheet> {
  final _customMinutes = TextEditingController();
  int? _presetMinutes = 30;

  @override
  void dispose() {
    _customMinutes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final remaining = ref.watch(sleepTimerProvider);
    final custom = _presetMinutes == null;
    final minutes = _presetMinutes ?? int.tryParse(_customMinutes.text);
    final valid = minutes != null && minutes >= 1 && minutes <= 180;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SettingsSheetLayout(
        key: const ValueKey('player-sleep-timer-sheet'),
        title: '定时关闭音乐',
        body: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '到时暂停播放，手动暂停不会停止计时。',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              if (remaining != null) ...[
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: scheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '距离暂停播放',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: scheme.onSecondaryContainer,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        formatSleepTimerRemaining(remaining),
                        key: const ValueKey('sleep-timer-remaining'),
                        style: theme.textTheme.headlineMedium?.copyWith(
                          color: scheme.onSecondaryContainer,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Text('选择时长', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final preset in const [15, 30, 45, 60, 90])
                    prism.Chip(
                      key: ValueKey('sleep-timer-preset-$preset'),
                      label: '$preset 分钟',
                      selected: _presetMinutes == preset,
                      onPressed: () {
                        FocusManager.instance.primaryFocus?.unfocus();
                        setState(() => _presetMinutes = preset);
                      },
                    ),
                  prism.Chip(
                    key: const ValueKey('sleep-timer-custom'),
                    label: '自定义',
                    selected: custom,
                    onPressed: () => setState(() => _presetMinutes = null),
                  ),
                ],
              ),
              if (custom) ...[
                const SizedBox(height: 16),
                TextField(
                  key: const ValueKey('sleep-timer-custom-minutes'),
                  controller: _customMinutes,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(3),
                  ],
                  decoration: InputDecoration(
                    labelText: '时长',
                    suffixText: '分钟',
                    errorText: _customMinutes.text.isNotEmpty && !valid
                        ? '请输入 1–180 之间的分钟数'
                        : null,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) {
                    if (valid) _start(minutes);
                  },
                ),
              ],
            ],
          ),
        ),
        actions: [
          prism.FilledButton.icon(
            key: const ValueKey('sleep-timer-start'),
            onPressed: valid ? () => _start(minutes) : null,
            icon: const Icon(Icons.timer_outlined),
            label: Text(remaining == null ? '开启定时' : '重新计时'),
          ),
          if (remaining != null) ...[
            prism.TextButton(
              key: const ValueKey('sleep-timer-cancel'),
              onPressed: () {
                ref.read(sleepTimerProvider.notifier).cancel();
                Navigator.of(context).pop();
              },
              child: const Text('取消定时'),
            ),
          ],
        ],
      ),
    );
  }

  void _start(int minutes) {
    ref.read(sleepTimerProvider.notifier).start(Duration(minutes: minutes));
    Navigator.of(context).pop();
  }
}
