import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:prism_ui/common_button.dart';
import 'package:prism_ui/context.dart';
import 'package:prism_ui/metrics.dart';
import 'package:prism_ui/theme_data.dart';
import 'package:prism_ui/typography.dart';

enum ListRowAlignment { center, top }

/// A row of leading, title, subtitle and trailing laid out as a Material 3
/// one- or two-line list tile, without the tile's ink, focus or semantics:
/// the card or row around it answers presses.
class ListRow extends StatelessWidget {
  const ListRow({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
    this.horizontalTitleGap,
    this.minVerticalPadding = listRowVerticalPadding,
    this.minHeight = listRowMinHeight,
    this.alignment = ListRowAlignment.center,
  });

  final Widget? leading;
  final Widget title;
  final Widget? subtitle;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;
  final double? horizontalTitleGap;
  final double minVerticalPadding;
  final double minHeight;
  final ListRowAlignment alignment;

  static const _defaultTitleGap = 16.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textDirection = Directionality.of(context);
    final safe = MediaQuery.paddingOf(context);
    final inset = padding.resolve(textDirection);
    final titleStyle = context.listTitleStyle;
    final subtitleStyle = context.listSubtitleStyle;
    final sideStyle = AppTextStyle.caption2
        .of(context, emphasized: true)
        .copyWith(color: colorScheme.onSurfaceVariant);
    final iconColor = colorScheme.onSurfaceVariant;
    // As ListTile does: an icon theme a slot sets must not recolor a button.
    final iconButtonColor =
        ButtonTheme.of(context).icon?.foregroundColor?.resolve(const {}) ??
        iconColor;
    final leading = this.leading;
    final subtitle = this.subtitle;
    final trailing = this.trailing;
    return IconTheme.merge(
      data: IconThemeData(color: iconColor),
      child: ButtonTheme.merge(
        data: ButtonThemeData(
          icon: ButtonStyle(
            foregroundColor: WidgetStatePropertyAll(iconButtonColor),
          ),
        ),
        child: _ListRowLayout(
          padding: EdgeInsets.fromLTRB(
            math.max(safe.left, inset.left),
            math.max(0, inset.top),
            math.max(safe.right, inset.right),
            math.max(0, inset.bottom),
          ),
          visualDensity: theme.visualDensity,
          textDirection: textDirection,
          titleBaseline: titleStyle.textBaseline ?? TextBaseline.alphabetic,
          subtitleBaseline:
              subtitleStyle.textBaseline ?? TextBaseline.alphabetic,
          horizontalTitleGap: horizontalTitleGap ?? _defaultTitleGap,
          minVerticalPadding: minVerticalPadding,
          minHeight: minHeight,
          alignment: alignment,
          leading: leading == null
              ? null
              : DefaultTextStyle(style: sideStyle, child: leading),
          title: DefaultTextStyle(style: titleStyle, child: title),
          subtitle: subtitle == null
              ? null
              : DefaultTextStyle(style: subtitleStyle, child: subtitle),
          trailing: trailing == null
              ? null
              : DefaultTextStyle(style: sideStyle, child: trailing),
        ),
      ),
    );
  }
}

enum _Slot { leading, title, subtitle, trailing }

class _ListRowLayout
    extends SlottedMultiChildRenderObjectWidget<_Slot, RenderBox> {
  const _ListRowLayout({
    required this.padding,
    required this.visualDensity,
    required this.textDirection,
    required this.titleBaseline,
    required this.subtitleBaseline,
    required this.horizontalTitleGap,
    required this.minVerticalPadding,
    required this.minHeight,
    required this.alignment,
    this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final EdgeInsets padding;
  final VisualDensity visualDensity;
  final TextDirection textDirection;
  final TextBaseline titleBaseline;
  final TextBaseline subtitleBaseline;
  final double horizontalTitleGap;
  final double minVerticalPadding;
  final double minHeight;
  final ListRowAlignment alignment;
  final Widget? leading;
  final Widget title;
  final Widget? subtitle;
  final Widget? trailing;

  @override
  Iterable<_Slot> get slots => _Slot.values;

  @override
  Widget? childForSlot(_Slot slot) => switch (slot) {
    _Slot.leading => leading,
    _Slot.title => title,
    _Slot.subtitle => subtitle,
    _Slot.trailing => trailing,
  };

  @override
  _RenderListRow createRenderObject(BuildContext context) => _RenderListRow(
    padding: padding,
    visualDensity: visualDensity,
    textDirection: textDirection,
    titleBaseline: titleBaseline,
    subtitleBaseline: subtitleBaseline,
    horizontalTitleGap: horizontalTitleGap,
    minVerticalPadding: minVerticalPadding,
    minHeight: minHeight,
    alignment: alignment,
  );

  @override
  void updateRenderObject(BuildContext context, _RenderListRow renderObject) {
    renderObject
      ..padding = padding
      ..visualDensity = visualDensity
      ..textDirection = textDirection
      ..titleBaseline = titleBaseline
      ..subtitleBaseline = subtitleBaseline
      ..horizontalTitleGap = horizontalTitleGap
      ..minVerticalPadding = minVerticalPadding
      ..minHeight = minHeight
      ..alignment = alignment;
  }
}

typedef _Sizes = ({double titleY, BoxConstraints text, Size size});

// The geometry of a Material 3 ListTile that is neither dense nor three-line.
class _RenderListRow extends RenderBox
    with SlottedContainerRenderObjectMixin<_Slot, RenderBox> {
  _RenderListRow({
    required EdgeInsets padding,
    required VisualDensity visualDensity,
    required TextDirection textDirection,
    required TextBaseline titleBaseline,
    required TextBaseline subtitleBaseline,
    required double horizontalTitleGap,
    required double minVerticalPadding,
    required double minHeight,
    required ListRowAlignment alignment,
  }) : _padding = padding,
       _visualDensity = visualDensity,
       _textDirection = textDirection,
       _titleBaseline = titleBaseline,
       _subtitleBaseline = subtitleBaseline,
       _horizontalTitleGap = horizontalTitleGap,
       _minVerticalPadding = minVerticalPadding,
       _minHeight = minHeight,
       _alignment = alignment;

  static const _minLeadingWidth = 24.0;
  static const _minTrailingWidth = 32.0;
  static const _maxSideHeight = 56.0;
  static const _titleBaselineY = 32.0;
  static const _subtitleBaselineY = 52.0;

  RenderBox? get _leading => childForSlot(_Slot.leading);
  RenderBox get _title => childForSlot(_Slot.title)!;
  RenderBox? get _subtitle => childForSlot(_Slot.subtitle);
  RenderBox? get _trailing => childForSlot(_Slot.trailing);

  @override
  Iterable<RenderBox> get children => [
    ?_leading,
    ?childForSlot(_Slot.title),
    ?_subtitle,
    ?_trailing,
  ];

  EdgeInsets _padding;

  set padding(EdgeInsets value) {
    if (_padding == value) {
      return;
    }
    _padding = value;
    markNeedsLayout();
  }

  VisualDensity _visualDensity;

  set visualDensity(VisualDensity value) {
    if (_visualDensity == value) {
      return;
    }
    _visualDensity = value;
    markNeedsLayout();
  }

  TextDirection _textDirection;

  set textDirection(TextDirection value) {
    if (_textDirection == value) {
      return;
    }
    _textDirection = value;
    markNeedsLayout();
  }

  TextBaseline _titleBaseline;

  set titleBaseline(TextBaseline value) {
    if (_titleBaseline == value) {
      return;
    }
    _titleBaseline = value;
    markNeedsLayout();
  }

  TextBaseline _subtitleBaseline;

  set subtitleBaseline(TextBaseline value) {
    if (_subtitleBaseline == value) {
      return;
    }
    _subtitleBaseline = value;
    markNeedsLayout();
  }

  double _horizontalTitleGap;

  set horizontalTitleGap(double value) {
    if (_horizontalTitleGap == value) {
      return;
    }
    _horizontalTitleGap = value;
    markNeedsLayout();
  }

  double _minVerticalPadding;

  set minVerticalPadding(double value) {
    if (_minVerticalPadding == value) {
      return;
    }
    _minVerticalPadding = value;
    markNeedsLayout();
  }

  double _minHeight;

  set minHeight(double value) {
    if (_minHeight == value) {
      return;
    }
    _minHeight = value;
    markNeedsLayout();
  }

  ListRowAlignment _alignment;

  set alignment(ListRowAlignment value) {
    if (_alignment == value) {
      return;
    }
    _alignment = value;
    markNeedsLayout();
  }

  Rect _content = Rect.zero;

  double get _titleGap => _horizontalTitleGap + _visualDensity.horizontal * 2;

  double _sideY(double height, double rowHeight) => switch (_alignment) {
    ListRowAlignment.center => (rowHeight - height) / 2,
    ListRowAlignment.top => _minVerticalPadding,
  };

  double _intrinsicWidth(
    double height,
    double Function(RenderBox box, double height) measure,
  ) {
    final inner = math.max(0.0, height - _padding.vertical);
    final leading = _leading;
    final subtitle = _subtitle;
    final trailing = _trailing;
    final leadingWidth = leading == null
        ? 0.0
        : math.max(measure(leading, inner), _minLeadingWidth) + _titleGap;
    return leadingWidth +
        math.max(
          measure(_title, inner),
          subtitle == null ? 0.0 : measure(subtitle, inner),
        ) +
        (trailing == null ? 0.0 : trailing.getMaxIntrinsicWidth(inner)) +
        _padding.horizontal;
  }

  @override
  double computeMinIntrinsicWidth(double height) => _intrinsicWidth(
    height,
    (box, height) => box.getMinIntrinsicWidth(height),
  );

  @override
  double computeMaxIntrinsicWidth(double height) => _intrinsicWidth(
    height,
    (box, height) => box.getMaxIntrinsicWidth(height),
  );

  @override
  double computeMinIntrinsicHeight(double width) {
    final inner = math.max(0.0, width - _padding.horizontal);
    final content =
        _title.getMinIntrinsicHeight(inner) +
        (_subtitle?.getMinIntrinsicHeight(inner) ?? 0) +
        2 * _minVerticalPadding;
    return math.max(_minHeight, content) + _padding.vertical;
  }

  @override
  double computeMaxIntrinsicHeight(double width) =>
      computeMinIntrinsicHeight(width);

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) {
    final parentData = _title.parentData! as BoxParentData;
    return (BaselineOffset(_title.getDistanceToActualBaseline(baseline)) +
            parentData.offset.dy)
        .offset;
  }

  _Sizes _computeSizes(
    ChildBaselineGetter getBaseline,
    ChildLayouter layoutChild,
    BoxConstraints constraints, {
    void Function(RenderBox child, Offset offset)? position,
  }) {
    final loose = constraints.deflate(_padding).loosen();
    final width = loose.maxWidth;
    final sideConstraints = loose.enforce(
      BoxConstraints(
        maxHeight: _maxSideHeight + _visualDensity.baseSizeAdjustment.dy,
      ),
    );
    final leading = _leading;
    final subtitle = _subtitle;
    final trailing = _trailing;
    final leadingSize = leading == null
        ? null
        : layoutChild(leading, sideConstraints);
    final trailingSize = trailing == null
        ? null
        : layoutChild(trailing, sideConstraints);
    final titleStart = leadingSize == null
        ? 0.0
        : math.max(_minLeadingWidth, leadingSize.width) + _titleGap;
    final trailingWidth = trailingSize == null
        ? 0.0
        : math.max(trailingSize.width + _titleGap, _minTrailingWidth);
    final text = loose.tighten(width: width - titleStart - trailingWidth);
    final titleHeight = layoutChild(_title, text).height;
    final ltr = _textDirection == TextDirection.ltr;
    final textX = ltr ? titleStart : trailingWidth;
    final double titleY;
    final double height;
    if (subtitle == null) {
      height = math.max(_minHeight, titleHeight + 2 * _minVerticalPadding);
      titleY = (height - titleHeight) / 2;
    } else {
      final subtitleHeight = layoutChild(subtitle, text).height;
      final titleBaseline =
          getBaseline(_title, text, _titleBaseline) ?? titleHeight;
      final subtitleBaseline =
          getBaseline(subtitle, text, _subtitleBaseline) ?? subtitleHeight;
      final targetTitleY = _titleBaselineY - titleBaseline;
      final targetSubtitleY =
          _subtitleBaselineY + _visualDensity.vertical * 2 - subtitleBaseline;
      final halfOverlap =
          math.max(targetTitleY + titleHeight - targetSubtitleY, 0) / 2;
      final idealTitleY = targetTitleY - halfOverlap;
      final idealSubtitleY = targetSubtitleY + halfOverlap;
      final compact =
          idealTitleY < _minVerticalPadding ||
          idealSubtitleY + subtitleHeight + _minVerticalPadding > _minHeight;
      position?.call(
        subtitle,
        Offset(
          textX,
          compact ? _minVerticalPadding + titleHeight : idealSubtitleY,
        ),
      );
      height = compact
          ? 2 * _minVerticalPadding + titleHeight + subtitleHeight
          : _minHeight;
      titleY = compact ? _minVerticalPadding : idealTitleY;
    }
    if (position != null) {
      position(_title, Offset(textX, titleY));
      if (leading != null && leadingSize != null) {
        position(
          leading,
          Offset(
            ltr ? 0 : width - leadingSize.width,
            _sideY(leadingSize.height, height),
          ),
        );
      }
      if (trailing != null && trailingSize != null) {
        position(
          trailing,
          Offset(
            ltr ? width - trailingSize.width : 0,
            _sideY(trailingSize.height, height),
          ),
        );
      }
    }
    final inner = constraints.deflate(_padding).constrain(Size(width, height));
    return (
      titleY: titleY,
      text: text,
      size: constraints.constrain(
        Size(
          inner.width + _padding.horizontal,
          inner.height + _padding.vertical,
        ),
      ),
    );
  }

  @override
  double? computeDryBaseline(
    covariant BoxConstraints constraints,
    TextBaseline baseline,
  ) {
    final sizes = _computeSizes(
      ChildLayoutHelper.getDryBaseline,
      ChildLayoutHelper.dryLayoutChild,
      constraints,
    );
    return (BaselineOffset(_title.getDryBaseline(sizes.text, baseline)) +
            sizes.titleY +
            _padding.top)
        .offset;
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) => _computeSizes(
    ChildLayoutHelper.getDryBaseline,
    ChildLayoutHelper.dryLayoutChild,
    constraints,
  ).size;

  @override
  void performLayout() {
    final origin = Offset(_padding.left, _padding.top);
    size = _computeSizes(
      ChildLayoutHelper.getBaseline,
      ChildLayoutHelper.layoutChild,
      constraints,
      position: (child, offset) =>
          (child.parentData! as BoxParentData).offset = origin + offset,
    ).size;
    _content = _padding.deflateRect(Offset.zero & size);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    for (final child in children) {
      context.paintChild(
        child,
        offset + (child.parentData! as BoxParentData).offset,
      );
    }
  }

  @override
  bool hitTestSelf(Offset position) => _content.contains(position);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    for (final child in children) {
      final parentData = child.parentData! as BoxParentData;
      final hit = result.addWithPaintOffset(
        offset: parentData.offset,
        position: position,
        hitTest: (result, transformed) =>
            child.hitTest(result, position: transformed),
      );
      if (hit) {
        return true;
      }
    }
    return false;
  }
}
