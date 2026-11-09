import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:prism_ui/checkbox.dart';
import 'package:prism_ui/divider.dart';
import 'package:prism_ui/context.dart';
import 'package:prism_ui/prism_list.dart';
import 'package:prism_ui/focus.dart';
import 'package:prism_ui/inherited.dart';
import 'package:prism_ui/item_position.dart';
import 'package:prism_ui/measure.dart';
import 'package:prism_ui/metrics.dart';
import 'package:prism_ui/models.dart';
import 'package:prism_ui/shape.dart';
import 'package:prism_ui/typography.dart';

import 'button.dart';
import 'card.dart';
import 'list_row.dart';
import 'navigation_dock.dart';
import 'scaffold.dart';
import 'sortable.dart';

part 'list_row_separator.dart';
part 'list_selected.dart';

/// A section's title, as tall as its action buttons with or without them.
class ListHeader extends StatelessWidget {
  static const _actionSize = TonalButtonSize.section;
  static const _actionsGap = 6.0;

  final String title;
  final List<IconButtonData> actions;
  final Widget? trailing;
  final EdgeInsets? padding;

  const ListHeader({
    super.key,
    required this.title,
    this.padding,
    this.actions = const [],
    this.trailing,
  });

  Widget _buildActions() {
    final grouped = actions.length > 1 ? actions.take(2) : null;
    return TonalButtonTheme(
      size: _actionSize,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: appBarActionSpace,
        children: [
          if (grouped != null)
            TonalButtonGroup(
              size: _actionSize,
              children: [
                for (final data in grouped) AppBarActionButton(data: data),
              ],
            ),
          for (final data in actions.skip(grouped?.length ?? 0))
            ElasticPress(
              enabled: !data.isLoading && data.onPressed != null,
              child: AppBarActionButton(data: data),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final padding = this.padding ?? listHeaderPaddingOf(context);
    final lineHeight = MeasureScope.of(
      context,
    ).textHeight(AppTextStyle.headline);
    final overhang = (_actionSize.button - lineHeight) / 2;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        padding.left,
        math.max(0, padding.top - overhang),
        padding.right,
        math.max(_actionsGap, padding.bottom - overhang),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: _actionSize.button),
        child: Row(
          spacing: 12,
          children: [
            Expanded(
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyle.headline
                    .of(context)
                    .copyWith(color: context.colorScheme.onSurfaceVariant),
              ),
            ),
            ?trailing,
            if (actions.isNotEmpty) _buildActions(),
          ],
        ),
      ),
    );
  }
}

class ListFooter extends StatelessWidget {
  final String text;

  const ListFooter({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.centerLeft,
      padding:
          const EdgeInsets.only(left: 16, right: 16, top: 8) * 1.mAp(context),
      child: Text(text, style: context.listCaptionStyle),
    );
  }
}

class ListSectionGap extends StatelessWidget {
  const ListSectionGap({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(height: listHeaderPaddingOf(context).top);
  }
}

/// A section's rows alone, for a group under a header its caller lays out.
Widget generateGroup(Iterable<Widget> items) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ...items.mapIndexed<Widget>(
        (index, item) => ItemPositionProvider(
          position: ItemPosition.get(index, items.length),
          child: item,
        ),
      ),
    ],
  );
}

Widget generateSection({
  String? title,
  required Iterable<Widget> items,
  List<IconButtonData> actions = const [],
  String? footer,
}) {
  return Column(
    children: [
      if (items.isNotEmpty)
        title != null
            ? ListHeader(title: title, actions: actions)
            : const ListSectionGap(),
      generateGroup(items),
      if (items.isNotEmpty && footer != null) ListFooter(text: footer),
    ],
  );
}

/// [generateSection] as slivers that build only the rows in view.
Widget generateSliverSection<T>({
  String? title,
  required List<T> items,
  required Widget Function(T item) itemBuilder,
  List<IconButtonData> actions = const [],
  String? footer,
}) {
  if (items.isEmpty) {
    return const SliverToBoxAdapter();
  }
  return SliverMainAxisGroup(
    slivers: [
      SliverToBoxAdapter(
        child: title != null
            ? ListHeader(title: title, actions: actions)
            : const ListSectionGap(),
      ),
      SliverPrismList(
        itemCount: items.length,
        itemBuilder: (_, index) => ItemPositionProvider(
          position: ItemPosition.get(index, items.length),
          child: itemBuilder(items[index]),
        ),
      ),
      if (footer != null) SliverToBoxAdapter(child: ListFooter(text: footer)),
    ],
  );
}
