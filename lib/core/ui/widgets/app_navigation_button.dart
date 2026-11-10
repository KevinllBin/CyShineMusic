import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart' as prism;
import 'package:prism_ui/icons/icons.dart' as glyph;

/// Shared page/sheet navigation using Prism's bar sizing and press feedback.
class AppNavigationButton extends StatelessWidget {
  const AppNavigationButton.back({
    super.key,
    required this.onPressed,
    this.tooltip = '返回上一页',
    this.foregroundColor,
    this.size = prism.TonalButtonSize.bar,
  }) : _close = false;

  const AppNavigationButton.close({
    super.key,
    required this.onPressed,
    this.tooltip = '关闭',
    this.foregroundColor,
    this.size = prism.TonalButtonSize.bar,
  }) : _close = true;

  final VoidCallback? onPressed;
  final String tooltip;
  final Color? foregroundColor;
  final prism.TonalButtonSize size;
  final bool _close;

  @override
  Widget build(BuildContext context) => Center(
    widthFactor: 1,
    heightFactor: 1,
    child: prism.TonalButtonTheme(
      size: size,
      glass: prism.LiquidGlassScope.of(context),
      child: prism.ElasticPress(
        enabled: onPressed != null,
        child: prism.IconButton(
          tooltip: tooltip,
          onPressed: onPressed,
          style: prism.ButtonStyle.from(
            foregroundColor: foregroundColor,
            disabledForegroundColor: foregroundColor?.withValues(alpha: 0.38),
            tapTargetSize: prism.TapTargetSize.padded,
          ),
          icon: glyph.GlyphIcon(
            _close
                ? glyph.Glyphs.close
                : glyph.Glyphs.backFor(prism.Theme.of(context).platform),
            size: size.icon,
          ),
        ),
      ),
    ),
  );
}
