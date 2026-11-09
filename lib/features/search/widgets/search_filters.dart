import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_ui/prism_ui.dart' as prism;
import 'package:prism_ui/icons/icons.dart' as glyph;

import '../../../core/models/enums.dart';
import '../../../core/models/search_category.dart';
import '../../../core/storage/settings_store.dart';
import '../../../theme/app_motion.dart';
import '../search_controller.dart';

class SearchPlatformMenu extends ConsumerWidget {
  const SearchPlatformMenu({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(
      searchControllerProvider.select((s) => s.source),
    );
    final enabled = ref.watch(
      settingsProvider.select((s) => s.enabledSearchSources),
    );
    final order = ref.watch(
      settingsProvider.select((s) => s.discoverySourceOrder),
    );
    final sources = [
      MusicSource.all,
      ...{...order, ...enabled}.where(enabled.contains),
    ];
    final liquidGlass = prism.LiquidGlassScope.of(context);
    return prism.PopupAnchor(
      key: const ValueKey('search-platform-menu-anchor'),
      targetBuilder: (open) {
        final selectedLabel = selected == MusicSource.all
            ? '全平台'
            : selected.label;
        return Semantics(
          button: true,
          label: '搜索平台：$selectedLabel',
          child: prism.TonalButtonTheme(
            size: prism.TonalButtonSize.bar,
            glass: liquidGlass,
            child: prism.ElasticPress(
              child: prism.IconButton(
                tooltip: '平台：$selectedLabel',
                onPressed: open,
                style: prism.ButtonStyle.from(
                  padding: EdgeInsets.zero,
                  tapTargetSize: prism.TapTargetSize.shrinkWrap,
                  pressLook: prism.PressLook.none,
                ),
                icon: const glyph.GlyphIcon(glyph.Glyphs.more),
              ),
            ),
          ),
        );
      },
      popupBuilder: (_) => prism.PopupMenu(
        items: [
          for (final source in sources)
            prism.PopupMenuItem(
              label: source == MusicSource.all ? '全平台' : source.label,
              checked: source == selected,
              executeImmediately: true,
              onPressed: () =>
                  ref.read(searchControllerProvider.notifier).setSource(source),
            ),
        ],
      ),
    );
  }
}

class SearchCategoryTabs extends ConsumerWidget {
  const SearchCategoryTabs({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(
      searchControllerProvider.select((s) => s.category),
    );
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 6),
      child: Row(
        children: [
          for (final category in SearchCategory.values)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Semantics(
                  selected: category == selected,
                  button: true,
                  child: AnimatedContainer(
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : AppMotion.short,
                    decoration: BoxDecoration(
                      color: category == selected
                          ? scheme.secondaryContainer
                          : scheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(999),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => ref
                            .read(searchControllerProvider.notifier)
                            .setCategory(category),
                        child: SizedBox(
                          height: 32,
                          child: Center(
                            child: Text(
                              category.label,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: category == selected
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                                color: category == selected
                                    ? scheme.onSecondaryContainer
                                    : scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
