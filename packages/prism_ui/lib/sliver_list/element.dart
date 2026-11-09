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

import 'package:flutter/widgets.dart';

import 'extent_manager.dart';
import 'render_object.dart';
import 'super_sliver_list.dart';

class SuperSliverMultiBoxAdaptorElement extends SliverMultiBoxAdaptorElement
    implements ExtentManagerDelegate {
  SuperSliverMultiBoxAdaptorElement(
    SuperSliverList widget, {
    required super.replaceMovedChildren,
  }) : super(widget) {
    _extentManager = ExtentManager(delegate: this);
    _currentController = widget.listController;
    _currentController?.setDelegate(_extentManager);
  }

  @override
  RenderSuperSliverList get renderObject =>
      super.renderObject as RenderSuperSliverList;

  @override
  double estimateExtentForItem(int? index) {
    return renderObject.estimateExtentForItem(index);
  }

  @override
  double getOffsetToReveal(
    int index,
    double alignment, {
    required bool estimationOnly,
    Rect? rect,
  }) {
    return renderObject.getOffsetToReveal(
      index,
      alignment,
      estimationOnly: estimationOnly,
      rect: rect,
    );
  }

  ListController? _currentController;

  @override
  void update(covariant SuperSliverList newWidget) {
    final childCountBefore = childCount;
    super.update(newWidget);
    if (childCountBefore != childCount) {
      renderObject.markNeedsLayout();
    }
    if (_currentController != newWidget.listController) {
      _currentController?.unsetDelegate(_extentManager);
      _currentController = newWidget.listController;
      _currentController?.setDelegate(_extentManager);
    }
  }

  @override
  void deactivate() {
    super.deactivate();
    _currentController?.unsetDelegate(_extentManager);
    _currentController = null;
  }

  late final ExtentManager _extentManager;

  ExtentManager get extentManager => _extentManager;
}
