/*
Copyright 2021 Google LLC

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

import 'dart:math';

class ColorUtils {
  static const _srgbToXyz = [
    [0.41233895, 0.35762064, 0.18051042],
    [0.2126, 0.7152, 0.0722],
    [0.01932141, 0.11916382, 0.95034478],
  ];

  static const _whitePointD65 = [95.047, 100.0, 108.883];

  static int argbFromRgb(int red, int green, int blue) {
    return 255 << 24 | (red & 255) << 16 | (green & 255) << 8 | blue & 255;
  }

  static int argbFromLinrgb(List<double> linrgb) {
    final r = delinearized(linrgb[0]);
    final g = delinearized(linrgb[1]);
    final b = delinearized(linrgb[2]);
    return argbFromRgb(r, g, b);
  }

  static int redFromArgb(int argb) {
    return argb >> 16 & 255;
  }

  static int greenFromArgb(int argb) {
    return argb >> 8 & 255;
  }

  static int blueFromArgb(int argb) {
    return argb & 255;
  }

  static List<double> xyzFromArgb(int argb) {
    final r = linearized(redFromArgb(argb));
    final g = linearized(greenFromArgb(argb));
    final b = linearized(blueFromArgb(argb));
    return MathUtils.matrixMultiply([r, g, b], _srgbToXyz);
  }

  static List<double> labFromArgb(int argb) {
    final linearR = linearized(redFromArgb(argb));
    final linearG = linearized(greenFromArgb(argb));
    final linearB = linearized(blueFromArgb(argb));
    const matrix = _srgbToXyz;
    final x =
        matrix[0][0] * linearR +
        matrix[0][1] * linearG +
        matrix[0][2] * linearB;
    final y =
        matrix[1][0] * linearR +
        matrix[1][1] * linearG +
        matrix[1][2] * linearB;
    final z =
        matrix[2][0] * linearR +
        matrix[2][1] * linearG +
        matrix[2][2] * linearB;
    const whitePoint = _whitePointD65;
    final xNormalized = x / whitePoint[0];
    final yNormalized = y / whitePoint[1];
    final zNormalized = z / whitePoint[2];
    final fx = _labF(xNormalized);
    final fy = _labF(yNormalized);
    final fz = _labF(zNormalized);
    final l = 116.0 * fy - 16;
    final a = 500.0 * (fx - fy);
    final b = 200.0 * (fy - fz);
    return [l, a, b];
  }

  static int argbFromLstar(double lstar) {
    final y = yFromLstar(lstar);
    final component = delinearized(y);
    return argbFromRgb(component, component, component);
  }

  static double lstarFromArgb(int argb) {
    final y = xyzFromArgb(argb)[1];
    return 116.0 * _labF(y / 100.0) - 16.0;
  }

  static double yFromLstar(double lstar) {
    return 100.0 * _labInvf((lstar + 16.0) / 116.0);
  }

  static double lstarFromY(double y) {
    return _labF(y / 100.0) * 116.0 - 16.0;
  }

  static double linearized(int rgbComponent) {
    final normalized = rgbComponent / 255.0;
    if (normalized <= 0.040449936) {
      return normalized / 12.92 * 100.0;
    } else {
      return pow((normalized + 0.055) / 1.055, 2.4).toDouble() * 100.0;
    }
  }

  static int delinearized(double rgbComponent) {
    final normalized = rgbComponent / 100.0;
    var delinearized = 0.0;
    if (normalized <= 0.0031308) {
      delinearized = normalized * 12.92;
    } else {
      delinearized = 1.055 * pow(normalized, 1.0 / 2.4).toDouble() - 0.055;
    }
    return MathUtils.clampInt(0, 255, (delinearized * 255.0).round());
  }

  static List<double> whitePointD65() {
    return _whitePointD65;
  }

  static double _labF(double t) {
    const e = 216.0 / 24389.0;
    const kappa = 24389.0 / 27.0;
    if (t > e) {
      return pow(t, 1.0 / 3.0).toDouble();
    } else {
      return (kappa * t + 16) / 116;
    }
  }

  static double _labInvf(double ft) {
    const e = 216.0 / 24389.0;
    const kappa = 24389.0 / 27.0;
    final ft3 = ft * ft * ft;
    if (ft3 > e) {
      return ft3;
    } else {
      return (116 * ft - 16) / kappa;
    }
  }
}

class MathUtils {
  static int signum(double num) {
    if (num < 0) {
      return -1;
    } else if (num == 0) {
      return 0;
    } else {
      return 1;
    }
  }

  static double lerp(double start, double stop, double amount) {
    return (1.0 - amount) * start + amount * stop;
  }

  static int clampInt(int min, int max, int input) {
    if (input < min) {
      return min;
    } else if (input > max) {
      return max;
    }

    return input;
  }

  static double clampDouble(double min, double max, double input) {
    if (input < min) {
      return min;
    } else if (input > max) {
      return max;
    }

    return input;
  }

  static int sanitizeDegreesInt(int degrees) {
    degrees = degrees % 360;
    if (degrees < 0) {
      degrees = degrees + 360;
    }
    return degrees;
  }

  static double sanitizeDegreesDouble(double degrees) {
    degrees = degrees % 360.0;
    if (degrees < 0) {
      degrees = degrees + 360.0;
    }
    return degrees;
  }

  static List<double> matrixMultiply(
    List<double> row,
    List<List<double>> matrix,
  ) {
    final a =
        row[0] * matrix[0][0] + row[1] * matrix[0][1] + row[2] * matrix[0][2];
    final b =
        row[0] * matrix[1][0] + row[1] * matrix[1][1] + row[2] * matrix[1][2];
    final c =
        row[0] * matrix[2][0] + row[1] * matrix[2][1] + row[2] * matrix[2][2];
    return [a, b, c];
  }
}
