part of 'shapes.dart';

class MeasuredPolygon {
  MeasuredPolygon._({
    required Measurer measurer,
    required List<ProgressableFeature> features,
    required List<Cubic> cubics,
    required List<double> outlineProgress,
  }) : assert(
         outlineProgress.length == cubics.length + 1,
         'Outline progress length is expected to be the cubics length + 1',
       ),
       assert(
         outlineProgress.first == 0,
         'First outline progress value is expected to be zero',
       ),
       assert(
         outlineProgress.last == 1,
         'Last outline progress value is expected to be one',
       ),
       _measurer = measurer,
       _features = features {
    final measuredCubics = <MeasuredCubic>[];
    var startOutlineProgress = 0.0;
    for (var i = 0; i < cubics.length; i++) {
      if ((outlineProgress[i + 1] - outlineProgress[i]) > distanceEpsilon) {
        measuredCubics.add(
          MeasuredCubic(
            measurer: measurer,
            cubic: cubics[i],
            startOutlineProgress: startOutlineProgress,
            endOutlineProgress: outlineProgress[i + 1],
          ),
        );
        startOutlineProgress = outlineProgress[i + 1];
      }
    }
    measuredCubics[measuredCubics.length - 1].updateProgressRange(
      endOutlineProgress: 1,
    );
    _cubics = measuredCubics;
  }

  factory MeasuredPolygon.measurePolygon(
    Measurer measurer,
    RoundedPolygon polygon,
  ) {
    final cubics = <Cubic>[];
    final featureToCubic = <(Feature, int)>[];

    for (
      var featureIndex = 0;
      featureIndex < polygon.features.length;
      featureIndex++
    ) {
      final feature = polygon.features[featureIndex];
      for (
        var cubicIndex = 0;
        cubicIndex < feature.cubics.length;
        cubicIndex++
      ) {
        if (feature is CornerFeature &&
            cubicIndex == feature.cubics.length ~/ 2) {
          featureToCubic.add((feature, cubics.length));
        }
        cubics.add(feature.cubics[cubicIndex]);
      }
    }

    final measures = List<double>.filled(cubics.length + 1, 0);
    var totalMeasure = 0.0;

    for (var i = 0; i < cubics.length; i++) {
      final measure = measurer.measureCubic(cubics[i]);
      if (measure < 0) {
        throw StateError(
          'Measured cubic is expected to be greater or equal to zero',
        );
      }
      totalMeasure += measure;
      measures[i + 1] = totalMeasure;
    }

    final outlineProgress = List<double>.filled(measures.length, 0);
    for (var i = 0; i < measures.length; i++) {
      outlineProgress[i] = measures[i] / totalMeasure;
    }

    final features = List<ProgressableFeature>.generate(featureToCubic.length, (
      i,
    ) {
      final ix = featureToCubic[i].$2;
      return ProgressableFeature(
        positiveModulo((outlineProgress[ix] + outlineProgress[ix + 1]) / 2, 1),
        featureToCubic[i].$1,
      );
    });

    return MeasuredPolygon._(
      measurer: measurer,
      features: features,
      cubics: cubics,
      outlineProgress: outlineProgress,
    );
  }

  final Measurer _measurer;

  late final List<MeasuredCubic> _cubics;

  final List<ProgressableFeature> _features;

  List<ProgressableFeature> get features => UnmodifiableListView(_features);

  MeasuredCubic get first => _cubics.first;

  MeasuredCubic get last => _cubics.last;

  int get length => _cubics.length;

  MeasuredCubic operator [](int index) => _cubics[index];

  MeasuredCubic? getOrNull(int index) {
    final length = _cubics.length;

    if (index < 0 || index >= length) {
      return null;
    }

    return _cubics[index];
  }

  MeasuredPolygon cutAndShift(double cuttingPoint) {
    if (cuttingPoint < 0 && cuttingPoint > 1) {
      throw ArgumentError('Cutting point is expected to be between 0 and 1');
    }

    if (cuttingPoint < distanceEpsilon) return this;

    final targetIndex = _cubics.indexWhere(
      (c) =>
          cuttingPoint >= c._startOutlineProgress &&
          cuttingPoint <= c._endOutlineProgress,
    );
    final target = _cubics[targetIndex];

    final (b1, b2) = target.cutAtProgress(cuttingPoint);

    final retCubics = [b2.cubic];
    for (var i = 1; i < _cubics.length; i++) {
      retCubics.add(_cubics[(i + targetIndex) % _cubics.length].cubic);
    }
    retCubics.add(b1.cubic);

    final retOutlineProgress = List<double>.filled(_cubics.length + 2, 0);

    for (var i = 0; i < _cubics.length + 2; i++) {
      if (i == 0) {
        retOutlineProgress[i] = 0;
      } else if (i == _cubics.length + 1) {
        retOutlineProgress[i] = 1;
      } else {
        final cubicIndex = (targetIndex + i - 1) % _cubics.length;
        retOutlineProgress[i] = positiveModulo(
          _cubics[cubicIndex]._endOutlineProgress - cuttingPoint,
          1,
        );
      }
    }

    final newFeatures = [
      for (var i = 0; i < _features.length; i++)
        ProgressableFeature(
          positiveModulo(_features[i].progress - cuttingPoint, 1),
          _features[i].feature,
        ),
    ];

    return MeasuredPolygon._(
      measurer: _measurer,
      features: newFeatures,
      cubics: retCubics,
      outlineProgress: retOutlineProgress,
    );
  }
}

class MeasuredCubic {
  MeasuredCubic({
    required this.measurer,
    required this.cubic,
    required double startOutlineProgress,
    required double endOutlineProgress,
  }) : assert(
         startOutlineProgress >= 0 && startOutlineProgress <= 1,
         'startOutlineProgress has to be in [0..1] range',
       ),
       assert(
         endOutlineProgress >= 0 && endOutlineProgress <= 1,
         'endOutlineProgress has to be in range [0..1]',
       ),
       assert(
         endOutlineProgress >= startOutlineProgress,
         'endOutlineProgress is expected to be equal or greater than '
         'startOutlineProgress',
       ),
       _startOutlineProgress = startOutlineProgress,
       _endOutlineProgress = endOutlineProgress {
    measuredSize = measurer.measureCubic(cubic);
  }

  final Measurer measurer;

  final Cubic cubic;

  late final double measuredSize;

  double _startOutlineProgress;

  double _endOutlineProgress;

  double get startOutlineProgress => _startOutlineProgress;

  double get endOutlineProgress => _endOutlineProgress;

  void updateProgressRange({
    double? startOutlineProgress,
    double? endOutlineProgress,
  }) {
    startOutlineProgress ??= _startOutlineProgress;
    endOutlineProgress ??= _endOutlineProgress;

    if (endOutlineProgress < startOutlineProgress) {
      throw ArgumentError(
        'endOutlineProgress is expected to be equal or greater than '
        'startOutlineProgress',
      );
    }

    _startOutlineProgress = startOutlineProgress;
    _endOutlineProgress = endOutlineProgress;
  }

  (MeasuredCubic, MeasuredCubic) cutAtProgress(double cutOutlineProgress) {
    final boundedCutOutlineProgress = cutOutlineProgress.coerceIn(
      _startOutlineProgress,
      _endOutlineProgress,
    );
    final outlineProgressSize = _endOutlineProgress - _startOutlineProgress;
    final progressFromStart = boundedCutOutlineProgress - _startOutlineProgress;

    final relativeProgress = progressFromStart / outlineProgressSize;
    final t = measurer.findCubicCutPoint(
      cubic,
      relativeProgress * measuredSize,
    );

    if (t < 0 || t > 1) {
      throw ArgumentError('Cubic cut point is expected to be between 0 and 1.');
    }

    final (c1, c2) = cubic.split(t);
    return (
      MeasuredCubic(
        measurer: measurer,
        cubic: c1,
        startOutlineProgress: _startOutlineProgress,
        endOutlineProgress: boundedCutOutlineProgress,
      ),
      MeasuredCubic(
        measurer: measurer,
        cubic: c2,
        startOutlineProgress: boundedCutOutlineProgress,
        endOutlineProgress: _endOutlineProgress,
      ),
    );
  }
}

abstract interface class Measurer {
  const Measurer();

  double measureCubic(Cubic c);

  double findCubicCutPoint(Cubic c, double m);
}

class LengthMeasurer implements Measurer {
  const LengthMeasurer();

  static const _segments = 3;

  @override
  double measureCubic(Cubic c) {
    return _closestProgressTo(c, double.infinity).$2;
  }

  @override
  double findCubicCutPoint(Cubic c, double m) {
    return _closestProgressTo(c, m).$1;
  }

  (double, double) _closestProgressTo(Cubic cubic, double threshold) {
    var total = 0.0;
    var remainder = threshold;
    var prev = Point(cubic.anchor0X, cubic.anchor0Y);

    for (var i = 0; i <= _segments; i++) {
      final progress = i / _segments;
      final point = cubic.pointOnCurve(progress);
      final segment = (point - prev).getDistance();

      if (segment >= remainder) {
        return (progress - (1.0 - remainder / segment) / _segments, threshold);
      }

      remainder -= segment;
      total += segment;
      prev = point;
    }

    return (1.0, total);
  }
}
