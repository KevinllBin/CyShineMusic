part of 'shapes.dart';

class RoundedPolygon {
  RoundedPolygon._(this.features, this.center) : cubics = <Cubic>[] {
    _initCubics();

    assert(() {
      var prevCubic = cubics[cubics.length - 1];

      for (var index = 0; index < cubics.length; index++) {
        final cubic = cubics[index];

        if ((cubic.anchor0X - prevCubic.anchor1X).abs() > distanceEpsilon ||
            (cubic.anchor0Y - prevCubic.anchor1Y).abs() > distanceEpsilon) {
          throw ArgumentError(
            'RoundedPolygon must be contiguous, with the anchor points of all '
            'curves matching the anchor points of the preceding and succeeding '
            'cubics.',
          );
        }
        prevCubic = cubic;
      }

      return true;
    }());
  }

  factory RoundedPolygon.fromVerticesNum(
    int numVertices, {
    double radius = 1,
    double centerX = 0,
    double centerY = 0,
    CornerRounding rounding = CornerRounding.unrounded,
    List<CornerRounding>? perVertexRounding,
  }) {
    if (numVertices < 3) {
      throw ArgumentError('numVertices must be at least 3.');
    }

    return RoundedPolygon.fromVertices(
      _verticesFromNumVerts(numVertices, radius, centerX, centerY),
      rounding: rounding,
      perVertexRounding: perVertexRounding,
      centerX: centerX,
      centerY: centerY,
    );
  }

  factory RoundedPolygon.fromVertices(
    List<double> vertices, {
    CornerRounding rounding = CornerRounding.unrounded,
    List<CornerRounding>? perVertexRounding,
    double centerX = double.minPositive,
    double centerY = double.minPositive,
  }) {
    if (vertices.length < 6) {
      throw ArgumentError('Polygons must have at least 3 vertices.');
    }
    if (vertices.length.isOdd) {
      throw ArgumentError('The vertices array should have even size.');
    }
    if (perVertexRounding != null &&
        perVertexRounding.length * 2 != vertices.length) {
      throw ArgumentError(
        'perVertexRounding list should be either null or '
        'the same size as the number of vertices (vertices.size / 2).',
      );
    }
    final corners = <List<Cubic>>[];
    final n = vertices.length ~/ 2;
    final roundedCorners = <_RoundedCorner>[];
    for (var i = 0; i < n; i++) {
      final vtxRounding = perVertexRounding?[i] ?? rounding;
      final prevIndex = ((i + n - 1) % n) * 2;
      final nextIndex = ((i + 1) % n) * 2;
      roundedCorners.add(
        _RoundedCorner(
          Point(vertices[prevIndex], vertices[prevIndex + 1]),
          Point(vertices[i * 2], vertices[i * 2 + 1]),
          Point(vertices[nextIndex], vertices[nextIndex + 1]),
          vtxRounding,
        ),
      );
    }

    final cutAdjusts = List.generate(n, (ix) {
      final expectedRoundCut =
          roundedCorners[ix].expectedRoundCut +
          roundedCorners[(ix + 1) % n].expectedRoundCut;
      final expectedCut =
          roundedCorners[ix].expectedCut +
          roundedCorners[(ix + 1) % n].expectedCut;
      final vtxX = vertices[ix * 2];
      final vtxY = vertices[ix * 2 + 1];
      final nextVtxX = vertices[((ix + 1) % n) * 2];
      final nextVtxY = vertices[((ix + 1) % n) * 2 + 1];
      final sideSize = distance(vtxX - nextVtxX, vtxY - nextVtxY);

      if (expectedRoundCut > sideSize) {
        return (sideSize / expectedRoundCut, 0);
      } else if (expectedCut > sideSize) {
        return (
          1,
          (sideSize - expectedRoundCut) / (expectedCut - expectedRoundCut),
        );
      } else {
        return (1, 1);
      }
    });

    for (var i = 0; i < n; i++) {
      final allowedCuts = List<double>.filled(2, 0);

      for (var delta = 0; delta <= 1; delta++) {
        final (roundCutRatio, cutRatio) = cutAdjusts[(i + n - 1 + delta) % n];
        allowedCuts[delta] =
            roundedCorners[i].expectedRoundCut * roundCutRatio +
            (roundedCorners[i].expectedCut -
                    roundedCorners[i].expectedRoundCut) *
                cutRatio;
      }

      corners.add(roundedCorners[i].getCubics(allowedCuts[0], allowedCuts[1]));
    }

    final tempFeatures = <Feature>[];
    for (var i = 0; i < n; i++) {
      final prevVtxIndex = (i + n - 1) % n;
      final nextVtxIndex = (i + 1) % n;
      final currVertex = Point(vertices[i * 2], vertices[i * 2 + 1]);
      final prevVertex = Point(
        vertices[prevVtxIndex * 2],
        vertices[prevVtxIndex * 2 + 1],
      );
      final nextVertex = Point(
        vertices[nextVtxIndex * 2],
        vertices[nextVtxIndex * 2 + 1],
      );
      final cvx = convex(prevVertex, currVertex, nextVertex);
      tempFeatures
        ..add(CornerFeature(corners[i], convex: cvx))
        ..add(
          EdgeFeature([
            Cubic.straightLine(
              corners[i].last.anchor1X,
              corners[i].last.anchor1Y,
              corners[(i + 1) % n].first.anchor0X,
              corners[(i + 1) % n].first.anchor0Y,
            ),
          ]),
        );
    }

    final double cX;
    final double cY;

    if (centerX == double.minPositive || centerY == double.minPositive) {
      final center = calculateCenter(vertices);
      cX = center.x;
      cY = center.y;
    } else {
      cX = centerX;
      cY = centerY;
    }

    return RoundedPolygon.fromFeatures(tempFeatures, centerX: cX, centerY: cY);
  }

  factory RoundedPolygon.fromFeatures(
    List<Feature> features, {
    double centerX = double.nan,
    double centerY = double.nan,
  }) {
    if (features.length < 2) {
      throw ArgumentError('Polygons must have at least 2 features.');
    }

    if (centerX.isNaN || centerY.isNaN) {
      final vertices = <double>[];

      for (final feature in features) {
        for (final cubic in feature.cubics) {
          vertices
            ..add(cubic.anchor0X)
            ..add(cubic.anchor0Y);
        }
      }

      final center = calculateCenter(vertices);

      final cX = centerX.isNaN ? center.x : centerX;
      final cY = centerY.isNaN ? center.y : centerY;

      return RoundedPolygon._(features, Point(cX, cY));
    }

    return RoundedPolygon._(features, Point(centerX, centerY));
  }

  factory RoundedPolygon.circle({
    int numVertices = 8,
    double radius = 1,
    double centerX = 0,
    double centerY = 0,
  }) {
    if (numVertices < 3) {
      throw ArgumentError('Circle must have at least three vertices.');
    }

    final theta = math.pi / numVertices;
    final polygonRadius = radius / math.cos(theta);
    return RoundedPolygon.fromVerticesNum(
      numVertices,
      radius: polygonRadius,
      centerX: centerX,
      centerY: centerY,
      rounding: CornerRounding(radius: radius),
    );
  }

  factory RoundedPolygon.rectangle({
    double width = 2,
    double height = 2,
    CornerRounding rounding = CornerRounding.unrounded,
    List<CornerRounding>? perVertexRounding,
    double centerX = 0,
    double centerY = 0,
  }) {
    final left = centerX - width / 2;
    final top = centerY - height / 2;
    final right = centerX + width / 2;
    final bottom = centerY + height / 2;

    return RoundedPolygon.fromVertices(
      [right, bottom, left, bottom, left, top, right, top],
      rounding: rounding,
      perVertexRounding: perVertexRounding,
      centerX: centerX,
      centerY: centerY,
    );
  }

  factory RoundedPolygon.star({
    required int numVerticesPerRadius,
    double radius = 1,
    double innerRadius = 0.5,
    CornerRounding rounding = CornerRounding.unrounded,
    CornerRounding? innerRounding,
    List<CornerRounding>? perVertexRounding,
    double centerX = 0,
    double centerY = 0,
  }) {
    if (radius <= 0 || innerRadius <= 0) {
      throw ArgumentError('Star radii must both be greater than 0.');
    }
    if (innerRadius >= radius) {
      throw ArgumentError('innerRadius must be less than radius.');
    }

    var pvRounding = perVertexRounding;
    if (pvRounding == null && innerRounding != null) {
      pvRounding = [
        for (var i = 0; i < numVerticesPerRadius; i++) ...[
          rounding,
          innerRounding,
        ],
      ];
    }

    return RoundedPolygon.fromVertices(
      _starVerticesFromNumVerts(
        numVerticesPerRadius,
        radius,
        innerRadius,
        centerX,
        centerY,
      ),
      rounding: rounding,
      perVertexRounding: pvRounding,
      centerX: centerX,
      centerY: centerY,
    );
  }

  final List<Feature> features;

  final Point center;

  final List<Cubic> cubics;

  double get centerX => center.x;

  double get centerY => center.y;

  void _initCubics() {
    Cubic? firstCubic;
    Cubic? lastCubic;
    List<Cubic>? firstFeatureSplitStart;
    List<Cubic>? firstFeatureSplitEnd;

    if (features.isNotEmpty && features[0].cubics.length == 3) {
      final centerCubic = features[0].cubics[1];
      final (start, end) = centerCubic.split(0.5);
      firstFeatureSplitStart = [features[0].cubics[0], start];
      firstFeatureSplitEnd = [end, features[0].cubics[2]];
    }

    for (var i = 0; i <= features.length; i++) {
      final List<Cubic> featureCubics;

      if (i == 0 && firstFeatureSplitEnd != null) {
        featureCubics = firstFeatureSplitEnd;
      } else if (i == features.length) {
        if (firstFeatureSplitStart != null) {
          featureCubics = firstFeatureSplitStart;
        } else {
          break;
        }
      } else {
        featureCubics = features[i].cubics;
      }

      for (var j = 0; j < featureCubics.length; j++) {
        final cubic = featureCubics[j];

        if (!cubic.zeroLength()) {
          if (lastCubic != null) cubics.add(lastCubic);
          lastCubic = cubic;
          firstCubic ??= cubic;
        } else {
          if (lastCubic != null) {
            final points = lastCubic.points.toList();
            points[6] = cubic.anchor1X;
            points[7] = cubic.anchor1Y;
            lastCubic = Cubic._raw(points);
          }
        }
      }
    }

    if (lastCubic != null && firstCubic != null) {
      cubics.add(
        Cubic(
          lastCubic.anchor0X,
          lastCubic.anchor0Y,
          lastCubic.control0X,
          lastCubic.control0Y,
          lastCubic.control1X,
          lastCubic.control1Y,
          firstCubic.anchor0X,
          firstCubic.anchor0Y,
        ),
      );
    } else {
      cubics.add(
        Cubic(
          centerX,
          centerY,
          centerX,
          centerY,
          centerX,
          centerY,
          centerX,
          centerY,
        ),
      );
    }
  }

  RoundedPolygon transformed(PointTransformer f) {
    final center = this.center.transformed(f);
    return RoundedPolygon._([
      for (var i = 0; i < features.length; i++) features[i].transformed(f),
    ], center);
  }

  RoundedPolygon normalized() {
    final bounds = calculateBounds();
    final width = bounds[2] - bounds[0];
    final height = bounds[3] - bounds[1];
    final side = math.max(width, height);

    final offsetX = (side - width) / 2 - bounds[0]; /* left */
    final offsetY = (side - height) / 2 - bounds[1]; /* top */

    return transformed((x, y) => ((x + offsetX) / side, (y + offsetY) / side));
  }

  List<double> calculateBounds({
    List<double>? bounds,
    bool approximate = true,
  }) {
    bounds ??= List.filled(4, 0);

    if (bounds.length < 4) {
      throw ArgumentError('Required bounds size of 4.');
    }

    var minX = double.maxFinite;
    var minY = double.maxFinite;
    var maxX = double.minPositive;
    var maxY = double.minPositive;

    for (var i = 0; i < cubics.length; i++) {
      cubics[i].calculateBounds(bounds, approximate: approximate);
      minX = math.min(minX, bounds[0]);
      minY = math.min(minY, bounds[1]);
      maxX = math.max(maxX, bounds[2]);
      maxY = math.max(maxY, bounds[3]);
    }

    bounds[0] = minX;
    bounds[1] = minY;
    bounds[2] = maxX;
    bounds[3] = maxY;

    return bounds;
  }
}

Point calculateCenter(List<double> vertices) {
  var cumulativeX = 0.0;
  var cumulativeY = 0.0;
  var index = 0;
  while (index < vertices.length) {
    cumulativeX += vertices[index++];
    cumulativeY += vertices[index++];
  }
  return Point(
    cumulativeX / (vertices.length / 2),
    cumulativeY / (vertices.length / 2),
  );
}

class _RoundedCorner {
  _RoundedCorner(this.p0, this.p1, this.p2, this.rounding) {
    final v01 = p0 - p1;
    final v21 = p2 - p1;
    final d01 = v01.getDistance();
    final d21 = v21.getDistance();

    if (d01 > 0 && d21 > 0) {
      d1 = v01 / d01;
      d2 = v21 / d21;
      cornerRadius = rounding?.radius ?? 0;
      smoothing = rounding?.smoothing ?? 0;

      cosAngle = d1.dotProduct(d2);

      sinAngle = math.sqrt(1 - square(cosAngle));

      expectedRoundCut = (sinAngle > 1e-3)
          ? cornerRadius * (cosAngle + 1) / sinAngle
          : 0;
    } else {
      d1 = Point.zero;
      d2 = Point.zero;
      cornerRadius = 0;
      smoothing = 0;
      cosAngle = 0;
      sinAngle = 0;
      expectedRoundCut = 0;
    }
  }

  final Point p0;

  final Point p1;

  final Point p2;

  final CornerRounding? rounding;

  late final Point d1;

  late final Point d2;

  late final double cornerRadius;

  late final double smoothing;

  late final double cosAngle;

  late final double sinAngle;

  late final double expectedRoundCut;

  double get expectedCut => (1 + smoothing) * expectedRoundCut;

  Point center = Point.zero;

  List<Cubic> getCubics(double allowedCut0, double allowedCut1) {
    final allowedCut = math.min(allowedCut0, allowedCut1);

    if (expectedRoundCut < distanceEpsilon ||
        allowedCut < distanceEpsilon ||
        cornerRadius < distanceEpsilon) {
      center = p1;
      return [Cubic.straightLine(p1.x, p1.y, p1.x, p1.y)];
    }

    final actualRoundCut = math.min(allowedCut, expectedRoundCut);

    final actualSmoothing0 = _calculateActualSmoothingValue(allowedCut0);
    final actualSmoothing1 = _calculateActualSmoothingValue(allowedCut1);
    final actualR = cornerRadius * actualRoundCut / expectedRoundCut;
    final centerDistance = math.sqrt(square(actualR) + square(actualRoundCut));
    center = p1 + ((d1 + d2) / 2).getDirection() * centerDistance;
    final circleIntersection0 = p1 + d1 * actualRoundCut;
    final circleIntersection2 = p1 + d2 * actualRoundCut;
    final flanking0 = _computeFlankingCurve(
      actualRoundCut,
      actualSmoothing0,
      p1,
      p0,
      circleIntersection0,
      circleIntersection2,
      center,
      actualR,
    );
    final flanking2 = _computeFlankingCurve(
      actualRoundCut,
      actualSmoothing1,
      p1,
      p2,
      circleIntersection2,
      circleIntersection0,
      center,
      actualR,
    ).reverse();

    return [
      flanking0,
      Cubic.circularArc(
        center.x,
        center.y,
        flanking0.anchor1X,
        flanking0.anchor1Y,
        flanking2.anchor0X,
        flanking2.anchor0Y,
      ),
      flanking2,
    ];
  }

  double _calculateActualSmoothingValue(double allowedCut) {
    if (allowedCut > expectedCut) {
      return smoothing;
    } else if (allowedCut > expectedRoundCut) {
      return smoothing *
          (allowedCut - expectedRoundCut) /
          (expectedCut - expectedRoundCut);
    } else {
      return 0;
    }
  }

  Cubic _computeFlankingCurve(
    double actualRoundCut,
    double actualSmoothingValues,
    Point corner,
    Point sideStart,
    Point circleSegmentIntersection,
    Point otherCircleSegmentIntersection,
    Point circleCenter,
    double actualR,
  ) {
    final sideDirection = (sideStart - corner).getDirection();
    final curveStart =
        corner + sideDirection * actualRoundCut * (1 + actualSmoothingValues);

    final p = interpolate(
      circleSegmentIntersection,
      (circleSegmentIntersection + otherCircleSegmentIntersection) / 2,
      actualSmoothingValues,
    );

    final curveEnd =
        circleCenter +
        directionVector(p.x - circleCenter.x, p.y - circleCenter.y) * actualR;

    final circleTangent = (curveEnd - circleCenter).rotate90();
    final anchorEnd =
        _lineIntersection(sideStart, sideDirection, curveEnd, circleTangent) ??
        circleSegmentIntersection;

    final anchorStart = (curveStart + anchorEnd * 2) / 3;

    return Cubic.fromPoints(curveStart, anchorStart, anchorEnd, curveEnd);
  }

  Point? _lineIntersection(Point p0, Point d0, Point p1, Point d1) {
    final rotatedD1 = d1.rotate90();
    final den = d0.dotProduct(rotatedD1);

    if (den.abs() < distanceEpsilon) {
      return null;
    }

    final num = (p1 - p0).dotProduct(rotatedD1);

    if (den.abs() < distanceEpsilon * num.abs()) {
      return null;
    }

    final k = num / den;
    return p0 + d0 * k;
  }
}

List<double> _verticesFromNumVerts(
  int numVertices,
  double radius,
  double centerX,
  double centerY,
) {
  final result = List<double>.filled(numVertices * 2, 0);

  var arrayIndex = 0;
  for (var i = 0; i < numVertices; i++) {
    final vertex =
        radialToCartesian(radius, math.pi / numVertices * 2 * i) +
        Point(centerX, centerY);

    result[arrayIndex++] = vertex.x;
    result[arrayIndex++] = vertex.y;
  }

  return result;
}

List<double> _starVerticesFromNumVerts(
  int numVerticesPerRadius,
  double radius,
  double innerRadius,
  double centerX,
  double centerY,
) {
  final result = List<double>.filled(numVerticesPerRadius * 4, 0);
  var arrayIndex = 0;

  for (var i = 0; i < numVerticesPerRadius; i++) {
    var vertex = radialToCartesian(
      radius,
      math.pi / numVerticesPerRadius * 2 * i,
    );
    result[arrayIndex++] = vertex.x + centerX;
    result[arrayIndex++] = vertex.y + centerY;
    vertex = radialToCartesian(
      innerRadius,
      math.pi / numVerticesPerRadius * (2 * i + 1),
    );
    result[arrayIndex++] = vertex.x + centerX;
    result[arrayIndex++] = vertex.y + centerY;
  }

  return result;
}
