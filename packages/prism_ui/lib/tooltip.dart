import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:prism_ui/shape.dart';
import 'package:prism_ui/theme_data.dart';
import 'package:prism_ui/typography.dart';

/// A short message over a widget, shown by hovering or long pressing it.
class Tooltip extends StatelessWidget {
  const Tooltip({
    super.key,
    required this.message,
    this.preferBelow = true,
    this.triggerMode = TooltipTriggerMode.longPress,
    this.excludeFromSemantics = false,
    required this.child,
  });

  final String message;
  final bool preferBelow;
  final TooltipTriggerMode triggerMode;
  final bool excludeFromSemantics;
  final Widget child;

  static const _verticalOffset = 24.0;

  @override
  Widget build(BuildContext context) {
    if (message.isEmpty) {
      return child;
    }
    return RawTooltip(
      semanticsTooltip: excludeFromSemantics ? null : message,
      tooltipBuilder: (context, animation) => FadeTransition(
        opacity: animation,
        child: _TooltipBox(message: message),
      ),
      triggerMode: triggerMode,
      positionDelegate: (position) => positionDependentBox(
        size: position.overlaySize,
        childSize: position.tooltipSize,
        target: position.target,
        verticalOffset: _verticalOffset,
        preferBelow: preferBelow,
      ),
      ignorePointer: true,
      child: child,
    );
  }
}

class _TooltipBox extends StatelessWidget {
  const _TooltipBox({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final desktop = switch (defaultTargetPlatform) {
      TargetPlatform.macOS ||
      TargetPlatform.linux ||
      TargetPlatform.windows => true,
      TargetPlatform.android ||
      TargetPlatform.fuchsia ||
      TargetPlatform.iOS => false,
    };
    final dark = Theme.brightnessOf(context) == Brightness.dark;
    final style = AppTextStyle.subheadline
        .of(context)
        .copyWith(
          color: dark ? Colors.black : Colors.white,
          fontSize: desktop ? 12 : 14,
        );
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: desktop ? 24 : 32),
      child: DefaultTextStyle(
        style: style,
        child: Container(
          decoration: ShapeDecoration(
            shape: AppShape.xs,
            color: dark ? const Color(0xE6FFFFFF) : const Color(0xE6616161),
          ),
          padding: EdgeInsets.symmetric(
            horizontal: desktop ? 8 : 16,
            vertical: 4,
          ),
          child: Center(
            widthFactor: 1,
            heightFactor: 1,
            child: Text(message, style: style),
          ),
        ),
      ),
    );
  }
}
