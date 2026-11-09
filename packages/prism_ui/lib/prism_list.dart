import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:prism_ui/sliver_list/super_sliver_list.dart';

export 'package:prism_ui/sliver_list/super_sliver_list.dart'
    show ListController;

/// The app's lazily built list. A far jump, such as dragging the scrollbar,
/// places rows it has not laid out yet at [estimatedItemExtent] instead of
/// laying out every row it passes, as [SliverList] does.
class SliverPrismList extends StatelessWidget {
  static const defaultEstimatedItemExtent = 64.0;

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double gap;
  final double? itemExtent;
  final double estimatedItemExtent;
  final ChildIndexGetter? findChildIndexCallback;
  final ListController? listController;
  final bool addRepaintBoundaries;

  const SliverPrismList({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.gap = 0,
    this.itemExtent,
    this.estimatedItemExtent = SliverPrismList.defaultEstimatedItemExtent,
    this.findChildIndexCallback,
    this.listController,
    this.addRepaintBoundaries = true,
  }) : assert(listController == null || (gap == 0 && itemExtent == null));

  // SuperSliverList takes a nonzero estimate for no index as every row's.
  double _estimate(int? index, double crossAxisExtent) {
    final extent = itemExtent ?? estimatedItemExtent;
    if (gap == 0) {
      return extent;
    }
    return switch (index) {
      null => 0,
      _ when index.isEven => extent,
      _ => gap,
    };
  }

  SliverChildBuilderDelegate _delegate() {
    if (gap == 0) {
      return SliverChildBuilderDelegate(
        itemBuilder,
        childCount: itemCount,
        findChildIndexCallback: findChildIndexCallback,
        addRepaintBoundaries: addRepaintBoundaries,
      );
    }
    final findChildIndex = findChildIndexCallback;
    return SliverChildBuilderDelegate(
      (context, index) => index.isEven
          ? itemBuilder(context, index ~/ 2)
          : SizedBox.square(dimension: gap),
      childCount: math.max(0, itemCount * 2 - 1),
      findChildIndexCallback: findChildIndex == null
          ? null
          : (key) => switch (findChildIndex(key)) {
              final index? => index * 2,
              null => null,
            },
      addRepaintBoundaries: addRepaintBoundaries,
      semanticIndexCallback: (_, index) => index.isEven ? index ~/ 2 : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final itemExtent = this.itemExtent;
    if (itemExtent != null && gap == 0) {
      return SliverFixedExtentList(
        itemExtent: itemExtent,
        delegate: _delegate(),
      );
    }
    return SuperSliverList(
      delegate: _delegate(),
      listController: listController,
      extentEstimation: _estimate,
    );
  }
}

class PrismListView extends BoxScrollView {
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double gap;
  final double? itemExtent;
  final double estimatedItemExtent;
  final ChildIndexGetter? findChildIndexCallback;
  final ListController? listController;
  final bool addRepaintBoundaries;

  const PrismListView({
    super.key,
    super.scrollDirection,
    super.reverse,
    super.controller,
    super.primary,
    super.physics,
    super.shrinkWrap,
    super.padding,
    super.scrollCacheExtent,
    super.keyboardDismissBehavior,
    super.clipBehavior,
    required this.itemCount,
    required this.itemBuilder,
    this.gap = 0,
    this.itemExtent,
    this.estimatedItemExtent = SliverPrismList.defaultEstimatedItemExtent,
    this.findChildIndexCallback,
    this.listController,
    this.addRepaintBoundaries = true,
  }) : super(semanticChildCount: itemCount);

  @override
  Widget buildChildLayout(BuildContext context) {
    return SliverPrismList(
      itemCount: itemCount,
      itemBuilder: itemBuilder,
      gap: gap,
      itemExtent: itemExtent,
      estimatedItemExtent: estimatedItemExtent,
      findChildIndexCallback: findChildIndexCallback,
      listController: listController,
      addRepaintBoundaries: addRepaintBoundaries,
    );
  }
}

/// A [SliverReorderableList] that jumps as [SliverPrismList] does.
class SliverPrismReorderableList extends SliverReorderableList {
  final double estimatedItemExtent;

  const SliverPrismReorderableList({
    super.key,
    required super.itemBuilder,
    required super.itemCount,
    required super.onReorderItem,
    super.proxyDecorator,
    super.itemExtent,
    this.estimatedItemExtent = SliverPrismList.defaultEstimatedItemExtent,
  });

  @override
  SliverReorderableListState createState() =>
      _SliverPrismReorderableListState();
}

class _SliverPrismReorderableListState extends SliverReorderableListState {
  @override
  Widget build(BuildContext context) {
    final sliver = super.build(context);
    if (sliver is! SliverList) {
      return sliver;
    }
    final estimate = (widget as SliverPrismReorderableList).estimatedItemExtent;
    return SuperSliverList(
      delegate: sliver.delegate,
      extentEstimation: (_, _) => estimate,
    );
  }
}

/// Rows start their drag from their own [ReorderDragStartListener].
class PrismReorderableListView extends StatelessWidget {
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final ReorderCallback onReorderItem;
  final ReorderItemProxyDecorator proxyDecorator;
  final Widget? header;
  final Widget? footer;
  final double? itemExtent;
  final double estimatedItemExtent;
  final ScrollController? controller;
  final EdgeInsetsGeometry? padding;
  final ScrollCacheExtent? scrollCacheExtent;

  const PrismReorderableListView({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    required this.onReorderItem,
    required this.proxyDecorator,
    this.header,
    this.footer,
    this.itemExtent,
    this.estimatedItemExtent = SliverPrismList.defaultEstimatedItemExtent,
    this.controller,
    this.padding,
    this.scrollCacheExtent,
  });

  @override
  Widget build(BuildContext context) {
    final header = this.header;
    final footer = this.footer;
    return CustomScrollView(
      controller: controller,
      scrollCacheExtent: scrollCacheExtent,
      slivers: [
        SliverPadding(
          padding: padding ?? EdgeInsets.zero,
          sliver: SliverMainAxisGroup(
            slivers: [
              if (header != null) SliverToBoxAdapter(child: header),
              SliverPrismReorderableList(
                itemCount: itemCount,
                itemBuilder: itemBuilder,
                onReorderItem: onReorderItem,
                proxyDecorator: proxyDecorator,
                itemExtent: itemExtent,
                estimatedItemExtent: estimatedItemExtent,
              ),
              if (footer != null) SliverToBoxAdapter(child: footer),
            ],
          ),
        ),
      ],
    );
  }
}
