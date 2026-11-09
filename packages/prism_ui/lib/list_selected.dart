part of 'list.dart';

bool _isEnd(ItemPosition? position) =>
    position == ItemPosition.end || position == ItemPosition.startAndEnd;

BorderRadius listItemRadiusOf(ItemPosition? position) {
  final isStart =
      position == ItemPosition.start || position == ItemPosition.startAndEnd;
  return AppRadius.vertical(
    top: isStart ? AppCorner.xl : AppCorner.none,
    bottom: _isEnd(position) ? AppCorner.xl : AppCorner.none,
  );
}

class DecorationListItem extends StatefulWidget {
  final Widget title;
  final Widget? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final bool? isSelected;
  final double? horizontalTitleGap;
  final EdgeInsetsGeometry? contentPadding;
  final VoidCallback? onPressed;
  final double? minVerticalPadding;
  final bool invalid;

  const DecorationListItem({
    super.key,
    this.contentPadding,
    required this.title,
    this.leading,
    this.trailing,
    this.subtitle,
    this.isSelected,
    this.onPressed,
    this.horizontalTitleGap,
    this.minVerticalPadding,
    this.invalid = false,
  });

  @override
  State<DecorationListItem> createState() => _DecorationListItemState();
}

class _DecorationListItemState extends State<DecorationListItem> {
  final _states = WidgetStatesController();

  @override
  void dispose() {
    _states.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final proxy = ProxyDecoratorProvider.of(context);
    final proxyDecorator = proxy?.isProxyDecorator ?? false;
    final sortable = SortableItem.maybeOf(context);
    final sorting = sortable?.sorting ?? false;
    final position = ItemPositionProvider.of(context)?.position;
    final isEnd = _isEnd(position);
    final row = _ListRowSeparator(
      separated: !proxyDecorator && !isEnd,
      emphasized: widget.invalid,
      states: _states,
      endIndent: 14,
      child: Card(
        shape: AppShape.of(listItemRadiusOf(position)),
        isError: widget.invalid,
        isSelected: widget.isSelected,
        padding: EdgeInsets.zero,
        statesController: _states,
        inert: sorting,
        onPressed: proxyDecorator ? null : widget.onPressed,
        child: LayoutBuilder(
          builder: (_, constraints) {
            final tile = ListRow(
              leading: widget.leading == null
                  ? null
                  : IgnorePointer(ignoring: sorting, child: widget.leading),
              padding:
                  widget.contentPadding ??
                  const EdgeInsets.only(right: 16, left: 16),
              title: _ListRowSeparatorStart(child: widget.title),
              subtitle: widget.subtitle,
              minVerticalPadding:
                  widget.minVerticalPadding ?? listRowVerticalPadding,
              horizontalTitleGap: widget.horizontalTitleGap,
              trailing: sortable == null
                  ? widget.trailing
                  : SortableTrailing(item: sortable, child: widget.trailing),
            );
            if (constraints.maxHeight >= double.infinity) {
              return tile;
            }
            return SizedBox(height: constraints.maxHeight, child: tile);
          },
        ),
      ),
    );
    if (!proxyDecorator) {
      return row;
    }
    // A change of the card's shape eases in over the button's own animation
    // duration, which would trail the lift; the clip follows it frame by frame.
    return ClipRSuperellipse(
      borderRadius: AppRadius.all(AppCorner.xl * proxy!.lift),
      child: row,
    );
  }
}

class SelectedDecorationListItem extends StatelessWidget {
  final bool isSelected;
  final bool isEditing;
  final Widget title;
  final Widget? subtitle;
  final VoidCallback onSelected;
  final VoidCallback onPressed;
  final double? horizontalTitleGap;
  final Widget? leading;
  final bool invalid;
  final double? minVerticalPadding;

  const SelectedDecorationListItem({
    super.key,
    required this.isSelected,
    required this.onSelected,
    this.horizontalTitleGap,
    this.isEditing = false,
    this.invalid = false,
    required this.title,
    required this.onPressed,
    this.minVerticalPadding,
    this.subtitle,
    this.leading,
  });

  @override
  Widget build(BuildContext context) {
    return DecorationListItem(
      title: title,
      minVerticalPadding: minVerticalPadding,
      contentPadding: const EdgeInsets.only(left: 16, right: 0),
      isSelected: isSelected,
      invalid: invalid,
      leading: leading,
      horizontalTitleGap: horizontalTitleGap,
      onPressed: () {
        if (isEditing) {
          onSelected();
          return;
        }
        onPressed();
      },
      subtitle: subtitle,
      trailing: Checkbox(
        value: isSelected,
        isCircle: true,
        onChanged: (_) {
          onSelected();
        },
      ),
    );
  }
}
