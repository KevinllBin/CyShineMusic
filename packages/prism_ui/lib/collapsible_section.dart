import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:prism_ui/builder.dart';
import 'package:prism_ui/context.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/item_position.dart';
import 'package:prism_ui/prism_list.dart';
import 'package:prism_ui/shape.dart';
import 'package:prism_ui/surface.dart';
import 'package:prism_ui/text_style.dart';
import 'package:prism_ui/theme_data.dart';
import 'package:prism_ui/typography.dart';

import 'inherited.dart';

/// A titled section whose header folds its entries away. The entries unfold
/// with the section, and the ones nearest the middle of what fits on screen
/// fade in first.
class SliverCollapsibleSection extends StatelessWidget {
  final String label;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final bool collapsible;
  final bool initiallyExpanded;

  const SliverCollapsibleSection({
    super.key,
    required this.label,
    required this.itemCount,
    required this.itemBuilder,
    this.collapsible = true,
    this.initiallyExpanded = true,
  });

  static const _groupKey = Object();

  @override
  Widget build(BuildContext context) {
    return SliverCollapsibleGroups(
      groups: [
        CollapsibleGroup(key: _groupKey, label: label, itemCount: itemCount),
      ],
      itemBuilder: (context, _, index) => itemBuilder(context, index),
      collapsible: collapsible,
      initiallyExpanded: initiallyExpanded,
    );
  }
}

class CollapsibleGroup {
  /// Keeps whether the group is open while the groups around it change.
  final Object key;
  final String label;
  final int itemCount;
  final Widget? leading;
  final Widget? trailing;

  const CollapsibleGroup({
    required this.key,
    required this.label,
    required this.itemCount,
    this.leading,
    this.trailing,
  });
}

/// Folds each of [groups] under its header as [SliverCollapsibleSection]
/// does, building only the headers and entries in view.
class SliverCollapsibleGroups extends StatefulWidget {
  final List<CollapsibleGroup> groups;
  final Widget Function(BuildContext context, int group, int index) itemBuilder;
  final bool collapsible;
  final bool initiallyExpanded;

  /// Also orders the fade; a wrong guess shifts which entry leads it, not
  /// what ends up shown.
  final double estimatedItemExtent;

  const SliverCollapsibleGroups({
    super.key,
    required this.groups,
    required this.itemBuilder,
    this.collapsible = true,
    this.initiallyExpanded = false,
    this.estimatedItemExtent = SliverPrismList.defaultEstimatedItemExtent,
  });

  @override
  State<SliverCollapsibleGroups> createState() =>
      _SliverCollapsibleGroupsState();
}

class _SliverCollapsibleGroupsState extends State<SliverCollapsibleGroups>
    with TickerProviderStateMixin {
  static const _header = -1;
  static const _unfolding = -2;

  final _toggled = <Object>{};
  final _motions = <Object, CurvedAnimation>{};
  final _controllers = <Object, AnimationController>{};

  bool _isOpen(Object key, {required bool collapsible}) =>
      !collapsible || widget.initiallyExpanded != _toggled.contains(key);

  void _move(Object key, {required bool open}) {
    final controller = _controllers[key] ??= AnimationController(
      vsync: this,
      duration: UnfoldEntryTransition.duration,
      value: open ? 0 : 1,
    )..addStatusListener((status) => _settle(key, status));
    _motions[key] ??= UnfoldEntryTransition.curveOf(controller);
    open ? controller.forward() : controller.reverse();
  }

  void _settle(Object key, AnimationStatus status) {
    if (status.isAnimating) {
      return;
    }
    final controller = _controllers.remove(key);
    if (controller == null) {
      return;
    }
    setState(() {});
    _motions.remove(key)!.dispose();
    controller.dispose();
  }

  void _toggle(Object key) {
    setState(() {
      if (!_toggled.remove(key)) {
        _toggled.add(key);
      }
    });
    _move(key, open: _isOpen(key, collapsible: widget.collapsible));
  }

  @override
  void didUpdateWidget(SliverCollapsibleGroups oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.collapsible == widget.collapsible) {
      return;
    }
    for (final group in widget.groups) {
      final open = _isOpen(group.key, collapsible: widget.collapsible);
      if (open != _isOpen(group.key, collapsible: oldWidget.collapsible)) {
        _move(group.key, open: open);
      }
    }
  }

  @override
  void dispose() {
    for (final motion in _motions.values) {
      motion.dispose();
    }
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Widget _buildEntry(BuildContext context, int group, int index) =>
      ItemPositionProvider(
        position: ItemPosition.get(index, widget.groups[group].itemCount),
        child: widget.itemBuilder(context, group, index),
      );

  /// An entry is at least [kMinInteractiveDimension] tall, so these fill the
  /// screen whatever lies past them.
  Widget _buildUnfolding(BuildContext context, int group) {
    final count = widget.groups[group].itemCount;
    final height = MediaQuery.sizeOf(context).height;
    final visible = math.min(
      count.toDouble(),
      height / widget.estimatedItemExtent,
    );
    final unfolding = math.min(count, height ~/ kMinInteractiveDimension + 1);
    final animation = _motions[widget.groups[group].key]!;
    return SizeTransition(
      sizeFactor: animation,
      alignment: Alignment.topCenter,
      child: Column(
        children: [
          for (var index = 0; index < unfolding; index++)
            UnfoldEntryTransition(
              animation: animation,
              index: index,
              visibleCount: visible,
              child: _buildEntry(context, group, index),
            ),
        ],
      ),
    );
  }

  Widget _buildHeader(CollapsibleGroup group) {
    final collapsible = widget.collapsible;
    final unfold =
        _motions[group.key] ??
        (_isOpen(group.key, collapsible: collapsible)
            ? kAlwaysCompleteAnimation
            : kAlwaysDismissedAnimation);
    // Unkeyed, so headers update in place as a group jumps to the top.
    return MemoBuilder(
      inputs: [
        group.label,
        group.itemCount,
        group.leading,
        group.trailing,
        unfold,
        collapsible,
      ],
      builder: (_) => CollapsibleHeader(
        label: group.label,
        count: group.itemCount,
        leading: group.leading,
        trailing: group.trailing,
        unfold: unfold,
        onToggle: collapsible ? () => _toggle(group.key) : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final collapsible = widget.collapsible;
    final rows = <(int, int)>[];
    for (final (index, group) in widget.groups.indexed) {
      rows.add((index, _header));
      if (_motions.containsKey(group.key)) {
        rows.add((index, _unfolding));
      } else if (_isOpen(group.key, collapsible: collapsible)) {
        for (var item = 0; item < group.itemCount; item++) {
          rows.add((index, item));
        }
      }
    }
    return SliverPrismList(
      itemCount: rows.length,
      estimatedItemExtent: widget.estimatedItemExtent,
      itemBuilder: (context, row) {
        final (index, item) = rows[row];
        final group = widget.groups[index];
        return switch (item) {
          _header => _buildHeader(group),
          _unfolding => _buildUnfolding(context, index),
          _ => _buildEntry(context, index, item),
        };
      },
    );
  }
}

/// The header of a [SliverCollapsibleGroups] group, its chevron turning with
/// [unfold] from pointing at the label to pointing down.
class CollapsibleHeader extends StatefulWidget {
  final String label;
  final int count;
  final Widget? leading;
  final Widget? trailing;
  final Animation<double> unfold;
  final VoidCallback? onToggle;

  const CollapsibleHeader({
    super.key,
    required this.label,
    required this.count,
    this.leading,
    this.trailing,
    required this.unfold,
    this.onToggle,
  });

  @override
  State<CollapsibleHeader> createState() => _CollapsibleHeaderState();
}

class _CollapsibleHeaderState extends State<CollapsibleHeader> {
  static final _turns = Tween<double>(begin: -0.25, end: 0);

  late final _actions = <Type, Action<Intent>>{
    ActivateIntent: CallbackAction<ActivateIntent>(
      onInvoke: (_) => widget.onToggle?.call(),
    ),
  };
  var _focused = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final collapsible = widget.onToggle != null;
    final focused = collapsible && _focused;
    final leading = widget.leading;
    final trailing = widget.trailing;
    return FocusableActionDetector(
      enabled: collapsible,
      actions: _actions,
      mouseCursor: collapsible ? SystemMouseCursors.click : MouseCursor.defer,
      onShowFocusHighlight: (value) => setState(() => _focused = value),
      child: Semantics(
        button: collapsible,
        expanded: collapsible ? widget.unfold.value > 0 : null,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onToggle,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
            child: DecoratedBox(
              decoration: ShapeDecoration(
                shape: AppShape.md.copyWith(
                  side: focused ? focusRingSide(colorScheme) : BorderSide.none,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  spacing: 8,
                  children: [
                    ?leading,
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: widget.label),
                            TextSpan(
                              text: ' (${widget.count})',
                              style: TextStyle(
                                color: colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyle.headline.of(context),
                      ),
                    ),
                    if (trailing != null)
                      DefaultTextStyle.merge(
                        style: AppTextStyle.caption1
                            .of(context)
                            .toTabular
                            .copyWith(color: colorScheme.onSurfaceVariant),
                        child: trailing,
                      ),
                    RotationTransition(
                      turns: widget.unfold.drive(_turns),
                      child: GlyphIcon(
                        Glyphs.chevronDown,
                        size: 20,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// An entry unfolding from under its list's header; the entries nearest the
/// middle of the [visibleCount] that fit on screen fade in first.
class UnfoldEntryTransition extends StatelessWidget {
  static const duration = Duration(milliseconds: 240);
  static const _fade = 0.5;

  final Animation<double> animation;
  final int index;
  final double visibleCount;
  final Widget child;

  const UnfoldEntryTransition({
    super.key,
    required this.animation,
    required this.index,
    required this.visibleCount,
    required this.child,
  });

  static CurvedAnimation curveOf(AnimationController controller) =>
      CurvedAnimation(
        parent: controller,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );

  @override
  Widget build(BuildContext context) {
    final half = visibleCount / 2;
    final distance = (half - index - 0.5).abs() / half;
    final start = math.min(1.0, distance) * (1 - _fade);
    return SlideTransition(
      position: animation.drive(
        Tween(begin: Offset(0, -index - 0.5), end: Offset.zero),
      ),
      child: FadeTransition(
        opacity: animation.drive(
          CurveTween(curve: Interval(start, start + _fade)),
        ),
        child: child,
      ),
    );
  }
}
