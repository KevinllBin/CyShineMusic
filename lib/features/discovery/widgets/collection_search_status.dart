import 'package:flutter/material.dart';

/// Keeps the loaded search range visible without adding another input field.
class CollectionSearchStatus extends StatelessWidget {
  const CollectionSearchStatus({
    super.key,
    required this.caption,
    this.onSearchAll,
    this.loading = false,
  });
  final String caption;
  final VoidCallback? onSearchAll;
  final bool loading;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: Row(
          children: [
            Expanded(
              child: Text(
                caption,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            if (onSearchAll != null)
              TextButton(
                onPressed: loading ? null : onSearchAll,
                child: Text(loading ? '正在加载' : '搜索全部'),
              ),
          ],
        ),
      ),
    ),
  );
}
