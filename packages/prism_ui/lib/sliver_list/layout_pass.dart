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

import 'package:collection/collection.dart';
import 'package:flutter/rendering.dart';

import 'render_object.dart';

class SliverLayoutState {
  bool didAddInitialChild = false;
  bool didRemoveChildren = false;
  bool didSetPreviousConstraint = false;
}

class LayoutPass {
  LayoutPass({
    required this.slivers,
    required this.initialScrollPosition,
    required this.childScrollOffsetEstimation,
    required this.sliverWithOffsetEstimation,
  });

  final List<RenderSuperSliverList> slivers;
  final double initialScrollPosition;
  final bool childScrollOffsetEstimation;
  final RenderSuperSliverList? sliverWithOffsetEstimation;

  final sliversDuringLayout = <RenderSuperSliverList>[];

  bool sliverIsBeforeSliverWithOffsetEstimation(RenderSuperSliverList s) {
    assert(sliversDuringLayout.contains(s));
    if (sliverWithOffsetEstimation == null) {
      return false;
    }
    final index = sliversDuringLayout.indexOf(sliverWithOffsetEstimation!);
    return index ==
            -1 // not reached yet
            ||
        index > sliversDuringLayout.indexOf(s);
  }

  SliverLayoutState getLayoutState(RenderSuperSliverList sliver) {
    return _sliverLayoutState.putIfAbsent(sliver, () => SliverLayoutState());
  }

  final _sliverLayoutState = <RenderSuperSliverList, SliverLayoutState>{};
}

final _viewportToLayoutPass = Expando<LayoutPass>();

extension RenderSliverLayoutPass on RenderSliver {
  RenderViewportBase? getViewport() {
    RenderObject? parent = this.parent;
    while (parent != null) {
      if (parent is RenderViewportBase) {
        return parent;
      }
      parent = parent.parent;
    }
    return null;
  }

  static void _gatherSliverList(
    List<RenderSuperSliverList> slivers,
    RenderObject sliver,
  ) {
    if (sliver is RenderSuperSliverList) {
      slivers.add(sliver);
    } else {
      sliver.visitChildren((child) {
        if (child is RenderSliver) {
          _gatherSliverList(slivers, child);
        }
      });
    }
  }

  List<RenderSuperSliverList> getSuperSliverLists() {
    final slivers = <RenderSuperSliverList>[];
    final viewport = getViewport();
    if (viewport != null) {
      _gatherSliverList(slivers, viewport);
    }
    return slivers;
  }

  LayoutPass? getLayoutPass(RenderSuperSliverList self) {
    final viewport = getViewport();
    if (viewport == null) {
      return null;
    }
    var pass = _viewportToLayoutPass[viewport];
    if (pass == null) {
      final slivers = getSuperSliverLists();
      var sliverWithOffsetEstimation = slivers.firstWhereOrNull(
        (element) => element.hasChildScrollOffsetEstimation,
      );
      if (sliverWithOffsetEstimation != null) {
        sliverWithOffsetEstimation.sanitizeChildScrollOffsetEstimation(
          viewport,
        );
        if (!sliverWithOffsetEstimation.hasChildScrollOffsetEstimation) {
          sliverWithOffsetEstimation = null;
        }
      }
      pass = LayoutPass(
        slivers: slivers,
        initialScrollPosition: viewport.offset.pixels,
        childScrollOffsetEstimation: sliverWithOffsetEstimation != null,
        sliverWithOffsetEstimation: sliverWithOffsetEstimation,
      );
      _viewportToLayoutPass[viewport] = pass;
      Future.microtask(() {
        _viewportToLayoutPass[viewport] = null;
      });
    }
    if (!pass.sliversDuringLayout.contains(self)) {
      pass.sliversDuringLayout.add(self);
    }
    return pass;
  }
}
