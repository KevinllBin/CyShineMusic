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
import 'hct.dart';
import 'tonal_palette.dart';

enum Variant { monochrome, tonalSpot, content }

class DynamicScheme {
  final int sourceColorArgb;
  final Hct sourceColorHct;
  final Variant variant;
  final bool isDark;
  final TonalPalette primaryPalette;
  final TonalPalette secondaryPalette;
  final TonalPalette tertiaryPalette;
  final TonalPalette neutralPalette;
  final TonalPalette neutralVariantPalette;
  final TonalPalette errorPalette;

  DynamicScheme({
    required this.sourceColorHct,
    required this.variant,
    required this.isDark,
    required this.primaryPalette,
    required this.secondaryPalette,
    required this.tertiaryPalette,
    required this.neutralPalette,
    required this.neutralVariantPalette,
  }) : sourceColorArgb = sourceColorHct.toInt(),
       errorPalette = TonalPalette.of(25.0, 84.0);

  DynamicScheme.content({required Hct sourceColorHct, required bool isDark})
    : this(
        sourceColorHct: sourceColorHct,
        variant: Variant.content,
        isDark: isDark,
        primaryPalette: TonalPalette.of(
          sourceColorHct.hue,
          sourceColorHct.chroma,
        ),
        secondaryPalette: TonalPalette.of(
          sourceColorHct.hue,
          math.max(sourceColorHct.chroma - 32.0, sourceColorHct.chroma * 0.5),
        ),
        tertiaryPalette: TonalPalette.fromHct(
          fixIfDisliked(_analogue(sourceColorHct)),
        ),
        neutralPalette: TonalPalette.of(
          sourceColorHct.hue,
          sourceColorHct.chroma / 8.0,
        ),
        neutralVariantPalette: TonalPalette.of(
          sourceColorHct.hue,
          (sourceColorHct.chroma / 8.0) + 4.0,
        ),
      );

  DynamicScheme.tonalSpot({required Hct sourceColorHct, required bool isDark})
    : this(
        sourceColorHct: sourceColorHct,
        variant: Variant.tonalSpot,
        isDark: isDark,
        primaryPalette: TonalPalette.of(sourceColorHct.hue, 36.0),
        secondaryPalette: TonalPalette.of(sourceColorHct.hue, 16.0),
        tertiaryPalette: TonalPalette.of(
          MathUtils.sanitizeDegreesDouble(sourceColorHct.hue + 60.0),
          24.0,
        ),
        neutralPalette: TonalPalette.of(sourceColorHct.hue, 6.0),
        neutralVariantPalette: TonalPalette.of(sourceColorHct.hue, 8.0),
      );

  DynamicScheme.monochrome({required Hct sourceColorHct, required bool isDark})
    : this(
        sourceColorHct: sourceColorHct,
        variant: Variant.monochrome,
        isDark: isDark,
        primaryPalette: TonalPalette.of(sourceColorHct.hue, 0.0),
        secondaryPalette: TonalPalette.of(sourceColorHct.hue, 0.0),
        tertiaryPalette: TonalPalette.of(sourceColorHct.hue, 0.0),
        neutralPalette: TonalPalette.of(sourceColorHct.hue, 0.0),
        neutralVariantPalette: TonalPalette.of(sourceColorHct.hue, 0.0),
      );
}

/// A dark yellow-green that is not neutral reads as spoiled, so it is lightened.
Hct fixIfDisliked(Hct hct) {
  final disliked =
      hct.hue.round() >= 90.0 &&
      hct.hue.round() <= 111.0 &&
      hct.chroma.round() > 16.0 &&
      hct.tone.round() < 65.0;
  return disliked ? Hct.from(hct.hue, hct.chroma, 70.0) : hct;
}

const _analogueDivisions = 6;

/// The first hue a sixth of the way round the wheel from [input], counting by
/// warmth rather than by degrees.
Hct _analogue(Hct input) {
  final hcts = [
    for (var hue = 0.0; hue <= 360.0; hue += 1.0)
      Hct.from(hue, input.chroma, input.tone),
  ];
  final temperatures = hcts.map(_rawTemperature).toList();
  final inputTemperature = _rawTemperature(input);
  final coldest = math.min(temperatures.reduce(math.min), inputTemperature);
  final warmest = math.max(temperatures.reduce(math.max), inputTemperature);
  final range = warmest - coldest;
  double relative(int hue) {
    if (range == 0.0) {
      return 0.5;
    }
    return (temperatures[hue] - coldest) / range;
  }

  final startHue = input.hue.round();
  var lastTemperature = relative(startHue);
  var total = 0.0;
  for (var i = 0; i < 360; i++) {
    final temperature = relative(MathUtils.sanitizeDegreesInt(startHue + i));
    total += (temperature - lastTemperature).abs();
    lastTemperature = temperature;
  }
  final step = total / _analogueDivisions;

  lastTemperature = relative(startHue);
  var travelled = 0.0;
  for (var addend = 1; addend <= 360; addend++) {
    final hue = MathUtils.sanitizeDegreesInt(startHue + addend);
    final temperature = relative(hue);
    travelled += (temperature - lastTemperature).abs();
    if (travelled >= step) {
      return hcts[hue];
    }
    lastTemperature = temperature;
  }
  return hcts[MathUtils.sanitizeDegreesInt(startHue)];
}

double _rawTemperature(Hct color) {
  final lab = ColorUtils.labFromArgb(color.toInt());
  final hue = MathUtils.sanitizeDegreesDouble(
    math.atan2(lab[2], lab[1]) * 180.0 / math.pi,
  );
  final chroma = math.sqrt((lab[1] * lab[1]) + (lab[2] * lab[2]));
  return -0.5 +
      0.02 *
          math.pow(chroma, 1.07) *
          math.cos(
            MathUtils.sanitizeDegreesDouble(hue - 50.0) * math.pi / 180.0,
          );
}
