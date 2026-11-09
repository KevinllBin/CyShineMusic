// SPDX-License-Identifier: GPL-3.0-only
import 'dart:math';
import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart';
import 'package:prism_ui/icons/icons.dart';

class PrismColorSwatches extends StatelessWidget {
  const PrismColorSwatches({
    super.key,
    required this.colors,
    required this.selected,
    required this.onSelect,
    required this.onEdit,
    required this.onDelete,
    required this.onAdd,
    required this.systemColor,
  });

  static const double _minGap = 6;

  // Lines the dots, not their selection rings, up with the rows' text.
  static const double _inset = 16 - (_ColorSwatch.size - _ColorSwatch.dot) / 2;

  final List<int?> colors;
  final int? selected;
  final ValueChanged<int?> onSelect;
  final ValueChanged<int> onEdit;
  final ValueChanged<int> onDelete;
  final VoidCallback onAdd;
  final Color systemColor;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final level = context.raisedSurfaceLevel;
    return Container(
      padding: const EdgeInsets.all(_inset),
      decoration: ShapeDecoration(
        color: level.colorOf(colorScheme),
        shape: AppShape.xl,
      ),
      child: SurfaceScope(
        level: level,
        child: LayoutBuilder(
          builder: (_, constraints) {
            const cell = _ColorSwatch.size;
            final width = constraints.maxWidth;
            final columns = max(
              1,
              ((width + _minGap) / (cell + _minGap)).floor(),
            );
            final gap = columns > 1
                ? ((width - columns * cell) / (columns - 1)).floorToDouble()
                : 0.0;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final color in colors)
                  _ColorSwatch(
                    color: color == null ? null : Color(color),
                    systemColor: systemColor,
                    isSelected: color == selected,
                    label: color == null ? '跟随系统' : Color(color).hex,
                    onPressed: () => onSelect(color),
                    menuItems: color == null
                        ? null
                        : [
                            PopupMenuItem(
                              glyph: AppGlyphs.edit,
                              label: '编辑',
                              onPressed: () => onEdit(color),
                            ),
                            PopupMenuItem(
                              danger: true,
                              glyph: AppGlyphs.delete,
                              label: '删除',
                              onPressed: () => onDelete(color),
                            ),
                          ],
                  ),
                _AddColorButton(onPressed: onAdd),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    required this.color,
    required this.systemColor,
    required this.isSelected,
    required this.label,
    required this.onPressed,
    this.menuItems,
  });

  static const double size = 44;
  static const double dot = 32;
  static const double _ring = 2.5;
  static const _duration = Duration(milliseconds: 200);

  static const double _badge = 20;

  /// Null follows the system's accent color, [systemColor].
  final Color? color;
  final Color systemColor;
  final bool isSelected;
  final String label;
  final VoidCallback onPressed;
  final List<PopupMenuItem>? menuItems;

  @override
  Widget build(BuildContext context) {
    final fill = color ?? systemColor;
    final selected = isSelected;
    final check = ThemeData.estimateBrightnessForColor(fill) == Brightness.dark
        ? Colors.white
        : Colors.black;
    final swatch = SizedBox.square(
      dimension: size,
      child: PressSurface(
        fill: Colors.transparent,
        shape: AppShape.circle,
        ringStandsOff: selected,
        selected: selected,
        childFills: true,
        onPressed: onPressed,
        child: Semantics(
          label: label,
          child: Stack(
            alignment: Alignment.center,
            children: [
              AnimatedOpacity(
                opacity: selected ? 1 : 0,
                duration: _duration,
                child: DecoratedBox(
                  decoration: ShapeDecoration(
                    shape: AppShape.circle.copyWith(
                      side: BorderSide(color: fill, width: _ring),
                    ),
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
              SizedBox.square(
                dimension: dot,
                child: DecoratedBox(
                  decoration: ShapeDecoration(
                    color: fill,
                    shape: AppShape.circle,
                  ),
                ),
              ),
              if (color == null)
                const Positioned(
                  right: 0,
                  bottom: 0,
                  child: _EyedropperBadge(size: _badge),
                ),
              AnimatedScale(
                scale: selected ? 1 : 0,
                duration: _duration,
                curve: Curves.easeOutBack,
                child: GlyphIcon(
                  AppGlyphs.check,
                  size: 18,
                  fill: 1,
                  color: check,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final menuItems = this.menuItems;
    if (menuItems == null) {
      return swatch;
    }
    return ContextMenuRegion(menuItems: menuItems, child: swatch);
  }
}

class _EyedropperBadge extends StatelessWidget {
  const _EyedropperBadge({required this.size});

  static const double _gap = 2;

  final double size;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(_gap),
      decoration: ShapeDecoration(
        color: context.surfaceLevel.colorOf(colorScheme),
        shape: AppShape.circle,
      ),
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: context.raisedSurfaceLevel.colorOf(colorScheme),
          shape: AppShape.circle,
        ),
        child: Center(
          child: GlyphIcon(
            AppGlyphs.eyedropper,
            size: size - _gap * 2 - 4,
            color: colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}

class _AddColorButton extends StatelessWidget {
  const _AddColorButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return Tooltip(
      message: '添加颜色',
      child: SizedBox.square(
        dimension: _ColorSwatch.size,
        child: PressSurface(
          fill: Colors.transparent,
          shape: AppShape.circle,
          childFills: true,
          onPressed: onPressed,
          child: Center(
            child: Container(
              width: _ColorSwatch.dot,
              height: _ColorSwatch.dot,
              decoration: ShapeDecoration(
                color: context.raisedSurfaceLevel.colorOf(colorScheme),
                shape: AppShape.circle,
              ),
              child: GlyphIcon(
                AppGlyphs.add,
                size: 20,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
