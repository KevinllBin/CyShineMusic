import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';

class LiquidGlassFabMenuAction {
  const LiquidGlassFabMenuAction({
    required this.icon,
    required this.label,
    this.onPressed,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool selected;
}

/// The discovery and paging FABs share one bottom-anchored liquid surface.
class LiquidGlassFabMenu extends StatefulWidget {
  const LiquidGlassFabMenu({
    super.key,
    required this.label,
    required this.icon,
    required this.expanded,
    required this.onToggle,
    required this.actions,
    this.loading = false,
  });

  final String label;
  final IconData icon;
  final bool expanded;
  final VoidCallback onToggle;
  final List<LiquidGlassFabMenuAction> actions;
  final bool loading;

  @override
  State<LiquidGlassFabMenu> createState() => _LiquidGlassFabMenuState();
}

class _LiquidGlassFabMenuState extends State<LiquidGlassFabMenu> {
  late bool _wide = widget.expanded;

  @override
  void didUpdateWidget(covariant LiquidGlassFabMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.expanded) _wide = true;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textScaler = MediaQuery.textScalerOf(context);
    final rowHeight = math.max(48.0, textScaler.scale(14) * 1.25 + 24);
    final triggerHeight = math.max(56.0, rowHeight);
    final labelPainter = TextPainter(
      text: TextSpan(
        text: widget.label,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      textDirection: Directionality.of(context),
      textScaler: textScaler,
    )..layout();
    final labelWidth = labelPainter.width;
    labelPainter.dispose();

    return LayoutBuilder(
      builder: (context, constraints) {
        final openWidth = math.min(232.0, constraints.maxWidth);
        final closedWidth = math.min(
          openWidth,
          math.max(128.0, labelWidth + 64),
        );
        final openHeight = math.max(
          triggerHeight,
          math.min(
            widget.actions.length * rowHeight + triggerHeight + 13,
            constraints.maxHeight,
          ),
        );

        Widget trigger() => TextButton(
          onPressed: widget.onToggle,
          style: TextButton.styleFrom(
            foregroundColor: scheme.onSurface,
            minimumSize: Size(0, triggerHeight),
            padding: const EdgeInsets.symmetric(horizontal: 16),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.loading)
                const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(
                  widget.expanded ? Icons.close_rounded : widget.icon,
                  size: 22,
                ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        );

        return SizedBox(
          width: _wide ? openWidth : closedWidth,
          height: _wide ? openHeight : triggerHeight,
          child: LiquidGlassMorph(
            alignment: Alignment.bottomRight,
            motion: LiquidGlassMorphMotion.fluid,
            smoothness: 28,
            style: LiquidGlassFab.defaultStyle.copyWith(
              shape: LiquidGlassShape.continuousRoundedRectangle(
                cornerRadius: widget.expanded ? 24 : triggerHeight / 2,
              ),
              color: scheme.surfaceContainerHigh.withValues(alpha: 0.32),
              blur: 4,
            ),
            onEnd: () {
              if (_wide && !widget.expanded) setState(() => _wide = false);
            },
            child: widget.expanded
                ? SizedBox(
                    key: const ValueKey('liquid-fab-open'),
                    width: openWidth,
                    height: openHeight,
                    child: Material(
                      type: MaterialType.transparency,
                      child: Column(
                        children: [
                          Expanded(
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  for (final action in widget.actions)
                                    Semantics(
                                      selected: action.selected,
                                      child: TextButton.icon(
                                        onPressed: action.onPressed,
                                        style: TextButton.styleFrom(
                                          alignment: Alignment.centerLeft,
                                          foregroundColor: scheme.onSurface,
                                          disabledForegroundColor:
                                              action.selected
                                              ? scheme.primary
                                              : scheme.onSurface.withValues(
                                                  alpha: 0.38,
                                                ),
                                          minimumSize: Size(0, rowHeight),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                          ),
                                        ),
                                        icon: Icon(action.icon, size: 22),
                                        label: Text(action.label),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          const Divider(height: 1),
                          SizedBox(height: triggerHeight, child: trigger()),
                        ],
                      ),
                    ),
                  )
                : SizedBox(
                    key: const ValueKey('liquid-fab-closed'),
                    width: closedWidth,
                    height: triggerHeight,
                    child: Material(
                      type: MaterialType.transparency,
                      child: trigger(),
                    ),
                  ),
          ),
        );
      },
    );
  }
}
