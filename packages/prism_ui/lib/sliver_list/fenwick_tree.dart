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

import 'dart:typed_data';

class FenwickTree {
  FenwickTree({required this.size}) : _tree = Float64List(size + 1);

  FenwickTree.fromList({required Float64List list})
    : size = list.length,
      _tree = Float64List(list.length + 1) {
    for (int i = 1; i <= size; ++i) {
      _tree[i] += list[i - 1];
      if (i + (i & -i) <= size) {
        _tree[i + (i & -i)] += _tree[i];
      }
    }
  }

  final int size;
  final Float64List _tree;

  void update(int index, double delta) {
    ++index;
    while (index <= size) {
      _tree[index] += delta;
      index += index & -index;
    }
  }

  double query(int index) {
    double result = 0.0;
    while (index > 0) {
      result += _tree[index];
      index -= index & -index;
    }
    return result;
  }

  int inverseQuery(double prefixSum) {
    var index = 0;
    var bitmask = 1 << size.bitLength - 1;
    while (bitmask != 0 && index < size) {
      final nextIndex = index + bitmask;
      if (nextIndex <= size && _tree[nextIndex] <= prefixSum) {
        index = nextIndex;
        prefixSum -= _tree[index];
      }
      bitmask >>= 1;
    }
    return index;
  }
}
