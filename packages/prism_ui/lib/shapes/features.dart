part of 'shapes.dart';

abstract class Feature {
  const Feature(List<Cubic> cubics) : _cubics = cubics;

  final List<Cubic> _cubics;

  List<Cubic> get cubics => UnmodifiableListView(_cubics);

  bool get isCorner;

  Feature transformed(PointTransformer f);
}

class EdgeFeature extends Feature {
  EdgeFeature(super._cubics);

  @override
  Feature transformed(PointTransformer f) => EdgeFeature(
    List.generate(_cubics.length, (i) => _cubics[i].transformed(f)),
  );

  @override
  bool get isCorner => false;
}

class CornerFeature extends Feature {
  const CornerFeature(super._cubics, {this.convex = true});

  final bool convex;

  @override
  Feature transformed(PointTransformer f) => CornerFeature(
    List.generate(_cubics.length, (i) => _cubics[i].transformed(f)),
    convex: convex,
  );

  @override
  bool get isCorner => true;
}
