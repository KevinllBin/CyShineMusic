part of 'shapes.dart';

typedef MeasuredFeatures = List<ProgressableFeature>;

class ProgressableFeature {
  const ProgressableFeature(this.progress, this.feature);

  final double progress;

  final Feature feature;
}

class DistanceVertex {
  const DistanceVertex(this.distance, this.f1, this.f2);

  final double distance;

  final ProgressableFeature f1;

  final ProgressableFeature f2;
}

DoubleMapper featureMapper(
  MeasuredFeatures features1,
  MeasuredFeatures features2,
) {
  final filteredFeatures1 = <ProgressableFeature>[];
  for (var i = 0; i < features1.length; i++) {
    if (features1[i].feature.isCorner) {
      filteredFeatures1.add(features1[i]);
    }
  }

  final filteredFeatures2 = <ProgressableFeature>[];
  for (var i = 0; i < features2.length; i++) {
    if (features2[i].feature.isCorner) {
      filteredFeatures2.add(features2[i]);
    }
  }

  final featureProgressMapping = doMapping(
    filteredFeatures1,
    filteredFeatures2,
  );

  return DoubleMapper(featureProgressMapping);
}

List<(double, double)> doMapping(
  List<ProgressableFeature> features1,
  List<ProgressableFeature> features2,
) {
  final distanceVertexList = <DistanceVertex>[];

  for (final f1 in features1) {
    for (final f2 in features2) {
      final d = featureDistSquared(f1.feature, f2.feature);
      if (d != double.maxFinite) {
        distanceVertexList.add(DistanceVertex(d, f1, f2));
      }
    }
  }

  distanceVertexList.sort((a, b) => a.distance.compareTo(b.distance));

  if (distanceVertexList.isEmpty) {
    return [(0.0, 0.0), (0.5, 0.5)];
  }

  if (distanceVertexList.length == 1) {
    final d = distanceVertexList.first;

    final f1 = d.f1.progress;
    final f2 = d.f2.progress;

    return [(f1, f2), ((f1 + 0.5) % 1, (f2 + 0.5) % 1)];
  }

  final helper = _MappingHelper();

  for (final d in distanceVertexList) {
    helper.addMapping(d.f1, d.f2);
  }

  return helper.mapping;
}

class _MappingHelper {
  final mapping = <(double, double)>[];

  final _usedF1 = <ProgressableFeature>{};
  final _usedF2 = <ProgressableFeature>{};

  void addMapping(ProgressableFeature f1, ProgressableFeature f2) {
    if (_usedF1.contains(f1) || _usedF2.contains(f2)) {
      return;
    }

    final index = binarySearchBy<(double, double), double>(
      mapping,
      (it) => it.$1,
      (a, b) => a.compareTo(b),
      f1.progress,
    );

    if (index >= 0) {
      throw StateError("There can't be two features with the same progress.");
    }

    final insertionIndex = -index - 1;
    final n = mapping.length;

    if (n >= 1) {
      final (before1, before2) = mapping[(insertionIndex + n - 1) % n];
      final (after1, after2) = mapping[insertionIndex % n];

      if (progressDistance(f1.progress, before1) < distanceEpsilon ||
          progressDistance(f1.progress, after1) < distanceEpsilon ||
          progressDistance(f2.progress, before2) < distanceEpsilon ||
          progressDistance(f2.progress, after2) < distanceEpsilon) {
        return;
      }

      if (n > 1 && !progressInRange(f2.progress, before2, after2)) {
        return;
      }
    }

    mapping.insert(insertionIndex, (f1.progress, f2.progress));
    _usedF1.add(f1);
    _usedF2.add(f2);
  }
}

double featureDistSquared(Feature f1, Feature f2) {
  if (f1 is CornerFeature && f2 is CornerFeature && f1.convex != f2.convex) {
    return double.maxFinite;
  }

  return (featureRepresentativePoint(f1) - featureRepresentativePoint(f2))
      .getDistanceSquared();
}

Point featureRepresentativePoint(Feature feature) {
  final cubics = feature.cubics;
  final x = (cubics.first.anchor0X + cubics.last.anchor1X) / 2;
  final y = (cubics.first.anchor0Y + cubics.last.anchor1Y) / 2;
  return Point(x, y);
}
