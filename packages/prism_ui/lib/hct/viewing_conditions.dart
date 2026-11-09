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

import 'dart:math' as math;

import 'color_math.dart';

class ViewingConditions {
  static final sRgb = ViewingConditions._make();

  final double backgroundYTowhitePointY;
  final double aw;
  final double nbb;
  final double ncb;
  final double c;
  final double nC;
  final List<double> rgbD;
  final double fl;
  final double fLRoot;
  final double z;

  const ViewingConditions._({
    required this.backgroundYTowhitePointY,
    required this.aw,
    required this.nbb,
    required this.ncb,
    required this.c,
    required this.nC,
    required this.rgbD,
    required this.fl,
    required this.fLRoot,
    required this.z,
  });

  factory ViewingConditions._make() {
    final whitePoint = ColorUtils.whitePointD65();
    final adaptingLuminance =
        200.0 / math.pi * ColorUtils.yFromLstar(50.0) / 100.0;
    const backgroundLstar = 50.0;
    const surround = 2.0;
    final xyz = whitePoint;
    final rW = xyz[0] * 0.401288 + xyz[1] * 0.650173 + xyz[2] * -0.051461;
    final gW = xyz[0] * -0.250268 + xyz[1] * 1.204414 + xyz[2] * 0.045854;
    final bW = xyz[0] * -0.002079 + xyz[1] * 0.048952 + xyz[2] * 0.953127;

    const f = 0.8 + (surround / 10.0);
    final c = (f >= 0.9)
        ? MathUtils.lerp(0.59, 0.69, (f - 0.9) * 10.0)
        : MathUtils.lerp(0.525, 0.59, (f - 0.8) * 10.0);
    var d =
        f *
        (1.0 - ((1.0 / 3.6) * math.exp((-adaptingLuminance - 42.0) / 92.0)));
    d = (d > 1.0)
        ? 1.0
        : (d < 0.0)
        ? 0.0
        : d;
    const nc = f;

    final rgbD = <double>[
      d * (100.0 / rW) + 1.0 - d,
      d * (100.0 / gW) + 1.0 - d,
      d * (100.0 / bW) + 1.0 - d,
    ];

    final k = 1.0 / (5.0 * adaptingLuminance + 1.0);
    final k4 = k * k * k * k;
    final k4F = 1.0 - k4;

    final fl =
        (k4 * adaptingLuminance) +
        (0.1 * k4F * k4F * math.pow(5.0 * adaptingLuminance, 1.0 / 3.0));
    final n = ColorUtils.yFromLstar(backgroundLstar) / whitePoint[1];

    final z = 1.48 + math.sqrt(n);

    final nbb = 0.725 / math.pow(n, 0.2);
    final ncb = nbb;

    final rgbAFactors = [
      math.pow(fl * rgbD[0] * rW / 100.0, 0.42),
      math.pow(fl * rgbD[1] * gW / 100.0, 0.42),
      math.pow(fl * rgbD[2] * bW / 100.0, 0.42),
    ];

    final rgbA = [
      (400.0 * rgbAFactors[0]) / (rgbAFactors[0] + 27.13),
      (400.0 * rgbAFactors[1]) / (rgbAFactors[1] + 27.13),
      (400.0 * rgbAFactors[2]) / (rgbAFactors[2] + 27.13),
    ];

    final aw = (40.0 * rgbA[0] + 20.0 * rgbA[1] + rgbA[2]) / 20.0 * nbb;

    return ViewingConditions._(
      backgroundYTowhitePointY: n,
      aw: aw,
      nbb: nbb,
      ncb: ncb,
      c: c,
      nC: nc,
      rgbD: rgbD,
      fl: fl,
      fLRoot: math.pow(fl, 0.25).toDouble(),
      z: z,
    );
  }
}
