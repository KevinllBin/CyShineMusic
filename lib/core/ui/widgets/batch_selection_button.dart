import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart' as prism;
import 'package:prism_ui/icons/icons.dart' as glyph;

/// Matches the Songs header's Prism selection control.
class BatchSelectionButton extends StatelessWidget {
  const BatchSelectionButton({
    super.key,
    required this.onPressed,
    this.allSelected = false,
    this.tooltip,
  });

  final VoidCallback? onPressed;
  final bool allSelected;
  final String? tooltip;

  @override
  Widget build(BuildContext context) => prism.TonalButtonTheme(
    size: prism.TonalButtonSize.bar,
    glass: prism.LiquidGlassScope.of(context),
    child: prism.ElasticPress(
      enabled: onPressed != null,
      child: prism.IconButton(
        tooltip: tooltip ?? (allSelected ? '取消全选' : '全选'),
        onPressed: onPressed,
        icon: glyph.GlyphIcon(
          allSelected ? glyph.AppGlyphs.deselect : glyph.AppGlyphs.selectAll,
          size: prism.TonalButtonSize.bar.icon,
        ),
      ),
    ),
  );
}
