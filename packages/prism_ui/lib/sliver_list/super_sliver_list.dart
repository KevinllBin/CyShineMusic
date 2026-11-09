/*
Copyright (c) 2024 Matej Knopp, Superlist and the contributors

MIT LICENSE

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
of the Software, and to permit persons to whom the Software is furnished to do
so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS
OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR
IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
*/

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'element.dart';
import 'extent_manager.dart';
import 'render_object.dart';

class ListController {
  bool get isAttached => _delegate != null;

  void jumpToItem({
    required int index,
    required ScrollController scrollController,
    required double alignment,
  }) {
    assert(_delegate != null, 'ListController is not attached.');
    final offset = _delegate!.getOffsetToReveal(index, alignment);
    if (offset.isFinite) {
      final minExtent = scrollController.position.minScrollExtent;
      final maxExtent = scrollController.position.maxScrollExtent;
      final pixels = scrollController.position.pixels;
      // Jumping at the edge it already rests on leaves scrollbar handle
      // artifacts.
      if ((offset <= minExtent && pixels == minExtent) ||
          (offset >= maxExtent && pixels == maxExtent)) {
        return;
      }
      scrollController.jumpTo(offset);
    }
  }

  void dispose() {
    _delegate = null;
  }

  ExtentManager? _delegate;

  void setDelegate(ExtentManager delegate) {
    _delegate = delegate;
  }

  void unsetDelegate(ExtentManager delegate) {
    if (_delegate == delegate) {
      _delegate = null;
    }
  }
}

typedef ExtentEstimationProvider =
    double Function(int? index, double crossAxisExtent);

class SuperSliverList extends SliverMultiBoxAdaptorWidget {
  const SuperSliverList({
    super.key,
    required super.delegate,
    this.listController,
    required this.extentEstimation,
  });

  final ListController? listController;

  /// A nonzero extent for a null index is taken as every row's.
  final ExtentEstimationProvider extentEstimation;

  @override
  SliverMultiBoxAdaptorElement createElement() =>
      SuperSliverMultiBoxAdaptorElement(this, replaceMovedChildren: true);

  @override
  RenderSliverMultiBoxAdaptor createRenderObject(BuildContext context) {
    final element = context as SuperSliverMultiBoxAdaptorElement;
    return RenderSuperSliverList(
      childManager: element,
      estimateExtent: extentEstimation,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderObject renderObject,
  ) {
    super.updateRenderObject(context, renderObject);
    (renderObject as RenderSuperSliverList).estimateExtent = extentEstimation;
  }
}
