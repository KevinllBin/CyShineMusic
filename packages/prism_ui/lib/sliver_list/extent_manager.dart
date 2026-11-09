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

import 'dart:ui';

import 'extent_list.dart';

abstract class ExtentManagerDelegate {
  double estimateExtentForItem(int? index);
  double getOffsetToReveal(
    int index,
    double alignment, {
    required bool estimationOnly,
    Rect? rect,
  });
}

class ExtentManager {
  ExtentManager({required this.delegate});

  final ExtentManagerDelegate delegate;

  final _extentList = ExtentList();

  void setExtent(int index, double extent) {
    _extentList.setExtent(index, extent);
  }

  double get totalExtent => _extentList.totalExtent;

  @pragma('vm:prefer-inline')
  double getExtent(int index) => _extentList[index];

  void resize(int newSize) {
    if (newSize != _extentList.length) {
      _extentList.resize(newSize, delegate.estimateExtentForItem);
    }
  }

  int? indexForOffset(double offset) => _extentList.indexForOffset(offset);

  double offsetForIndex(int index) {
    assert(index >= 0 && index < _extentList.length);
    return _extentList.offsetForIndex(index);
  }

  double getOffsetToReveal(int index, double alignment, {Rect? rect}) =>
      delegate.getOffsetToReveal(
        index,
        alignment,
        rect: rect,
        estimationOnly: false,
      );
}
