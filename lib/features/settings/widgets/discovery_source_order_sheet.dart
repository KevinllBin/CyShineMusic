import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/models/enums.dart';

Future<void> showDiscoverySourceOrderSheet(
  BuildContext context, {
  required List<MusicSource> order,
  required Future<void> Function(List<MusicSource>) onChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => _DiscoverySourceOrderSheet(
      initialOrder: order,
      onChanged: onChanged,
    ),
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

class _DiscoverySourceOrderSheetState extends State<_DiscoverySourceOrderSheet> {
  late final List<MusicSource> _order = List<MusicSource>.of(
    widget.initialOrder,
  );

  void _reorder(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex--;
    setState(() {
      final source = _order.removeAt(oldIndex);
      _order.insert(newIndex, source);
    });
    unawaited(widget.onChanged(List<MusicSource>.unmodifiable(_order)));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: SizedBox(
        height: 400,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '发现页平台顺序',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ReorderableListView.builder(
                  itemCount: _order.length,
                  onReorder: _reorder,
                  buildDefaultDragHandles: false,
                  itemBuilder: (context, index) {
                    final source = _order[index];
                    return ListTile(
                      key: ValueKey(source.code),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                      title: Text(source.label),
                      trailing: ReorderableDragStartListener(
                        index: index,
                        child: Icon(
                          Icons.drag_handle_rounded,
                          color: scheme.outline,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
