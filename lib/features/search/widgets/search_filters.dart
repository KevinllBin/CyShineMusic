import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_ui/prism_ui.dart' as prism;

import '../../../core/models/enums.dart';
import '../../../core/models/search_category.dart';
import '../../../core/storage/settings_store.dart';
import '../../../core/ui/widgets/header_control_style.dart';
import '../../../theme/app_motion.dart';
import '../../discovery/discovery_controller.dart';
import '../search_controller.dart';
import 'platform_identity.dart';

class SearchPlatformMenu extends ConsumerWidget {
  const SearchPlatformMenu({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final searchSource = ref.watch(
      searchControllerProvider.select((s) => s.source),
    );
    final isSearchActive = ref.watch(
      searchControllerProvider.select((s) => s.isSearchActive),
    );
    final discoverySource = ref.watch(selectedDiscoverySourceProvider);
    final enabled = ref.watch(
      settingsProvider.select((s) => s.enabledSearchSources),
    );
    final order = ref.watch(
      settingsProvider.select((s) => s.discoverySourceOrder),
    );
    final selected = isSearchActive ? searchSource : discoverySource;
    final sources = isSearchActive
        ? [
            MusicSource.all,
            ...{...order, ...enabled}.where(enabled.contains),
          ]
        : order;
    final liquidGlass = prism.LiquidGlassScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    return prism.PopupAnchor(
      key: const ValueKey('search-platform-menu-anchor'),
      targetBuilder: (open) {
        final selectedLabel = selected.fullName;
        return Semantics(
          button: true,
          label: '${isSearchActive ? '搜索' : '发现'}平台：$selectedLabel',
          child: prism.TonalButtonTheme(
            size: prism.TonalButtonSize.bar,
            glass: liquidGlass,
            child: prism.ElasticPress(
              child: prism.IconButton(
                tooltip: '平台：$selectedLabel',
                onPressed: open,
                style: const prism.ButtonStyle(
                  fixedSize: Size(double.infinity, 52),
                  minimumSize: Size(88, 52),
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  tapTargetSize: prism.TapTargetSize.shrinkWrap,
                  pressLook: prism.PressLook.none,
                ).merge(headerControlButtonStyle(context)),
                icon: ExcludeSemantics(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedContainer(
                        duration: MediaQuery.disableAnimationsOf(context)
                            ? Duration.zero
                            : AppMotion.short,
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: selected.brandColor ?? scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Equal space for all short labels keeps the search bar
                      // steady when switching between QQ and Chinese names.
                      SizedBox(
                        width: MediaQuery.textScalerOf(context).scale(28),
                        child: Text(
                          selected.shortName,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.expand_more_rounded,
                        size: 16,
                        color: scheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
      popupBuilder: (_) => prism.PopupMenu(
        items: [
          for (final source in sources)
            prism.PopupMenuItem(
              label: source.fullName,
              leading: MusicPlatformIcon(source: source),
              checked: source == selected,
              executeImmediately: true,
              onPressed: () {
                if (isSearchActive) {
                  ref.read(searchControllerProvider.notifier).setSource(source);
                }
                // A concrete platform is also the next discovery default.
                // Aggregate search has no corresponding discovery page.
                if (source != MusicSource.all) {
                  ref.read(selectedDiscoverySourceProvider.notifier).state =
                      source;
                }
              },
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
