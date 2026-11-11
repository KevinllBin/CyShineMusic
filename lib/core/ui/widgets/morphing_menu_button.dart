import 'package:flutter/material.dart';

import '../../../theme/app_motion.dart';
import 'morphing_menu_motion.dart';

export 'morphing_menu_motion.dart' show MorphingMenuMotionStyle;

class MorphingMenuAction {
  const MorphingMenuAction({
    required this.label,
    required this.leading,
    this.onSelected,
    this.danger = false,
    this.showLeading = true,
  });

  final String label;
  final Widget leading;
  final VoidCallback? onSelected;
  final bool danger;
  final bool showLeading;
}

/// Uses the original Material popup while keeping every song/playlist action.
class MorphingMenuButton extends StatelessWidget {
  const MorphingMenuButton({
    super.key,
    required this.tooltip,
    required this.actions,
    this.icon = Icons.more_vert_rounded,
    this.buttonBuilder,
    this.width = 280,
    this.motionStyle = MorphingMenuMotionStyle.list,
  }) : assert(width > 0);

  final String tooltip;
  final List<MorphingMenuAction> actions;
  final IconData icon;
  final Widget Function(Widget button)? buttonBuilder;
  final double width;
  final MorphingMenuMotionStyle motionStyle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final button = SizedBox.square(
      dimension: 44,
      child: PopupMenuButton<VoidCallback>(
        tooltip: tooltip,
        enabled: actions.isNotEmpty,
        useRootNavigator: true,
        position: PopupMenuPosition.under,
        popUpAnimationStyle: const AnimationStyle(duration: AppMotion.medium),
        color: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        elevation: 3,
        menuPadding: const EdgeInsets.symmetric(vertical: 6),
        constraints: BoxConstraints(minWidth: 160, maxWidth: width),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        style: IconButton.styleFrom(visualDensity: VisualDensity.compact),
        icon: Icon(icon, size: 21),
        onSelected: (action) {
          if (context.mounted) action();
        },
        itemBuilder: (context) => [
          for (final action in actions)
            PopupMenuItem<VoidCallback>(
              value: action.onSelected,
              enabled: action.onSelected != null,
              child: IconTheme(
                data: IconThemeData(
                  size: 20,
                  color: action.danger ? scheme.error : scheme.onSurfaceVariant,
                ),
                child: Row(
                  children: [
                    if (action.showLeading) ...[
                      action.leading,
                      const SizedBox(width: 12),
                    ],
                    Flexible(
                      child: Text(
                        action.label,
                        style: action.danger
                            ? TextStyle(color: scheme.error)
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
    return buttonBuilder?.call(button) ?? button;
  }
}
