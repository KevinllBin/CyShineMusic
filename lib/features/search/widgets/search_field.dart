import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/material.dart' as material show SearchController;

class NativeSearchField extends StatelessWidget {
  const NativeSearchField({
    super.key,
    required this.controller,
    required this.onSubmitted,
    required this.onClear,
    required this.loading,
    required this.suggestionsBuilder,
  });

  final material.SearchController controller;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;
  final bool loading;
  final Future<Iterable<Widget>> Function(
    BuildContext context,
    material.SearchController controller,
  )
  suggestionsBuilder;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textStyle = WidgetStatePropertyAll(
      TextStyle(
        color: scheme.onSurface,
        fontSize: 14,
        fontWeight: FontWeight.w500,
        height: 1.1,
        letterSpacing: 0,
      ),
    );
    final hintStyle = WidgetStatePropertyAll(
      TextStyle(
        color: scheme.onSurfaceVariant.withValues(alpha: 0.76),
        fontSize: 13,
        fontWeight: FontWeight.w500,
        height: 1.1,
      ),
    );
    final shape = WidgetStatePropertyAll(
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    );
    return SearchAnchor.bar(
      searchController: controller,
      isFullScreen: false,
      barHintText: '搜索歌曲、艺人、歌单、专辑',
      barLeading: Icon(
        Icons.search_rounded,
        color: scheme.onSurfaceVariant,
        size: 20,
      ),
      barTrailing: [
        _SearchTrailing(
          controller: controller,
          loading: loading,
          onClear: onClear,
        ),
      ],
      barElevation: const WidgetStatePropertyAll(0),
      barBackgroundColor: WidgetStatePropertyAll(scheme.surfaceContainerHigh),
      barOverlayColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.pressed)) {
          return scheme.primary.withValues(alpha: 0.08);
        }
        if (states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.focused)) {
          return scheme.primary.withValues(alpha: 0.05);
        }
        return Colors.transparent;
      }),
      barSide: WidgetStatePropertyAll(
        BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.28)),
      ),
      barShape: shape,
      barPadding: const WidgetStatePropertyAll(
        EdgeInsetsDirectional.fromSTEB(12, 0, 6, 0),
      ),
      barTextStyle: textStyle,
      barHintStyle: hintStyle,
      constraints: const BoxConstraints(minHeight: 48, maxHeight: 48),
      viewConstraints: BoxConstraints(
        maxHeight: math.min(MediaQuery.sizeOf(context).height * 0.52, 520),
      ),
      viewShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      viewSide: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.8)),
      viewBackgroundColor: scheme.surfaceContainerHigh,
      viewElevation: 0,
      dividerColor: scheme.outlineVariant.withValues(alpha: 0.72),
      viewBarPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      viewHeaderHeight: 48,
      viewHeaderTextStyle: textStyle.value,
      viewHeaderHintStyle: hintStyle.value,
      shrinkWrap: true,
      textCapitalization: TextCapitalization.none,
      textInputAction: TextInputAction.search,
      keyboardType: TextInputType.text,
      suggestionsBuilder: suggestionsBuilder,
      onSubmitted: onSubmitted,
    );
  }
}

class _SearchTrailing extends StatelessWidget {
  const _SearchTrailing({
    required this.controller,
    required this.loading,
    required this.onClear,
  });

  final material.SearchController controller;
  final bool loading;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox.square(
      dimension: 36,
      child: Center(
        child: ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, _) {
            if (value.text.isEmpty) {
              return const SizedBox.shrink(key: ValueKey('empty'));
            }
            return IconButton(
              key: const ValueKey('clear'),
              tooltip: loading ? '取消搜索' : '清除',
              visualDensity: VisualDensity.compact,
              color: scheme.onSurfaceVariant,
              onPressed: onClear,
              icon: loading
                  ? SizedBox.square(
                      key: const ValueKey('loading-cancel'),
                      dimension: 22,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          CircularProgressIndicator(
                            strokeWidth: 2,
                            color: scheme.primary,
                          ),
                          Icon(
                            Icons.close_rounded,
                            size: 14,
                            color: scheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                    )
                  : const Icon(Icons.close_rounded),
            );
          },
        ),
      ),
    );
  }
}

class SearchSuggestionTile extends StatelessWidget {
  const SearchSuggestionTile({
    super.key,
    required this.text,
    required this.onTap,
    required this.onComplete,
  });

  final String text;
  final VoidCallback onTap;
  final VoidCallback onComplete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      minTileHeight: 54,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18),
      minLeadingWidth: 34,
      leading: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.search_rounded,
          color: scheme.onSurfaceVariant,
          size: 18,
        ),
      ),
      title: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: scheme.onSurface,
          fontSize: 14.5,
          fontWeight: FontWeight.w500,
          letterSpacing: -0.05,
        ),
      ),
      trailing: IconButton(
        tooltip: '补全',
        icon: const Icon(Icons.north_west_rounded),
        iconSize: 19,
        color: scheme.onSurfaceVariant,
        visualDensity: VisualDensity.compact,
        onPressed: onComplete,
      ),
      onTap: onTap,
    );
  }
}
