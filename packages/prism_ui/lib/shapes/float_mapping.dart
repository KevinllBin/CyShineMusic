part of 'shapes.dart';

bool progressInRange(double progress, double progressFrom, double progressTo) {
  if (progressTo >= progressFrom) {
    return progress >= progressFrom && progress <= progressTo;
  } else {
    return progress >= progressFrom || progress <= progressTo;
  }
}

double linearMap(List<double> xValues, List<double> yValues, double x) {
  assert(x >= 0 && x <= 1, 'Invalid progress $x');

  var segmentStartIndex = -1;

  for (var i = 0; i < xValues.length; i++) {
    if (progressInRange(x, xValues[i], xValues[(i + 1) % xValues.length])) {
      segmentStartIndex = i;
      break;
    }
  }

  if (segmentStartIndex == -1) {
    throw StateError('segmentStartIndex not found.');
  }

  final segmentEndIndex = (segmentStartIndex + 1) % xValues.length;
  final segmentSizeX = positiveModulo(
    xValues[segmentEndIndex] - xValues[segmentStartIndex],
    1,
  );
  final segmentSizeY = positiveModulo(
    yValues[segmentEndIndex] - yValues[segmentStartIndex],
    1,
  );
  final positionInSegment = segmentSizeX < 0.001
      ? 0.5
      : positiveModulo(x - xValues[segmentStartIndex], 1) / segmentSizeX;

  return positiveModulo(
    yValues[segmentStartIndex] + segmentSizeY * positionInSegment,
    1,
  );
}

class DoubleMapper {
  DoubleMapper(List<(double, double)> mappings) {
    _sourceValues = List.filled(mappings.length, 0);
    _targetValues = List.filled(mappings.length, 0);
    for (var i = 0; i < mappings.length; i++) {
      final pair = mappings[i];
      _sourceValues[i] = pair.$1;
      _targetValues[i] = pair.$2;
    }
    validateProgress(_sourceValues);
    validateProgress(_targetValues);
  }

  late final List<double> _sourceValues;

  late final List<double> _targetValues;

  double map(double x) => linearMap(_sourceValues, _targetValues, x);

  double mapBack(double x) => linearMap(_targetValues, _sourceValues, x);
}

void validateProgress(List<double> p) {
  if (p.isEmpty) {
    throw ArgumentError('List is empty.');
  }

  var prev = p.last;
  var wraps = 0;

  for (var i = 0; i < p.length; i++) {
    final curr = p[i];

    if (curr < 0 || curr >= 1) {
      throw ArgumentError(
        'FloatMapping - Progress outside of range: ${p.join(', ')}',
      );
    }

    if (progressDistance(curr, prev).abs() <= distanceEpsilon) {
      throw ArgumentError(
        'FloatMapping - Progress repeats a value: ${p.join(', ')}',
      );
    }

    if (curr < prev) {
      wraps++;
      if (wraps > 1) {
        throw ArgumentError(
          'FloatMapping - Progress wraps more than once: ${p.join(', ')}',
        );
      }
    }

    prev = curr;
  }
}

double progressDistance(double p1, double p2) {
  final diff = (p1 - p2).abs();
  return math.min(diff, 1.0 - diff);
}
