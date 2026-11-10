import 'package:flutter/material.dart';
import 'package:prism_ui/prism_ui.dart' as prism;

import '../../../core/ui/app_sheet.dart';

import '../songs_toolbar_state.dart';

Future<void> showSongsSortSheet({
  required BuildContext context,
  required SongSortMode initialMode,
  required bool initialAscending,
  required void Function(SongSortMode mode, bool ascending) onChanged,
}) {
  return showAppSheet<void>(
    context: context,
    heightFraction: 0.70,
    maxHeight: 600,
    fitsContent: true,
    builder: (_) => _SongsSortSheet(
      initialMode: initialMode,
      initialAscending: initialAscending,
      onChanged: onChanged,
    ),
  );
}

class _SongsSortSheet extends StatefulWidget {
  const _SongsSortSheet({
    required this.initialMode,
    required this.initialAscending,
    required this.onChanged,
  });

  final SongSortMode initialMode;
  final bool initialAscending;
  final void Function(SongSortMode mode, bool ascending) onChanged;

  @override
  State<_SongsSortSheet> createState() => _SongsSortSheetState();
}

class _SongsSortSheetState extends State<_SongsSortSheet> {
  late SongSortMode _mode;
  late bool _ascending;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
    _ascending = widget.initialAscending;
  }

  void _selectMode(SongSortMode mode) {
    if (_mode == mode) return;
    setState(() {
      _mode = mode;
      _ascending = mode != SongSortMode.added;
    });
    widget.onChanged(_mode, _ascending);
  }

  void _selectDirection(bool ascending) {
    if (_ascending == ascending) return;
    setState(() => _ascending = ascending);
    widget.onChanged(_mode, _ascending);
  }

  @override
  Widget build(BuildContext context) => AppSheetLayout(
    title: '歌曲排序',
    subtitle: '选择后立即应用',
    body: ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
      children: [
        for (final mode in SongSortMode.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: prism.Card(
              radius: 18,
              isSelected: mode == _mode,
              onPressed: () => _selectMode(mode),
              child: prism.ListRow(
                leading: Icon(mode.icon, size: 22),
                title: Text(mode.label),
                trailing: mode == _mode
                    ? const prism.SelectionBadge(tonal: true)
                    : const SizedBox.square(dimension: 22),
              ),
            ),
          ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Text(
            '排列顺序',
            style: prism.AppTextStyle.subheadline.of(context),
          ),
        ),
        prism.SegmentedControl<bool>(
          segments: const [(true, '升序'), (false, '降序')],
          value: _ascending,
          onChanged: _selectDirection,
        ),
      ],
    ),
  );
}
