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

import 'package:flutter/foundation.dart';

import 'fenwick_tree.dart';

class ResizableFloat64List {
  static const _minCapacity = 16;

  @pragma('vm:prefer-inline')
  double operator [](int index) {
    assert(index >= 0 && index < _length);
    return _list[index];
  }

  @pragma('vm:prefer-inline')
  void operator []=(int index, double value) {
    assert(index >= 0 && index < _length);
    _list[index] = value;
  }

  void resize(int newSize, double Function(int index) defaultElement) {
    assert(newSize >= 0);
    if (newSize == _length) {
      return;
    }
    _ensureCapacity(newSize);
    for (var i = _length; i < newSize; ++i) {
      _list[i] = defaultElement(i);
    }
    _length = newSize;
    _maybeTrim();
  }

  void resizeWithDefault(int newSize, double defaultValue) {
    assert(newSize >= 0);
    if (newSize == _length) {
      return;
    }
    _ensureCapacity(newSize);
    final list = _list;
    for (var i = _length; i < newSize; ++i) {
      list[i] = defaultValue;
    }
    _length = newSize;
    _maybeTrim();
  }

  void _maybeTrim() {
    var newCapacity = _capacity;
    while (newCapacity > _minCapacity && newCapacity ~/ 2 >= _length) {
      newCapacity ~/= 2;
    }
    _reallocate(newCapacity);
  }

  void _ensureCapacity(int newCapacity) {
    var capacity = _capacity;
    while (capacity < newCapacity) {
      capacity *= 2;
    }
    _reallocate(capacity);
  }

  void _reallocate(int newCapacity) {
    assert(_length <= newCapacity);
    if (_capacity == newCapacity) {
      return;
    }

    final previous = _list;
    _list = Float64List(newCapacity);
    _list.setRange(0, _length, previous);
  }

  bool get isEmpty => _length == 0;

  int get length => _length;

  int get _capacity => _list.length;
  int _length = 0;

  var _list = Float64List(_minCapacity);
}

class ExtentList {
  final _extents = ResizableFloat64List();

  double get _totalExtent => __totalExtent;
  set _totalExtent(double value) {
    __totalExtent = value;
    if (__totalExtent.abs() < precisionErrorTolerance) {
      __totalExtent = 0.0;
    }
  }

  double __totalExtent = 0.0;

  FenwickTree? _fenwickTree;

  void setExtent(int index, double extent) {
    final delta = extent - _extents[index];
    _extents[index] = extent;
    _totalExtent += delta;
    _fenwickTree?.update(index, delta);
  }

  int get length => _extents.length;

  @pragma('vm:prefer-inline')
  double operator [](int index) {
    assert(index >= 0 && index < _extents.length);
    return _extents[index];
  }

  double get totalExtent => _totalExtent;

  void resize(int newSize, double Function(int? index) defaultExtent) {
    final prevSize = _extents.length;
    final prevExtents = _extents;

    if (newSize < prevSize) {
      if (prevSize - newSize < newSize) {
        for (var i = newSize; i < prevSize; ++i) {
          _totalExtent -= prevExtents[i];
        }
      } else {
        _totalExtent = 0;
        for (var i = 0; i < newSize; ++i) {
          _totalExtent += _extents[i];
        }
      }
    }

    double addedDefaultExtent = 0.0;
    final sameExtent = defaultExtent(null);
    if (sameExtent > 0) {
      _extents.resizeWithDefault(newSize, sameExtent);
      if (newSize > prevSize) {
        addedDefaultExtent = (newSize - prevSize) * sameExtent;
      }
    } else {
      _extents.resize(newSize, (index) {
        final extent = defaultExtent(index);
        addedDefaultExtent += extent;
        return extent;
      });
    }

    if (newSize > prevSize) {
      _totalExtent += addedDefaultExtent;
    }

    _fenwickTree = null;
  }

  FenwickTree _getOrBuildFenwickTree() {
    _fenwickTree ??= FenwickTree.fromList(list: _extents._list);
    return _fenwickTree!;
  }

  double offsetForIndex(int index) {
    final tree = _getOrBuildFenwickTree();
    return tree.query(index);
  }

  int? indexForOffset(double offset) {
    if (offset >= _totalExtent) {
      return null;
    }
    final tree = _getOrBuildFenwickTree();
    return tree.inverseQuery(offset);
  }
}
