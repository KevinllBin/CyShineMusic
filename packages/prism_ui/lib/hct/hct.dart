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
import 'hct_solver.dart';
import 'viewing_conditions.dart';

class Hct {
  final int _argb;
  final double hue;
  final double chroma;
  final double tone;

  Hct._(this._argb, ({double hue, double chroma}) cam)
    : hue = cam.hue,
      chroma = cam.chroma,
      tone = ColorUtils.lstarFromArgb(_argb);

  factory Hct.fromInt(int argb) => Hct._(argb, _hueAndChroma(argb));

  factory Hct.from(double hue, double chroma, double tone) =>
      Hct.fromInt(HctSolver.solveToInt(hue, chroma, tone));

  int toInt() => _argb;
}

({double hue, double chroma}) _hueAndChroma(int argb) {
  final viewingConditions = ViewingConditions.sRgb;
  final xyz = ColorUtils.xyzFromArgb(argb);
  final x = xyz[0];
  final y = xyz[1];
  final z = xyz[2];

  final rC = 0.401288 * x + 0.650173 * y - 0.051461 * z;
  final gC = -0.250268 * x + 1.204414 * y + 0.045854 * z;
  final bC = -0.002079 * x + 0.048952 * y + 0.953127 * z;

  final rD = viewingConditions.rgbD[0] * rC;
  final gD = viewingConditions.rgbD[1] * gC;
  final bD = viewingConditions.rgbD[2] * bC;

  final rAF = math
      .pow(viewingConditions.fl * rD.abs() / 100.0, 0.42)
      .toDouble();
  final gAF = math
      .pow(viewingConditions.fl * gD.abs() / 100.0, 0.42)
      .toDouble();
  final bAF = math
      .pow(viewingConditions.fl * bD.abs() / 100.0, 0.42)
      .toDouble();
  final rA = MathUtils.signum(rD) * 400.0 * rAF / (rAF + 27.13);
  final gA = MathUtils.signum(gD) * 400.0 * gAF / (gAF + 27.13);
  final bA = MathUtils.signum(bD) * 400.0 * bAF / (bAF + 27.13);

  final a = (11.0 * rA + -12.0 * gA + bA) / 11.0;
  final b = (rA + gA - 2.0 * bA) / 9.0;
  final u = (20.0 * rA + 20.0 * gA + 21.0 * bA) / 20.0;
  final p2 = (40.0 * rA + 20.0 * gA + bA) / 20.0;

  final atanDegrees = math.atan2(b, a) * 180.0 / math.pi;
  final hue = atanDegrees < 0
      ? atanDegrees + 360.0
      : atanDegrees >= 360
      ? atanDegrees - 360
      : atanDegrees;

  final ac = p2 * viewingConditions.nbb;
  final j =
      100.0 *
      math.pow(
        ac / viewingConditions.aw,
        viewingConditions.c * viewingConditions.z,
      );

  final huePrime = (hue < 20.14) ? hue + 360 : hue;
  final eHue = (1.0 / 4.0) * (math.cos(huePrime * math.pi / 180.0 + 2.0) + 3.8);
  final p1 =
      50000.0 / 13.0 * eHue * viewingConditions.nC * viewingConditions.ncb;
  final t = p1 * math.sqrt(a * a + b * b) / (u + 0.305);
  final alpha =
      math.pow(t, 0.9) *
      math.pow(
        1.64 - math.pow(0.29, viewingConditions.backgroundYTowhitePointY),
        0.73,
      );
  return (hue: hue, chroma: alpha * math.sqrt(j / 100.0));
}
