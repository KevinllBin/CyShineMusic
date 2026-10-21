import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../search_history_store.dart';

class SearchHistorySuggestions extends ConsumerWidget {
  const SearchHistorySuggestions({super.key, required this.onSelected});

  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(searchHistoryProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    if (history.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(18),
        child: Text(
          '暂无搜索记录',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      );
    }

    final store = ref.read(searchHistoryProvider.notifier);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(18, 4, 8, 0),
          child: Row(
            children: [
              Expanded(child: Text('搜索记录', style: theme.textTheme.titleSmall)),
              TextButton(onPressed: store.clear, child: const Text('清空')),
            ],
          ),
        ),
        for (final keyword in history)
          ListTile(
            key: ValueKey(keyword),
            minTileHeight: 54,
            contentPadding: const EdgeInsetsDirectional.fromSTEB(18, 0, 8, 0),
            leading: Icon(
              Icons.history_rounded,
              color: scheme.onSurfaceVariant,
              size: 20,
            ),
            title: Text(keyword, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: IconButton(
              tooltip: '删除记录',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close_rounded, size: 18),
              color: scheme.onSurfaceVariant,
              onPressed: () => store.remove(keyword),
            ),
            onTap: () => onSelected(keyword),
          ),
      ],
    );
  }
}
