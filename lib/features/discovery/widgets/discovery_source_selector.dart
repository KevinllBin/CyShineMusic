import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/app_motion.dart';
import '../discovery_controller.dart';

class DiscoverySourceSelector extends ConsumerWidget {
  const DiscoverySourceSelector({super.key, this.pageController});

  /// 传入发现页的 pager 后，胶囊指示条连续跟随页面滑动进度；
  /// 不传（或 controller 还没挂载）时退化为按选中项动画。
  final PageController? pageController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedDiscoverySourceProvider);
    final selectedIndex = math.max(0, kDiscoverySources.indexOf(selected));
    final scheme = Theme.of(context).colorScheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Container(
        key: const ValueKey('discovery-source-filter'),
        height: 38,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: scheme.surfaceContainer,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.22),
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth / kDiscoverySources.length;
            final indicator = DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.secondaryContainer,
                borderRadius: BorderRadius.circular(9),
              ),
            );
            final controller = pageController;
            return Stack(
              children: [
                if (controller != null)
                  AnimatedBuilder(
                    animation: controller,
                    builder: (context, child) {
                      final page = controller.hasClients
                          ? (controller.page ??
                                controller.initialPage.toDouble())
                          : selectedIndex.toDouble();
                      return Positioned(
                        left:
                            page.clamp(
                              0.0,
                              (kDiscoverySources.length - 1).toDouble(),
                            ) *
                            width,
                        top: 0,
                        bottom: 0,
                        width: width,
                        child: child!,
                      );
                    },
                    child: indicator,
                  )
                else
                  AnimatedPositioned(
                    left: selectedIndex * width,
                    top: 0,
                    bottom: 0,
                    width: width,
                    duration: reduceMotion ? Duration.zero : AppMotion.medium,
                    curve: AppMotion.emphasized,
                    child: indicator,
                  ),
                Row(
                  children: [
                    for (final source in kDiscoverySources)
                      Expanded(
                        child: Semantics(
                          button: true,
                          selected: selected == source,
                          child: InkWell(
                            key: ValueKey('discovery-source-${source.code}'),
                            borderRadius: BorderRadius.circular(9),
                            onTap: () =>
                                ref
                                        .read(
                                          selectedDiscoverySourceProvider
                                              .notifier,
                                        )
                                        .state =
                                    source,
                            child: Center(
                              child: Text(
                                source.label,
                                maxLines: 1,
                                overflow: TextOverflow.fade,
                                softWrap: false,
                                style: TextStyle(
                                  color: selected == source
                                      ? scheme.onSecondaryContainer
                                      : scheme.onSurfaceVariant,
                                  fontSize: 11.5,
                                  fontWeight: selected == source
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                                  height: 1,
                                  letterSpacing: 0,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
