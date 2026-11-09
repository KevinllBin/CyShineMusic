import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_ui/prism_ui.dart' as prism;

import '../../../core/models/enums.dart';
import '../../../core/storage/settings_store.dart';
import '../../../theme/app_motion.dart';
import '../search_controller.dart';

class SourceFilterChips extends ConsumerWidget {
  const SourceFilterChips({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final selected = ref.watch(searchControllerProvider).source;
    final settings = ref.watch(settingsProvider);
    final sources = [
      MusicSource.all,
      for (final source in settings.discoverySourceOrder)
        if (settings.enabledSearchSources.contains(source)) source,
    ];
    final selectedIndex = sources.indexOf(selected);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final duration = reduceMotion ? Duration.zero : AppMotion.medium;

    final content = LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = constraints.maxWidth / sources.length;
        return Stack(
          children: [
            AnimatedPositioned(
              left: (selectedIndex < 0 ? 0 : selectedIndex) * itemWidth,
              top: 0,
              bottom: 0,
              width: itemWidth,
              duration: duration,
              curve: AppMotion.emphasized,
              child: const _SourceSlidingIndicator(
                key: ValueKey('search-source-indicator'),
              ),
            ),
            Row(
              children: [
                for (final source in sources)
                  Expanded(
                    child: _SourceChip(
                      key: ValueKey('search-source-${source.code}'),
                      source: source,
                      selected: selected == source,
                      onTap: () => ref
                          .read(searchControllerProvider.notifier)
                          .setSource(source),
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    );
    final liquidGlass = prism.LiquidGlassScope.of(context);
    final surface = liquidGlass
        ? ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: prism.LiquidGlass(
              borderRadius: BorderRadius.circular(16),
              style: prism.LiquidGlassStyle.pill(
                prism.Theme.of(context).colorScheme,
              ),
              child: content,
            ),
          )
        : DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: 0.28),
              ),
              boxShadow: [
                BoxShadow(
                  color: scheme.shadow.withValues(alpha: 0.07),
                  blurRadius: 16,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: content,
          );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: SizedBox(
        key: const ValueKey('search-source-filter'),
        height: 42,
        child: Padding(padding: const EdgeInsets.all(3), child: surface),
      ),
    );
  }
}

class _SourceSlidingIndicator extends StatelessWidget {
  const _SourceSlidingIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.secondaryContainer.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: scheme.primary.withValues(alpha: 0.10)),
          boxShadow: [
            BoxShadow(
              color: scheme.primary.withValues(alpha: 0.10),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
      ),
    );
  }
}

class _SourceChip extends StatefulWidget {
  const _SourceChip({
    super.key,
    required this.source,
    required this.selected,
    required this.onTap,
  });

  final MusicSource source;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_SourceChip> createState() => _SourceChipState();
}

class _SourceChipState extends State<_SourceChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scale;

  @override
  void initState() {
    super.initState();
    _scale = AnimationController.unbounded(vsync: this, value: 1);
  }

  @override
  void dispose() {
    _scale.dispose();
    super.dispose();
  }

  void _springTo(double target) {
    if (MediaQuery.disableAnimationsOf(context)) {
      _scale.value = target;
      return;
    }
    _scale.animateWith(
      SpringSimulation(AppMotion.expressiveSpring, _scale.value, target, 0),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final duration = reduceMotion ? Duration.zero : AppMotion.medium;
    final foreground = widget.selected
        ? scheme.onSecondaryContainer
        : scheme.onSurfaceVariant;

    return SizedBox.expand(
      child: Semantics(
        button: true,
        selected: widget.selected,
        label: '${widget.source.label}音乐来源',
        excludeSemantics: true,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(13),
          clipBehavior: Clip.antiAlias,
          child: AnimatedBuilder(
            animation: _scale,
            builder: (context, child) =>
                Transform.scale(scale: _scale.value, child: child),
            child: InkWell(
              onTap: widget.onTap,
              onHighlightChanged: (highlighted) =>
                  _springTo(highlighted ? 0.94 : 1),
              borderRadius: BorderRadius.circular(13),
              overlayColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.pressed)) {
                  return scheme.primary.withValues(alpha: 0.12);
                }
                if (states.contains(WidgetState.hovered) ||
                    states.contains(WidgetState.focused)) {
                  return scheme.primary.withValues(alpha: 0.08);
                }
                return null;
              }),
              child: AnimatedDefaultTextStyle(
                duration: duration,
                curve: AppMotion.emphasized,
                style: TextStyle(
                  color: foreground,
                  fontSize: 12,
                  fontWeight: widget.selected
                      ? FontWeight.w600
                      : FontWeight.w500,
                  height: 1,
                  letterSpacing: 0,
                ),
                child: Center(
                  child: Text(
                    widget.source.label,
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
