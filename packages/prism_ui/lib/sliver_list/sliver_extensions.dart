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

class ChildObstructionExtent {
  ChildObstructionExtent({required this.leading, required this.trailing});

  final double leading;

  final double trailing;

  ChildObstructionExtent operator +(ChildObstructionExtent other) {
    return ChildObstructionExtent(
      leading: leading + other.leading,
      trailing: trailing + other.trailing,
    );
  }

  ChildObstructionExtent operator -(ChildObstructionExtent other) {
    return ChildObstructionExtent(
      leading: leading - other.leading,
      trailing: trailing - other.trailing,
    );
  }
}

extension SliverGeometryChildObstruction on SliverGeometry {
  ChildObstructionExtent? get childObstructionExtent {
    if (this is _SliverGeometryWithChildObstructionExtent) {
      return (this as _SliverGeometryWithChildObstructionExtent)
          ._childObstructionExtent;
    } else {
      return null;
    }
  }
}

extension RenderObjectChildObstuctionExtent on RenderObject {
  ChildObstructionExtent getParentChildObstructionExtent() {
    var childObstructionExtent = ChildObstructionExtent(
      leading: 0,
      trailing: 0,
    );
    var parent = this.parent;
    while (parent != null && parent is! RenderViewport) {
      if (parent is RenderSliver) {
        final geometry = parent.geometry;
        if (geometry?.childObstructionExtent != null) {
          childObstructionExtent += geometry!.childObstructionExtent!;
        }
      }
      parent = parent.parent;
    }
    return childObstructionExtent;
  }
}

class OffsetToRevealContext {
  OffsetToRevealContext({
    required this.viewport,
    required this.target,
    required this.alignment,
    required this.estimationOnly,
    required this.rect,
    required this.axis,
  });

  final RenderAbstractViewport viewport;
  final RenderObject target;
  final double alignment;
  final bool estimationOnly;
  final Rect? rect;
  final Axis? axis;

  void registerOffsetResolvedCallback(ValueSetter<RevealedOffset> callback) {
    _offsetResolvedCallbacks.add(callback);
  }

  final _offsetResolvedCallbacks = <ValueSetter<RevealedOffset>>[];

  static final _contexts = <OffsetToRevealContext>[];

  static OffsetToRevealContext? current() {
    if (_contexts.isEmpty) return null;
    return _contexts.last;
  }
}

extension RenderViewportExt on RenderAbstractViewport {
  RevealedOffset getOffsetToRevealExt(
    RenderObject target,
    double alignment, {
    bool esimationOnly = false,
    Rect? rect,
    Axis? axis,
  }) {
    final context = OffsetToRevealContext(
      viewport: this,
      target: target,
      alignment: alignment,
      estimationOnly: esimationOnly,
      rect: rect,
      axis: axis,
    );
    OffsetToRevealContext._contexts.add(context);
    var result = getOffsetToReveal(target, alignment, rect: rect);
    OffsetToRevealContext._contexts.removeLast();
    final obstruction = target.getParentChildObstructionExtent();

    final resolvedAxis = (this is RenderViewportBase
        ? (this as RenderViewportBase).axis
        : axis);

    Rect shiftRect(Rect rect, double offset) {
      if (resolvedAxis == Axis.vertical) {
        return rect.shift(Offset(0, offset));
      } else {
        return rect.shift(Offset(offset, 0));
      }
    }

    if (obstruction.leading > 0) {
      final offset = obstruction.leading * (1.0 - alignment);
      result = RevealedOffset(
        offset: result.offset - offset,
        rect: shiftRect(result.rect, offset),
      );
    }
    if (obstruction.trailing > 0) {
      final offset = obstruction.trailing * alignment;
      result = RevealedOffset(
        offset: result.offset + offset,
        rect: shiftRect(result.rect, -offset),
      );
    }
    for (final callback in context._offsetResolvedCallbacks) {
      callback(result);
    }
    return result;
  }
}

class _SliverGeometryWithChildObstructionExtent extends SliverGeometry {
  const _SliverGeometryWithChildObstructionExtent({
    required super.scrollExtent,
    required super.paintExtent,
    required super.paintOrigin,
    required super.layoutExtent,
    required super.maxPaintExtent,
    required super.maxScrollObstructionExtent,
    required super.crossAxisExtent,
    required super.hitTestExtent,
    required super.visible,
    required super.hasVisualOverflow,
    required super.scrollOffsetCorrection,
    required super.cacheExtent,
    required ChildObstructionExtent? childObstructionExtent,
  }) : _childObstructionExtent = childObstructionExtent;

  @override
  SliverGeometry copyWith({
    double? scrollExtent,
    double? paintExtent,
    double? paintOrigin,
    double? layoutExtent,
    double? maxPaintExtent,
    double? maxScrollObstructionExtent,
    double? crossAxisExtent,
    double? hitTestExtent,
    bool? visible,
    bool? hasVisualOverflow,
    double? cacheExtent,
  }) {
    return _SliverGeometryWithChildObstructionExtent(
      scrollExtent: scrollExtent ?? this.scrollExtent,
      paintExtent: paintExtent ?? this.paintExtent,
      paintOrigin: paintOrigin ?? this.paintOrigin,
      layoutExtent: layoutExtent ?? this.layoutExtent,
      maxPaintExtent: maxPaintExtent ?? this.maxPaintExtent,
      maxScrollObstructionExtent:
          maxScrollObstructionExtent ?? this.maxScrollObstructionExtent,
      crossAxisExtent: crossAxisExtent ?? this.crossAxisExtent,
      hitTestExtent: hitTestExtent ?? this.hitTestExtent,
      visible: visible ?? this.visible,
      hasVisualOverflow: hasVisualOverflow ?? this.hasVisualOverflow,
      cacheExtent: cacheExtent ?? this.cacheExtent,
      scrollOffsetCorrection: scrollOffsetCorrection,
      childObstructionExtent: _childObstructionExtent,
    );
  }

  final ChildObstructionExtent? _childObstructionExtent;
}
