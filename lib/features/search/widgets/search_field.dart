import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/material.dart' as material show SearchController;
import 'package:prism_ui/prism_ui.dart' as prism;
import 'package:prism_ui/icons/icons.dart' as glyph;

import '../../../core/ui/widgets/app_navigation_button.dart';

class NativeSearchField extends StatefulWidget {
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
  State<NativeSearchField> createState() => _NativeSearchFieldState();
}

class _NativeSearchFieldState extends State<NativeSearchField> {
  // Editing belongs to the search view. A focusable anchor can regain focus
  // when platform-menu local history changes and reopen the keyboard.
  final _barFocusNode = FocusNode(
    debugLabel: 'search-anchor',
    canRequestFocus: false,
  );

  @override
  void dispose() {
    _barFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final liquidGlass = prism.LiquidGlassScope.of(context);
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
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    );
    return SearchAnchor(
      searchController: widget.controller,
      isFullScreen: false,
      viewLeading: AppNavigationButton.back(
        onPressed: () => widget.controller.closeView(widget.controller.text),
      ),
      viewOnSubmitted: widget.onSubmitted,
      viewHintText: '搜索歌曲、艺人、歌单、专辑',
      viewBackgroundColor: scheme.surface,
      viewElevation: 0,
      viewShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      viewSide: BorderSide(
        color: scheme.outlineVariant.withValues(alpha: 0.34),
      ),
      dividerColor: scheme.outlineVariant.withValues(alpha: 0.28),
      viewBarPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      headerHeight: 56,
      headerTextStyle: textStyle.value,
      headerHintStyle: hintStyle.value,
      viewConstraints: BoxConstraints(
        maxHeight: math.min(MediaQuery.sizeOf(context).height * 0.62, 600),
      ),
      viewTrailing: [_SearchViewTrailing(controller: widget.controller)],
      shrinkWrap: true,
      textCapitalization: TextCapitalization.none,
      textInputAction: TextInputAction.search,
      keyboardType: TextInputType.text,
      suggestionsBuilder: widget.suggestionsBuilder,
      builder: (context, searchController) {
        final bar = SearchBar(
          controller: searchController,
          focusNode: _barFocusNode,
          readOnly: true,
          onTap: searchController.openView,
          hintText: '搜索歌曲、艺人、歌单、专辑',
          leading: Icon(
            Icons.search_rounded,
            color: scheme.onSurfaceVariant,
            size: 20,
          ),
          trailing: [
            _SearchTrailing(
              controller: widget.controller,
              loading: widget.loading,
              onClear: widget.onClear,
            ),
          ],
          elevation: const WidgetStatePropertyAll(0),
          // GooSurface owns the background. Keeping the Material field clear
          // lets the backdrop and its rim show through instead of stacking an
          // opaque SearchBar fill over the liquid pane.
          backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) {
              return scheme.primary.withValues(alpha: 0.08);
            }
            if (states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.focused)) {
              return scheme.primary.withValues(alpha: 0.05);
            }
            return Colors.transparent;
          }),
          side: const WidgetStatePropertyAll(BorderSide.none),
          shape: shape,
          padding: const WidgetStatePropertyAll(
            EdgeInsetsDirectional.fromSTEB(12, 0, 6, 0),
          ),
          textStyle: textStyle,
          hintStyle: hintStyle,
          constraints: const BoxConstraints(minHeight: 52, maxHeight: 52),
          textCapitalization: TextCapitalization.none,
          textInputAction: TextInputAction.search,
          keyboardType: TextInputType.text,
        );
        final surface = liquidGlass
            ? prism.LiquidGlass(
                borderRadius: BorderRadius.circular(18),
                style: prism.LiquidGlassStyle.regular(
                  prism.Theme.of(context).colorScheme,
                ).copyWith(hazeBlur: 10),
                shadows: [
                  BoxShadow(
                    color: scheme.shadow.withValues(alpha: 0.12),
                    blurRadius: 22,
                    offset: const Offset(0, 8),
                  ),
                ],
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHigh.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: scheme.outline.withValues(alpha: 0.16),
                    ),
                  ),
                  child: bar,
                ),
              )
            : DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: scheme.outlineVariant.withValues(alpha: 0.34),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: scheme.shadow.withValues(alpha: 0.08),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: bar,
              );
        return prism.ElasticPress(child: surface);
      },
    );
  }
}

class _SearchViewTrailing extends StatelessWidget {
  const _SearchViewTrailing({required this.controller});

  final material.SearchController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final hasText = value.text.isNotEmpty;
        return prism.ElasticPress(
          child: prism.IconButton(
            tooltip: hasText ? '清除搜索' : '关闭搜索',
            onPressed: () {
              if (hasText) {
                controller.clear();
              } else {
                controller.closeView(controller.text);
              }
            },
            style: prism.ButtonStyle.from(
              foregroundColor: scheme.onSurfaceVariant,
              fixedSize: const Size.square(44),
              minimumSize: const Size.square(44),
              padding: EdgeInsets.zero,
              tapTargetSize: prism.TapTargetSize.shrinkWrap,
              pressLook: prism.PressLook.none,
            ),
            icon: glyph.GlyphIcon(
              hasText ? glyph.Glyphs.clearField : glyph.Glyphs.close,
              size: 21,
              fill: 1,
            ),
          ),
        );
      },
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
            final icon = loading
                ? SizedBox.square(
                    key: const ValueKey('loading-cancel'),
                    dimension: 20,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CircularProgressIndicator(
                          strokeWidth: 2,
                          color: scheme.primary,
                        ),
                        Icon(
                          Icons.close_rounded,
                          size: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                  )
                : const glyph.GlyphIcon(
                    glyph.Glyphs.clearField,
                    size: 20,
                    fill: 1,
                  );
            return prism.ElasticPress(
              child: prism.IconButton(
                key: const ValueKey('clear'),
                tooltip: loading ? '取消搜索' : '清除',
                onPressed: onClear,
                style: prism.ButtonStyle.from(
                  foregroundColor: scheme.onSurfaceVariant,
                  fixedSize: const Size.square(36),
                  minimumSize: const Size.square(36),
                  padding: EdgeInsets.zero,
                  tapTargetSize: prism.TapTargetSize.shrinkWrap,
                  pressLook: prism.PressLook.none,
                ),
                icon: icon,
              ),
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
