import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/widgets.dart';

import 'package:prism_ui/context.dart';
import 'package:prism_ui/divider.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/l10n.dart';
import 'package:prism_ui/liquid_glass.dart';
import 'package:prism_ui/motion.dart';
import 'package:prism_ui/popup.dart';
import 'package:prism_ui/press_region.dart';
import 'package:prism_ui/shape.dart';
import 'package:prism_ui/surface.dart';
import 'package:prism_ui/theme_data.dart';
import 'package:prism_ui/typography.dart';

// Measured on UIEditMenuInteraction of iOS 27 (iPhone 17 Pro).
const _barHeight = 44.0;
const _barInset = 4.0;
const _cellPadding = 16.0;
const _cellPressInset = 2.0;
const _cellPressHeight = 32.0;
const _separatorHeight = 18.0;
// The pressed row of PopupMenu.
const _pressedDark = Color(0x40CCCCCC);
const _pressedLight = Color(0x66BCBCBC);
const _chevronSize = 36.0;
const _margin = 16.0;
const _lineGap = 15.0;
const _closedScale = 0.2;
const _cardWidth = 250.0;
const _cardRowHeight = 42.0;
const _cardInset = 8.0;
const _cardRowPadding = 12.0;
const _cardCorner = AppCorner.md + _cardInset;
const _holdMargin = 4.0;

final _openCurve = SpringCurve(
  const SpringDescription(mass: 1, stiffness: 522.9, damping: 38.87),
  seconds: 0.405,
);

final _unfoldCurve = SpringCurve(
  const SpringDescription(mass: 1, stiffness: 300, damping: 30),
  seconds: 0.45,
);

/// The menu a touch selection opens, a capsule of labels beside the selection
/// that unfolds into a card when they do not all fit. [selection] is in the
/// coordinates of the navigator the route is pushed on.
///
/// Picking an item only runs it. Whoever owns the selection decides what
/// follows, as the text widgets do with their toolbars: pop this route, or
/// change [items] and [selection] to keep it up for the new selection.
class EditMenuRoute extends PopupRoute<void> {
  EditMenuRoute({
    required this.items,
    required this.selection,
    required this.barrierLabel,
    this.elevated = false,
  }) : super(requestFocus: false);

  final ValueListenable<List<PopupMenuItem>> items;
  final ValueListenable<Rect> selection;

  /// Whether the menu opens from a sheet's [ElevatedSurfaceTheme], which lies
  /// below the navigator the menu is pushed on.
  final bool elevated;

  @override
  final String? barrierLabel;

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 405);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 150);

  @override
  Widget buildModalBarrier() => const SizedBox.shrink();

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final menu = _EditMenu(route: this, animation: animation);
    return elevated ? ElevatedSurfaceTheme(child: menu) : menu;
  }

  void _dismiss() {
    if (isCurrent) {
      navigator?.pop();
    }
  }
}

class _EditMenu extends StatefulWidget {
  const _EditMenu({required this.route, required this.animation});

  final EditMenuRoute route;
  final Animation<double> animation;

  @override
  State<_EditMenu> createState() => _EditMenuState();
}

class _EditMenuState extends State<_EditMenu>
    with SingleTickerProviderStateMixin {
  late final AnimationController _unfold = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
  );
  late final _unfolded = CurvedAnimation(parent: _unfold, curve: _unfoldCurve);
  late final _opened = CurvedAnimation(
    parent: widget.animation,
    curve: _openCurve,
    reverseCurve: Curves.easeIn,
  );

  // Stable, as a builder listening anew during the close would reach
  // notifiers their owner has already disposed.
  late final _menuChanged = Listenable.merge([
    widget.route.selection,
    widget.route.items,
  ]);

  @override
  void initState() {
    super.initState();
    widget.route.items.addListener(_foldOnNewItems);
  }

  void _foldOnNewItems() => _unfold.value = 0;

  @override
  void dispose() {
    widget.route.items.removeListener(_foldOnNewItems);
    _opened.dispose();
    _unfolded.dispose();
    _unfold.dispose();
    super.dispose();
  }

  List<double> _cellWidths(BuildContext context, TextStyle style) {
    final painter = TextPainter(
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    );
    try {
      return [
        for (final item in widget.route.items.value)
          ((painter
                    ..text = TextSpan(text: item.label, style: style)
                    ..layout())
                  .width
                  .ceilToDouble() +
              2 * _cellPadding),
      ];
    } finally {
      painter.dispose();
    }
  }

  int _fittingCells(List<double> widths, double maxWidth) {
    final total = widths.fold(2 * _barInset, (sum, width) => sum + width);
    if (total <= maxWidth) {
      return widths.length;
    }
    var used = 2 * _barInset + _chevronSize;
    var count = 0;
    for (final width in widths) {
      if (used + width > maxWidth) {
        break;
      }
      used += width;
      count++;
    }
    return math.max(count, 1);
  }

  Widget _buildBar(
    BuildContext context,
    TextStyle style,
    List<double> widths,
    int count,
  ) {
    final colorScheme = context.colorScheme;
    final items = widget.route.items.value;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: _barInset),
      child: Row(
        children: [
          for (var i = 0; i < count; i++) ...[
            if (i > 0)
              SizedBox(
                width: 0,
                child: OverflowBox(
                  maxWidth: 1,
                  child: SizedBox(
                    width: 1,
                    height: _separatorHeight,
                    child: ColoredBox(color: Divider.colorOf(context)),
                  ),
                ),
              ),
            // The highlight is smaller than the cell, the target is not.
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              excludeFromSemantics: true,
              onTap: () => items[i].onPressed?.call(),
              child: SizedBox(
                width: widths[i],
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: _cellPressInset,
                    ),
                    child: SizedBox(
                      height: _cellPressHeight,
                      child: PressRegion(
                        onTap: () => items[i].onPressed?.call(),
                        canRequestFocus: false,
                        shape: AppShape.full,
                        overlay: _pressOverlay(context),
                        child: Center(
                          child: Text(
                            items[i].label,
                            style: style,
                            maxLines: 1,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
          if (count < items.length) ...[
            const Spacer(),
            Semantics(
              button: true,
              label: UiLocalizations.of(context).more,
              child: SizedBox.square(
                dimension: _chevronSize,
                child: PressRegion(
                  onTap: _unfold.forward,
                  canRequestFocus: false,
                  excludeFromSemantics: true,
                  shape: AppShape.circle,
                  fill: colorScheme.onSurface.withValues(alpha: 0.05),
                  overlay: _pressOverlay(context),
                  child: const Center(
                    child: GlyphIcon(Glyphs.chevronForward, size: 18),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCard(BuildContext context) {
    final style = AppTextStyle.body.of(context);
    return Padding(
      padding: const EdgeInsets.all(_cardInset),
      child: Column(
        children: [
          for (final item in widget.route.items.value)
            SizedBox(
              height: _cardRowHeight,
              child: PressRegion(
                onTap: () => item.onPressed?.call(),
                canRequestFocus: false,
                shape: AppShape.all(AppCorner.md),
                overlay: _pressOverlay(context),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: _cardRowPadding,
                  ),
                  child: Row(
                    children: [
                      if (item.glyph case final glyph?) ...[
                        GlyphIcon(glyph, size: 20),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: Text(
                          item.label,
                          style: style,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  WidgetStateProperty<Color?> _pressOverlay(BuildContext context) {
    final pressed = Theme.brightnessOf(context) == Brightness.dark
        ? _pressedDark
        : _pressedLight;
    return WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.pressed) ? pressed : null,
    );
  }

  Widget _buildPane(
    BuildContext context,
    double corner,
    Rect hold,
    Widget child,
  ) {
    final colorScheme = context.colorScheme;
    if (LiquidGlassScope.of(context)) {
      return LiquidGlass(
        style: LiquidGlassStyle.editMenu(colorScheme),
        borderRadius: AppRadius.all(corner),
        hold: hold,
        steadyFrost: true,
        shadows: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
        child: child,
      );
    }
    return Surface(
      color: SurfaceLevel.floatingOf(colorScheme).colorOf(colorScheme),
      shadowColor: colorScheme.shadow.withValues(alpha: 0.6),
      elevation: 3,
      shape: AppShape.all(corner),
      child: child,
    );
  }

  Widget _buildMenu(BuildContext context, BoxConstraints constraints) {
    final padding = MediaQuery.paddingOf(context);
    final inset = MediaQuery.viewInsetsOf(context);
    final area = Rect.fromLTRB(
      _margin,
      padding.top,
      math.max(constraints.maxWidth - _margin, _margin),
      math.max(
        constraints.maxHeight - math.max(padding.bottom, inset.bottom),
        padding.top,
      ),
    );
    final selection = widget.route.selection.value;
    final style = AppTextStyle.subheadline.of(context);
    final widths = _cellWidths(context, style);
    final count = _fittingCells(widths, area.width);
    final fits = count == widths.length;
    final barWidth = fits
        ? widths.fold(2 * _barInset, (sum, width) => sum + width)
        : math.min(
            area.width,
            widths.take(count).fold(0.0, (sum, width) => sum + width) +
                2 * _barInset +
                _chevronSize,
          );
    final topBelow = selection.bottom + _lineGap;
    final topAbove = selection.top - _lineGap - _barHeight;
    final wantsBelow = selection.center.dy < area.center.dy;
    final below = wantsBelow
        ? topBelow + _barHeight <= area.bottom || topAbove < area.top
        : topAbove < area.top && topBelow + _barHeight <= area.bottom;
    final barTop = _clampTo(
      below ? topBelow : topAbove,
      area.top,
      area.bottom - _barHeight,
    );
    final barLeft = _clampTo(
      selection.center.dx - barWidth / 2,
      area.left,
      area.right - barWidth,
    );
    final cardHeight = math.min(
      widget.route.items.value.length * _cardRowHeight + 2 * _cardInset,
      area.height,
    );
    final cardWidth = math.min(_cardWidth, area.width);
    final cardLeft = _clampTo(
      selection.center.dx - cardWidth / 2,
      area.left,
      area.right - cardWidth,
    );
    final cardTop = _clampTo(barTop, area.top, area.bottom - cardHeight);
    final bar = _buildBar(context, style, widths, count);
    final barRect = Rect.fromLTWH(barLeft, barTop, barWidth, _barHeight);
    final sweep =
        (fits
                ? barRect
                : barRect.expandToInclude(
                    Rect.fromLTWH(cardLeft, cardTop, cardWidth, cardHeight),
                  ))
            .inflate(_holdMargin);
    return AnimatedBuilder(
      animation: Listenable.merge([_opened, _unfolded]),
      builder: (context, _) {
        final opened = _opened.value;
        final unfolded = _unfolded.value;
        final width = _lerp(barWidth, cardWidth, unfolded);
        final height = _lerp(_barHeight, cardHeight, unfolded);
        final left = _lerp(barLeft, cardLeft, unfolded);
        final top = _lerp(barTop, cardTop, unfolded);
        final scale = _closedScale + (1 - _closedScale) * opened;
        // A hold scales with its pane; undone so one capture lasts throughout.
        final origin = Offset(left + width / 2, below ? top : top + height);
        return Stack(
          children: [
            Positioned(
              left: left,
              top: top,
              width: width,
              height: height,
              child: Transform.scale(
                scale: scale,
                alignment: below ? Alignment.topCenter : Alignment.bottomCenter,
                child: LiquidGlassFade(
                  opacity: _opened,
                  child: _buildPane(
                    context,
                    _lerp(_barHeight / 2, _cardCorner, unfolded),
                    Rect.fromPoints(
                      origin + (sweep.topLeft - origin) / scale,
                      origin + (sweep.bottomRight - origin) / scale,
                    ).shift(Offset(-left, -top)),
                    Stack(
                      fit: StackFit.expand,
                      children: [
                        if (unfolded < 1)
                          Opacity(
                            opacity: (1 - unfolded).clamp(0.0, 1.0),
                            child: OverflowBox(
                              alignment: AlignmentDirectional.topStart,
                              minWidth: barWidth,
                              maxWidth: barWidth,
                              minHeight: _barHeight,
                              maxHeight: _barHeight,
                              child: bar,
                            ),
                          ),
                        if (unfolded > 0)
                          Opacity(
                            opacity: unfolded.clamp(0.0, 1.0),
                            child: OverflowBox(
                              alignment: AlignmentDirectional.topStart,
                              minWidth: cardWidth,
                              maxWidth: cardWidth,
                              minHeight: cardHeight,
                              maxHeight: cardHeight,
                              child: _buildCard(context),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final route = widget.route;
    return Stack(
      children: [
        Positioned.fill(
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) => route._dismiss(),
            onPointerPanZoomStart: (_) => route._dismiss(),
            onPointerSignal: (_) => route._dismiss(),
          ),
        ),
        // Otherwise a tap on an item reads as a tap outside, and the text
        // drops its focus and selection before the item runs.
        Positioned.fill(
          child: SurfaceScope(
            level: SurfaceLevel.floatingOf(context.colorScheme),
            child: LayoutBuilder(
              builder: (context, constraints) => ListenableBuilder(
                listenable: _menuChanged,
                builder: (context, _) => TapRegion(
                  groupId: SelectableRegion,
                  child: TextFieldTapRegion(
                    child: _buildMenu(context, constraints),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

double _lerp(double a, double b, double t) => a + (b - a) * t;

double _clampTo(double value, double low, double high) =>
    math.max(low, math.min(value, math.max(low, high)));
