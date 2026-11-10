import 'settings_sheet.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:prism_ui/prism_ui.dart' as prism;

import '../../../core/models/enums.dart';

Future<void> showDiscoverySourceOrderSheet(
  BuildContext context, {
  required List<MusicSource> order,
  required Future<void> Function(List<MusicSource>) onChanged,
}) {
  return showSettingsSheet<void>(
    context: context,
    showDragHandle: true,

    builder: (context) =>
        _DiscoverySourceOrderSheet(initialOrder: order, onChanged: onChanged),
  );
}

class _DiscoverySourceOrderSheet extends StatefulWidget {
  const _DiscoverySourceOrderSheet({
    required this.initialOrder,
    required this.onChanged,
  });

  final List<MusicSource> initialOrder;
  final Future<void> Function(List<MusicSource>) onChanged;

  @override
  State<_DiscoverySourceOrderSheet> createState() =>
      _DiscoverySourceOrderSheetState();
}

class _DiscoverySourceOrderSheetState
    extends State<_DiscoverySourceOrderSheet> {
  late final List<MusicSource> _order = List<MusicSource>.of(
    widget.initialOrder,
  );

  void _reorder(int oldIndex, int newIndex) {
    setState(() {
      final source = _order.removeAt(oldIndex);
      _order.insert(newIndex, source);
    });
    unawaited(widget.onChanged(List<MusicSource>.unmodifiable(_order)));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SettingsSheetLayout(
      title: '发现页平台顺序',
      body: ReorderableListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: _order.length,
        onReorderItem: _reorder,
        buildDefaultDragHandles: false,
        itemBuilder: (context, index) {
          final source = _order[index];
          return prism.Card(
            key: ValueKey(source.code),
            inert: true,
            radius: 18,
            child: prism.ListRow(
              title: Text(source.label),
              trailing: ReorderableDragStartListener(
                index: index,
                child: Icon(Icons.drag_handle_rounded, color: scheme.outline),
              ),
            ),
          );
        },
      ),
      actions: [
        prism.FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('完成'),
        ),
      ],
    );
  }
}
