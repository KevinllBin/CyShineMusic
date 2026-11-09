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
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'element.dart';
import 'extent_manager.dart';
import 'layout_pass.dart';
import 'sliver_extensions.dart';
import 'super_sliver_list.dart';

class _ChildScrollOffsetEstimation {
  _ChildScrollOffsetEstimation({
    required this.index,
    required this.offset,
    required this.extent,
    required this.precedingScrollExtent,
    required this.revealingRect,
    required this.alignment,
    required this.childObstructionExtent,
  });

  final int index;

  final double offset;

  final double extent;

  final double precedingScrollExtent;

  final bool revealingRect;

  final double alignment;

  final ChildObstructionExtent childObstructionExtent;

  double? viewportScrollOffset;
}

class RenderSuperSliverList extends RenderSliverMultiBoxAdaptor {
  RenderSuperSliverList({
    required super.childManager,
    required this.estimateExtent,
  });

  @override
  SuperSliverMultiBoxAdaptorElement get childManager =>
      super.childManager as SuperSliverMultiBoxAdaptorElement;

  ExtentEstimationProvider estimateExtent;

  ExtentManager get _extentManager => childManager.extentManager;
  SliverConstraints? previousConstraints;

  _ChildScrollOffsetEstimation? _childScrollOffsetEstimation;

  void sanitizeChildScrollOffsetEstimation(RenderViewportBase viewport) {
    if (_childScrollOffsetEstimation != null) {
      final offset = viewport.offset.pixels;
      if (_childScrollOffsetEstimation!.viewportScrollOffset != null &&
          (_childScrollOffsetEstimation!.viewportScrollOffset! - offset).abs() >
              1.0) {
        _childScrollOffsetEstimation = null;
      }
    }
  }

  @override
  double? childScrollOffset(covariant RenderObject child) {
    for (var c = firstChild; c != null; c = childAfter(c)) {
      if (child == c) {
        return super.childScrollOffset(child);
      }
    }

    final offsetToRevealContext = OffsetToRevealContext.current();
    if (offsetToRevealContext == null) {
      return super.childScrollOffset(child);
    }

    final index = indexOf(child as RenderBox);

    assert(offsetToRevealContext.viewport == getViewport());

    if (offsetToRevealContext.estimationOnly == true) {
      return _extentManager.offsetForIndex(index);
    }

    double getActualPrecedingScrollExtent() {
      final viewport = getViewport()!;
      bool isParent(RenderObject object) {
        var parent = this.parent;
        while (parent != null && parent != viewport) {
          if (parent == object) {
            return true;
          }
          parent = parent.parent;
        }
        return false;
      }

      double offset = 0;
      bool finished = false;
      viewport.visitChildren((child) {
        if (finished) {
          return;
        }
        if (child is! RenderSliver) {
          assert(false, 'Unexpected non-sliver child of viewport');
          return;
        }
        if (isParent(child)) {
          final difference =
              constraints.precedingScrollExtent -
              child.constraints.precedingScrollExtent;
          offset += difference;
          finished = true;
          return;
        }
        if (child == this) {
          finished = true;
          return;
        }
        offset += child.geometry!.scrollExtent;
      });
      assert(finished, "Viewport doesn't seem to contain current sliver?");
      return offset;
    }

    final precedingScrollExtent = getActualPrecedingScrollExtent();
    if (constraints.precedingScrollExtent != precedingScrollExtent) {}

    _childScrollOffsetEstimation = _ChildScrollOffsetEstimation(
      index: index,
      offset: _extentManager.offsetForIndex(index),
      extent: _extentManager.getExtent(index),
      precedingScrollExtent: precedingScrollExtent,
      revealingRect: offsetToRevealContext.rect != null,
      alignment: offsetToRevealContext.alignment,
      childObstructionExtent: child.getParentChildObstructionExtent(),
    );

    assert(offsetToRevealContext.estimationOnly == false);
    offsetToRevealContext.registerOffsetResolvedCallback((value) {
      final offset = value.offset;
      final position = getViewport()!.offset as ScrollPosition;
      if (offset >= position.minScrollExtent &&
          offset <= position.maxScrollExtent) {
        _childScrollOffsetEstimation?.viewportScrollOffset = offset;
      }
    });

    final slivers = getSuperSliverLists();
    for (final sliver in slivers) {
      sliver.markNeedsLayout();
      if (sliver != this) {
        sliver._childScrollOffsetEstimation = null;
      } else if (sliver == this) {
        break;
      }
    }
    return _childScrollOffsetEstimation!.offset;
  }

  void _shiftLayoutOffsets(RenderBox? child, double delta) {
    while (child != null) {
      final data = child.parentData! as SliverMultiBoxAdaptorParentData;
      if (data.layoutOffset != null) {
        data.layoutOffset = data.layoutOffset! + delta;
      }
      child = childAfter(child);
    }
  }

  double? layoutChild(
    RenderBox child,
    BoxConstraints childConstraints, {
    RenderBox? lastChildWithScrollOffset,
  }) {
    if (childScrollOffset(child) == null && lastChildWithScrollOffset == null) {
      return null;
    }
    if (childScrollOffset(child) == null) {
      final data = child.parentData! as SliverMultiBoxAdaptorParentData;
      data.layoutOffset =
          childScrollOffset(lastChildWithScrollOffset!)! +
          paintExtentOf(lastChildWithScrollOffset);
    }
    child.layout(childConstraints, parentUsesSize: true);
    final index = indexOf(child);
    _extentManager.setExtent(index, paintExtentOf(child));
    final nextChild = childAfter(child);
    if (nextChild != null) {
      final nextChildData =
          nextChild.parentData! as SliverMultiBoxAdaptorParentData;
      nextChildData.layoutOffset = null;
    }
    return childScrollOffset(child);
  }

  void _markNeedsLayoutDelayed(LayoutPass pass) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final thisIndex = pass.sliversDuringLayout.indexOf(this);
      for (final s in pass.slivers) {
        final theirIndex = pass.sliversDuringLayout.indexOf(s);
        if (theirIndex == -1 || theirIndex >= thisIndex) {
          s.markNeedsLayout();
        }
      }
    });
  }

  double estimateExtentForItem(int? index) {
    return estimateExtent(index, constraints.crossAxisExtent);
  }

  @override
  void performLayout() {
    _performLayoutInner();
  }

  @override
  void layout(Constraints constraints, {bool parentUsesSize = false}) {
    super.layout(constraints, parentUsesSize: parentUsesSize);
    if (geometry?.scrollOffsetCorrection != null &&
        geometry?.scrollOffsetCorrection != 0) {
      parent?.invokeLayoutCallback((constraints) {
        markNeedsLayout();
      });
    }
  }

  bool get hasChildScrollOffsetEstimation =>
      _childScrollOffsetEstimation != null;

  void _performLayoutInner() {
    final layoutPass = getLayoutPass(this)!;
    final layoutState = layoutPass.getLayoutState(this);

    final SliverConstraints constraints = this.constraints;
    final BoxConstraints childConstraints = constraints.asBoxConstraints();
    final totalChildCount = childManager.childCount;

    _extentManager.resize(totalChildCount);

    final bool crossAxisResizing;

    if (previousConstraints != null &&
        previousConstraints!.crossAxisExtent != constraints.crossAxisExtent) {
      crossAxisResizing = true;
    } else {
      crossAxisResizing = false;
    }

    if (!layoutState.didSetPreviousConstraint) {
      layoutState.didSetPreviousConstraint = true;
      previousConstraints = constraints;
    }

    childManager.didStartLayout();
    childManager.setDidUnderflow(false);

    final initialExtent = _totalExtent();

    final viewportIsScrolled =
        (constraints.viewportMainAxisExtent -
                constraints.remainingPaintExtent) <
            constraints.precedingScrollExtent ||
        constraints.scrollOffset > 0;

    final anchoredAtEnd =
        viewportIsScrolled &&
        (constraints.scrollOffset + constraints.remainingPaintExtent) +
                precisionErrorTolerance >=
            initialExtent &&
        (layoutPass.childScrollOffsetEstimation == false ||
            layoutPass.sliverIsBeforeSliverWithOffsetEstimation(this));

    var startOffset = constraints.scrollOffset + constraints.cacheOrigin;
    var remainingExtent = constraints.remainingCacheExtent;

    int leadingGarbage = 0;
    int trailingGarbage = 0;
    RenderBox? lastChildWithScrollOffset;

    final firstVisible = _firstWholeVisibleChild();
    final double? firstVisibleLayoutOffset = firstVisible != null
        ? childScrollOffset(firstVisible)
        : null;

    RenderBox? previousChild;
    int index = firstChild != null ? indexOf(firstChild!) : 0;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      if (trailingGarbage > 0) {
        ++trailingGarbage;
      } else {
        if (indexOf(child) != index) {
          final newChild = insertAndLayoutChild(
            childConstraints,
            after: previousChild,
          );
          assert(newChild != null, 'Unexpected trailing child.');
          if (newChild == null) {
            ++trailingGarbage;
            continue;
          } else {
            child = newChild;
          }
        }
        final offset = layoutChild(
          child,
          childConstraints,
          lastChildWithScrollOffset: lastChildWithScrollOffset,
        );

        if (offset == null) {
          ++leadingGarbage;
        } else {
          lastChildWithScrollOffset = child;
          final endOffset = offset + paintExtentOf(child);
          if (offset > startOffset + remainingExtent) {
            ++trailingGarbage;
          } else if (endOffset < startOffset) {
            ++leadingGarbage;
          }
        }
      }
      previousChild = child;
      ++index;
    }

    if (leadingGarbage > 0 || trailingGarbage > 0) {
      layoutState.didRemoveChildren |= true;
    }
    collectGarbage(leadingGarbage, trailingGarbage);

    var didDelayPopulatingCacheArea = false;

    if (firstChild == null) {
      layoutState.didAddInitialChild |= true;
      final int firstChildInCacheAreaIndex =
          indexForOffset(startOffset) ?? totalChildCount;
      if (_childScrollOffsetEstimation == null &&
          (firstChildInCacheAreaIndex >= totalChildCount ||
              constraints.remainingCacheExtent == 0)) {
        if (totalChildCount == 0) {
          childManager.setDidUnderflow(true);
        }
        geometry = SliverGeometry(
          paintExtent: 0,
          maxPaintExtent: _totalExtent(),
          scrollExtent: _totalExtent(),
        );
        childManager.didFinishLayout();
        return;
      }

      final firstChildScrollOffset = constraints.scrollOffset;
      final firstChildIndex = anchoredAtEnd
          ? totalChildCount - 1
          : indexForOffset(firstChildScrollOffset) ?? totalChildCount - 1;

      if (!addInitialChild(
        index: firstChildIndex,
        layoutOffset: offsetForIndex(firstChildIndex),
      )) {
        return _zeroGeometry();
      }

      final reducedStartOffset = constraints.scrollOffset;
      final reducedRemainingExtent = constraints.remainingPaintExtent;

      if (layoutState.didRemoveChildren &&
          (startOffset != reducedStartOffset ||
              remainingExtent != reducedRemainingExtent)) {
        startOffset = reducedStartOffset;
        remainingExtent = reducedRemainingExtent;
        didDelayPopulatingCacheArea = true;
        _markNeedsLayoutDelayed(layoutPass);
      }
    }

    firstChild!.layout(childConstraints, parentUsesSize: true);
    _extentManager.setExtent(indexOf(firstChild!), paintExtentOf(firstChild!));

    double scrollCorrection = 0;

    if (crossAxisResizing &&
        !anchoredAtEnd &&
        firstVisible != null &&
        firstVisible.parent == this) {
      scrollCorrection =
          childScrollOffset(firstVisible)! - firstVisibleLayoutOffset!;
    }

    var correctedStartOffset = startOffset + scrollCorrection;

    while ((indexOf(firstChild!) > 0 &&
            childScrollOffset(firstChild!)! > correctedStartOffset) ||
        (_childScrollOffsetEstimation != null &&
            indexOf(firstChild!) > _childScrollOffsetEstimation!.index)) {
      final prevOffset = childScrollOffset(firstChild!)!;
      final previousExtent = _extentManager.getExtent(indexOf(firstChild!) - 1);
      final box = insertAndLayoutLeadingChild(
        childConstraints,
        parentUsesSize: true,
      );
      if (box == null) {
        break;
      }
      final data = box.parentData! as SliverMultiBoxAdaptorParentData;
      data.layoutOffset = prevOffset - previousExtent;
      final correction = paintExtentOf(box) - previousExtent;
      _shiftLayoutOffsets(childAfter(box), correction);
      if ((!anchoredAtEnd || !layoutState.didAddInitialChild) &&
          constraints.remainingPaintExtent ==
              constraints.viewportMainAxisExtent) {
        scrollCorrection += correction;
      }

      if (startOffset > 0) {
        correctedStartOffset += correction;
      }
    }

    if (indexOf(firstChild!) == 0 && childScrollOffset(firstChild!)! != 0) {
      final correction = -childScrollOffset(firstChild!)!;
      _shiftLayoutOffsets(firstChild, correction);
      scrollCorrection += correction;
    }

    bool addTrailingChild() {
      final lastChildIndex = indexOf(lastChild!);
      if (lastChildIndex >= totalChildCount - 1) {
        return false;
      }

      if (childScrollOffset(lastChild!)! + paintExtentOf(lastChild!) >=
          startOffset + remainingExtent) {
        if (_childScrollOffsetEstimation != null &&
            _childScrollOffsetEstimation!.index < lastChildIndex) {
          return false;
        }
        if (layoutPass.childScrollOffsetEstimation == false) {
          return false;
        }
        if (_childScrollOffsetEstimation == null &&
            !layoutPass.sliverIsBeforeSliverWithOffsetEstimation(this)) {
          return false;
        }
      }

      final newLayoutOffset =
          childScrollOffset(lastChild!)! + paintExtentOf(lastChild!);

      final box = insertAndLayoutChild(
        childConstraints,
        after: lastChild,
        parentUsesSize: true,
      );
      if (box == null) {
        return false;
      }
      _extentManager.setExtent(indexOf(box), paintExtentOf(box));
      final data = box.parentData! as SliverMultiBoxAdaptorParentData;
      data.layoutOffset = newLayoutOffset;
      return true;
    }

    while (addTrailingChild()) {}

    final estimation = _childScrollOffsetEstimation;
    if (estimation != null) {
      for (var c = firstChild; c != null; c = childAfter(c)) {
        if (estimation.index == indexOf(c)) {
          _childScrollOffsetEstimation = null;
          final childScrollOffset = this.childScrollOffset(c)!;

          var correction = childScrollOffset - estimation.offset;
          correction +=
              constraints.precedingScrollExtent -
              estimation.precedingScrollExtent;

          final currentScrollPosition = getViewport()?.offset.pixels ?? 0.0;
          correction +=
              layoutPass.initialScrollPosition - currentScrollPosition;

          if (!estimation.revealingRect) {
            final childAlignmentWithinViewport = estimation.alignment;

            final extentDifference = paintExtentOf(c) - estimation.extent;
            correction += extentDifference * childAlignmentWithinViewport;

            final obstructionExtentDifference =
                c.getParentChildObstructionExtent() -
                estimation.childObstructionExtent;
            correction -=
                obstructionExtentDifference.leading *
                (1.0 - childAlignmentWithinViewport);
            correction +=
                obstructionExtentDifference.trailing *
                childAlignmentWithinViewport;
          }

          final position = getViewport()!.offset as ScrollPosition;

          final maxScrollExtent =
              position.maxScrollExtent -
              initialExtent +
              _totalExtent() +
              constraints.precedingScrollExtent -
              estimation.precedingScrollExtent;

          final target = position.pixels + correction;
          if (target < 0) {
            correction -= target;
          } else if (target > maxScrollExtent) {
            correction -= target - maxScrollExtent;
          }

          if (correction.abs() > precisionErrorTolerance) {
            geometry = SliverGeometry(scrollOffsetCorrection: correction);
            childManager.didFinishLayout();
            return;
          } else {
            scrollCorrection = 0;
          }
        }
      }
    }

    if (anchoredAtEnd &&
        (crossAxisResizing || layoutState.didAddInitialChild) &&
        _totalExtent() != initialExtent) {
      scrollCorrection += _totalExtent() - initialExtent;
    }

    if (scrollCorrection.abs() > precisionErrorTolerance) {
      geometry = SliverGeometry(scrollOffsetCorrection: scrollCorrection);
      childManager.didFinishLayout();
      return;
    }

    final endScrollOffset = _totalExtent();
    final cacheStart = constraints.scrollOffset + constraints.cacheOrigin;
    final lastChildEnd =
        childScrollOffset(lastChild!)! + paintExtentOf(lastChild!);
    var cacheConsumed = (lastChildEnd - cacheStart).clamp(
      0.0,
      constraints.remainingCacheExtent,
    );
    var paintExtent = calculatePaintOffset(
      constraints,
      from: childScrollOffset(firstChild!)!,
      to: endScrollOffset,
    );

    if ((constraints.remainingPaintExtent - paintExtent).abs() <
        precisionErrorTolerance) {
      paintExtent = constraints.remainingPaintExtent;
    }

    if (paintExtent == constraints.remainingPaintExtent &&
        didDelayPopulatingCacheArea) {
      cacheConsumed = constraints.remainingCacheExtent;
    }

    geometry = SliverGeometry(
      scrollExtent: endScrollOffset,
      paintExtent: paintExtent,
      maxPaintExtent: endScrollOffset,
      cacheExtent: cacheConsumed,
      hasVisualOverflow:
          endScrollOffset > constraints.remainingPaintExtent ||
          constraints.scrollOffset > 0.0,
    );
    if (paintExtent < constraints.remainingPaintExtent) {
      childManager.setDidUnderflow(true);
    }

    childManager.didFinishLayout();
  }

  RenderBox? _firstWholeVisibleChild() {
    RenderBox? child = firstChild;
    while (child != null) {
      final data = child.parentData! as SliverMultiBoxAdaptorParentData;
      if ((data.layoutOffset ?? double.negativeInfinity) >=
          constraints.scrollOffset) {
        return child;
      }
      child = childAfter(child);
    }
    return null;
  }

  void _zeroGeometry() {
    geometry = SliverGeometry.zero;
    childManager.didFinishLayout();
  }

  int? indexForOffset(double offset) {
    return _extentManager.indexForOffset(offset);
  }

  double offsetForIndex(int index) {
    return _extentManager.offsetForIndex(index);
  }

  double _totalExtent() {
    return _extentManager.totalExtent;
  }

  @override
  @protected
  RenderBox? insertAndLayoutLeadingChild(
    BoxConstraints childConstraints, {
    bool parentUsesSize = false,
  }) {
    final res = super.insertAndLayoutLeadingChild(
      childConstraints,
      parentUsesSize: parentUsesSize,
    );
    if (res != null) {
      _extentManager.setExtent(indexOf(res), paintExtentOf(res));
    }
    return res;
  }

  double getOffsetToReveal(
    int index,
    double alignment, {
    required bool estimationOnly,
    Rect? rect,
  }) {
    final renderObject = _FakeRenderObject(
      parent: this,
      index: index,
      extent: _extentManager.getExtent(index),
    );
    final viewport = getViewport()!;
    return viewport
        .getOffsetToRevealExt(
          renderObject,
          alignment,
          esimationOnly: estimationOnly,
          rect: rect,
        )
        .offset;
  }
}

class _FakeRenderObject extends RenderBox {
  @override
  final RenderObject parent;
  final double extent;

  _FakeRenderObject({
    required this.parent,
    required int index,
    required this.extent,
  }) {
    parentData = SliverMultiBoxAdaptorParentData()..index = index;
  }

  @override
  Size get size => Size(extent, extent);

  @override
  Matrix4 getTransformTo(RenderObject? ancestor) {
    return Matrix4.identity();
  }
}
