import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/enums.dart';
import '../../../core/models/search_category.dart';
import '../../../core/storage/settings_store.dart';
import '../../../core/ui/radio_menu.dart';
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
    return RadioMenuAnchor(
      menuId: 'search-platform',
      optionsBuilder: () => [
        for (final source in sources)
          RadioMenuOption(
            id: source.code,
            label: source == MusicSource.all ? '全平台' : source.label,
            selected: source == selected,
            onSelected: () =>
                ref.read(searchControllerProvider.notifier).setSource(source),
          ),
      ],
      anchorBuilder: (context, expanded, onTapDown, onTap) => GestureDetector(
        onTapDown: onTapDown,
        child: TextButton(
          onPressed: onTap,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.only(left: 12, right: 6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(selected == MusicSource.all ? '全平台' : selected.label),
              AnimatedRotation(
                turns: expanded ? 0.5 : 0,
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : AppMotion.short,
                child: const Icon(Icons.expand_more_rounded, size: 20),
              ),
            ],
          ),
        ),
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
