import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../../../theme/app_motion.dart';
import 'playback_glyph.dart';
import 'toolbar_metrics.dart';

/// Animated sliding indicator pill that highlights the active tab in capsule navigation.
class ToolbarSlidingIndicator extends StatelessWidget {
  const ToolbarSlidingIndicator({
    super.key,
    required this.width,
    required this.height,
  });

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IgnorePointer(
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: scheme.secondaryContainer,
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }
}

/// Navigation item button for capsule navigation, including icon, label, and press physics.
class ToolbarAction extends StatefulWidget {
  const ToolbarAction({
    super.key,
    required this.tooltip,
    required this.label,
    required this.icon,
    required this.onPressed,
    required this.width,
    required this.height,
    this.selected = false,
    this.animatedPlayback = false,
  });

  final String tooltip;
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final double width;
  final double height;
  final bool selected;
  final bool animatedPlayback;

  @override
  State<ToolbarAction> createState() => _ToolbarActionState();
}

class _ToolbarActionState extends State<ToolbarAction>
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
    _scale.animateWith(
      SpringSimulation(AppMotion.expressiveSpring, _scale.value, target, 0),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final viewport = MediaQuery.sizeOf(context);
    final iconExtent = toolbarIconExtentFor(viewport);
    final iconSize = toolbarIconSizeFor(viewport);
    final labelFontSize = toolbarLabelFontSizeFor(viewport);
    final enabled = widget.onPressed != null;
    final selected = widget.selected;
    final foregroundColor = selected
        ? scheme.onSecondaryContainer
        : scheme.onSurfaceVariant.withValues(alpha: enabled ? 1 : 0.72);

    final child = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? widget.onPressed : null,
      onTapDown: enabled ? (_) => _springTo(0.92) : null,
      onTapUp: enabled ? (_) => _springTo(1) : null,
      onTapCancel: enabled ? () => _springTo(1) : null,
      child: AnimatedBuilder(
        animation: _scale,
        builder: (context, child) =>
            Transform.scale(scale: _scale.value, child: child),
        child: AnimatedContainer(
          duration: AppMotion.medium,
          curve: AppMotion.emphasized,
          width: widget.width,
          height: widget.height,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: iconExtent,
                  height: iconExtent,
                  child: Center(
                    child: widget.animatedPlayback
                        ? AnimatedPlaybackGlyph(color: foregroundColor)
                        : Icon(
                            widget.icon,
                            color: foregroundColor,
                            size: iconSize,
                          ),
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected
                        ? scheme.onSecondaryContainer
                        : scheme.onSurfaceVariant.withValues(
                            alpha: enabled ? 1 : 0.72,
                          ),
                    fontSize: labelFontSize,
                    fontWeight: FontWeight.w600,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return Tooltip(message: widget.tooltip, child: child);
  }
}
