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
  }) : _close = false;

  const AppNavigationButton.close({
    super.key,
    required this.onPressed,
    this.tooltip = '关闭',
    this.foregroundColor,
  }) : _close = true;

  final VoidCallback? onPressed;
  final String tooltip;
  final Color? foregroundColor;
  final bool _close;

  @override
  Widget build(BuildContext context) => prism.TonalButtonTheme(
    size: prism.TonalButtonSize.bar,
    glass: prism.LiquidGlassScope.of(context),
    child: prism.ElasticPress(
      enabled: onPressed != null,
      child: prism.IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        style: foregroundColor == null
            ? null
            : prism.ButtonStyle.from(
                foregroundColor: foregroundColor,
                disabledForegroundColor: foregroundColor!.withValues(
                  alpha: 0.38,
                ),
              ),
        icon: glyph.GlyphIcon(
          _close
              ? glyph.Glyphs.close
              : glyph.Glyphs.backFor(prism.Theme.of(context).platform),
          size: prism.TonalButtonSize.bar.icon,
        ),
      ),
    ),
  );
}
