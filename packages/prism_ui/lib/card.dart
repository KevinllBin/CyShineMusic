import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:prism_ui/color.dart';
import 'package:prism_ui/common_button.dart';
import 'package:prism_ui/context.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/measure.dart';
import 'package:prism_ui/metrics.dart';
import 'package:prism_ui/shape.dart';
import 'package:prism_ui/surface.dart';
import 'package:prism_ui/theme_data.dart';
import 'package:prism_ui/typography.dart';

import 'fade_box.dart';
import 'press_surface.dart';
import 'scaffold.dart';
import 'text.dart';

class Info {
  final String label;
  final Glyph? glyph;

  const Info({required this.label, this.glyph});
}

class InfoHeader extends StatelessWidget {
  final Info info;
  final List<Widget> actions;
  final EdgeInsets? padding;
  final double? space;

  const InfoHeader({
    super.key,
    required this.info,
    this.padding,
    this.space,
    List<Widget>? actions,
  }) : actions = actions ?? const [];

  @override
  Widget build(BuildContext context) {
    final actionInset = 8.mAp(context);
    EdgeInsetsGeometry nextPadding = (padding ?? baseInfoEdgeInsetsOf(context));
    if (actions.isNotEmpty) {
      nextPadding = nextPadding.subtract(
        EdgeInsets.symmetric(vertical: actionInset),
      );
    }
    final lineHeight = MeasureScope.of(context).cardHeaderHeight;
    final rowHeight = info.glyph == null
        ? lineHeight
        : math.max(lineHeight, IconTheme.of(context).size ?? Glyph.size);
    return Padding(
      padding: nextPadding,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            flex: 1,
            child: Row(
              mainAxisSize: MainAxisSize.max,
              children: [
                if (info.glyph case final glyph?) ...[
                  GlyphIcon(
                    glyph,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 12),
                ],
                Flexible(
                  flex: 1,
                  child: TooltipText(
                    text: Text(
                      info.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.cardHeaderStyle,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (actions.isNotEmpty)
            SizedBox(
              height: rowHeight + actionInset * 2,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.end,
                spacing: space ?? appBarActionSpace,
                children: [...actions],
              ),
            ),
        ],
      ),
    );
  }
}

const commonCardIconSize = 20.0;

/// A pressable card or grouped row. A press highlights it as iOS 27
/// highlights a list cell; see `.agents/surfaces.md`.
class Card extends StatelessWidget {
  const Card({
    super.key,
    bool? isSelected,
    this.onPressed,
    this.radius,
    this.padding,
    this.enterAnimated = false,
    this.shape,
    this.isError = false,
    this.enterActionsOnRight = false,
    this.statesController,
    this.inert = false,
    this.fillsSelection = false,
    required this.child,
  }) : isSelected = isSelected ?? false;

  /// Ignores presses in the enabled colors, so toggling it animates nothing.
  final bool inert;
  final bool enterAnimated;
  final bool enterActionsOnRight;

  /// A selected card keeps its fill unless [fillsSelection]; callers mark it.
  final bool isSelected;
  final bool fillsSelection;
  final bool isError;
  final void Function()? onPressed;
  final Widget child;
  final EdgeInsets? padding;
  final double? radius;
  final OutlinedBorder? shape;
  final WidgetStatesController? statesController;

  static const _minimumSize = Size(64, 40);
  static const _minimumTapTarget = 48.0;

  /// The smallest a card draws, which a compact visual density shrinks.
  static BoxConstraints minimumOf(BuildContext context) =>
      Theme.of(context).visualDensity.effectiveConstraints(
        BoxConstraints(
          minWidth: _minimumSize.width,
          minHeight: _minimumSize.height,
        ),
      );

  /// [padding] as a card lays it out: a visual density can shorten it, but
  /// never narrow it.
  static EdgeInsets paddingOf(BuildContext context, EdgeInsets padding) {
    final adjustment = Theme.of(context).visualDensity.baseSizeAdjustment;
    final dx = math.max(0.0, adjustment.dx);
    return EdgeInsets.fromLTRB(
      math.max(0, padding.left + dx),
      math.max(0, padding.top + adjustment.dy),
      math.max(0, padding.right + dx),
      math.max(0, padding.bottom + adjustment.dy),
    );
  }

  static Size _tapTargetOf(ThemeData theme) {
    if (theme.tapTargetSize != TapTargetSize.padded) {
      return Size.zero;
    }
    final adjustment = theme.visualDensity.baseSizeAdjustment;
    return Size(
      _minimumTapTarget + adjustment.dx,
      _minimumTapTarget + adjustment.dy,
    );
  }

  bool get _filled => isSelected && fillsSelection;

  ({Color text, Color icon}) _contentColorsOf(ColorScheme colorScheme) {
    if (onPressed == null && !inert) {
      final disabled = colorScheme.onSurface.opacity38;
      return (text: disabled, icon: disabled);
    }
    if (isError) {
      return (
        text: colorScheme.onErrorContainer,
        icon: colorScheme.onErrorContainer,
      );
    }
    if (_filled) {
      return (text: colorScheme.onPrimary, icon: colorScheme.onPrimary);
    }
    return (text: colorScheme.onSurfaceVariant, icon: colorScheme.primary);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final level = context.raisedSurfaceLevel;
    final content = _contentColorsOf(colorScheme);
    final card = PressSurface(
      fill: switch ((isError, _filled)) {
        (true, _) => colorScheme.errorContainer,
        (_, true) => colorScheme.primary,
        _ => level.colorOf(colorScheme),
      },
      shape: shape ?? AppShape.all(radius ?? AppCorner.md),
      inkColor: _filled ? content.text : null,
      ringColor: isError ? colorScheme.error : null,
      padding: paddingOf(context, padding ?? EdgeInsets.zero),
      minimum: minimumOf(context),
      tapTarget: _tapTargetOf(theme),
      onPressed: onPressed,
      inert: inert,
      selected: isSelected,
      statesController: statesController,
      onKeyEvent: enterActionsOnRight ? _enterActionOnRight : null,
      child: DefaultTextStyle(
        style: AppTextStyle.subheadline
            .of(context, emphasized: true)
            .copyWith(color: content.text),
        child: IconTheme(
          data: IconTheme.of(
            context,
          ).merge(IconThemeData(color: content.icon, size: commonCardIconSize)),
          child: SurfaceScope(level: level, child: child),
        ),
      ),
    );
    return enterAnimated ? FadeScaleEnterBox(child: card) : card;
  }

  static KeyEventResult _enterActionOnRight(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.arrowRight) {
      return KeyEventResult.ignored;
    }
    final focusNode = FocusManager.instance.primaryFocus;
    final context = focusNode?.context;
    if (focusNode == null || context == null) {
      return KeyEventResult.ignored;
    }
    final action = focusNode.descendants
        .where((node) => node.skipTraversal && node.canRequestFocus)
        .firstOrNull;
    if (action != null) {
      action.requestFocus();
      return KeyEventResult.handled;
    }
    if (focusNode.skipTraversal ||
        context.findAncestorWidgetOfExactType<IconButton>() != null) {
      return KeyEventResult.ignored;
    }
    return focusNode.nextFocus()
        ? KeyEventResult.handled
        : KeyEventResult.ignored;
  }
}

/// A focus node left out of the traversal that walks between cards: a card
/// that must not be a stop, or an action inside a card reached by arrow right.
class SkipTraversalFocusNode extends FocusNode {
  @override
  bool get skipTraversal => true;
}
