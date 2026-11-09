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
import 'dynamic_scheme.dart';
import 'hct.dart';
import 'tonal_palette.dart';

class DynamicColor {
  final TonalPalette Function(DynamicScheme) palette;
  final double Function(DynamicScheme) tone;
  final bool isBackground;
  final DynamicColor Function(DynamicScheme)? background;
  final DynamicColor Function(DynamicScheme)? secondBackground;
  final double? contrast;
  final ToneDeltaPair Function(DynamicScheme)? toneDeltaPair;

  final Map<DynamicScheme, Hct> _hctCache = {};

  DynamicColor({
    required this.palette,
    required this.tone,
    this.isBackground = false,
    this.background,
    this.secondBackground,
    this.contrast,
    this.toneDeltaPair,
  });

  int getArgb(DynamicScheme scheme) {
    return getHct(scheme).toInt();
  }

  Hct getHct(DynamicScheme scheme) {
    final cachedAnswer = _hctCache[scheme];
    if (cachedAnswer != null) {
      return cachedAnswer;
    }
    final tone = getTone(scheme);
    final answer = palette(scheme).getHct(tone);
    if (_hctCache.length > 4) {
      _hctCache.clear();
    }
    _hctCache[scheme] = answer;
    return answer;
  }

  double getTone(DynamicScheme scheme) {
    if (toneDeltaPair != null) {
      final pair = toneDeltaPair!(scheme);
      final roleA = pair.roleA;
      final roleB = pair.roleB;
      final delta = pair.delta;
      final polarity = pair.polarity;
      final stayTogether = pair.stayTogether;

      final bg = background!(scheme);
      final bgTone = bg.getTone(scheme);

      final aIsNearer =
          polarity == TonePolarity.nearer ||
          (polarity == TonePolarity.lighter && !scheme.isDark);
      final nearer = aIsNearer ? roleA : roleB;
      final farther = aIsNearer ? roleB : roleA;
      final amNearer = identical(this, nearer);
      final expansionDir = scheme.isDark ? 1 : -1;

      final nContrast = nearer.contrast!;
      final fContrast = farther.contrast!;

      final nInitialTone = nearer.tone(scheme);
      var nTone = Contrast.ratioOfTones(bgTone, nInitialTone) >= nContrast
          ? nInitialTone
          : DynamicColor.foregroundTone(bgTone, nContrast);
      final fInitialTone = farther.tone(scheme);
      var fTone = Contrast.ratioOfTones(bgTone, fInitialTone) >= fContrast
          ? fInitialTone
          : DynamicColor.foregroundTone(bgTone, fContrast);

      if ((fTone - nTone) * expansionDir < delta) {
        fTone = MathUtils.clampDouble(0, 100, nTone + delta * expansionDir);
        if ((fTone - nTone) * expansionDir < delta) {
          nTone = MathUtils.clampDouble(0, 100, fTone - delta * expansionDir);
        }
      }

      if (50 <= nTone && nTone < 60) {
        if (expansionDir > 0) {
          nTone = 60;
          fTone = math.max(fTone, nTone + delta * expansionDir);
        } else {
          nTone = 49;
          fTone = math.min(fTone, nTone + delta * expansionDir);
        }
      } else if (50 <= fTone && fTone < 60) {
        if (stayTogether) {
          if (expansionDir > 0) {
            nTone = 60;
            fTone = math.max(fTone, nTone + delta * expansionDir);
          } else {
            nTone = 49;
            fTone = math.min(fTone, nTone + delta * expansionDir);
          }
        } else {
          if (expansionDir > 0) {
            fTone = 60;
          } else {
            fTone = 49;
          }
        }
      }

      return amNearer ? nTone : fTone;
    } else {
      var answer = tone(scheme);

      if (background == null) {
        return answer; // No adjustment for colors with no background.
      }

      final bgTone = background!(scheme).getTone(scheme);

      final desiredRatio = contrast!;

      if (Contrast.ratioOfTones(bgTone, answer) < desiredRatio) {
        answer = DynamicColor.foregroundTone(bgTone, desiredRatio);
      }

      if (isBackground && 50 <= answer && answer < 60) {
        if (Contrast.ratioOfTones(49, bgTone) >= desiredRatio) {
          answer = 49;
        } else {
          answer = 60;
        }
      }

      if (secondBackground != null) {
        final bgTone1 = background!(scheme).getTone(scheme);
        final bgTone2 = secondBackground!(scheme).getTone(scheme);

        final upper = math.max(bgTone1, bgTone2);
        final lower = math.min(bgTone1, bgTone2);

        if (Contrast.ratioOfTones(upper, answer) >= desiredRatio &&
            Contrast.ratioOfTones(lower, answer) >= desiredRatio) {
          return answer;
        }

        final lightOption = Contrast.lighter(tone: upper, ratio: desiredRatio);

        final darkOption = Contrast.darker(tone: lower, ratio: desiredRatio);

        final availables = <double>[];
        if (lightOption != -1) availables.add(lightOption);
        if (darkOption != -1) availables.add(darkOption);

        final prefersLight =
            DynamicColor.tonePrefersLightForeground(bgTone1) ||
            DynamicColor.tonePrefersLightForeground(bgTone2);
        if (prefersLight) {
          return (lightOption < 0) ? 100 : lightOption;
        }
        if (availables.length == 1) {
          return availables[0];
        }
        return (darkOption < 0) ? 0 : darkOption;
      }

      return answer;
    }
  }

  static double foregroundTone(double bgTone, double ratio) {
    final lighterTone = Contrast.lighterUnsafe(tone: bgTone, ratio: ratio);
    final darkerTone = Contrast.darkerUnsafe(tone: bgTone, ratio: ratio);
    final lighterRatio = Contrast.ratioOfTones(lighterTone, bgTone);
    final darkerRatio = Contrast.ratioOfTones(darkerTone, bgTone);
    final preferLighter = tonePrefersLightForeground(bgTone);

    if (preferLighter) {
      final negligibleDifference =
          (lighterRatio - darkerRatio).abs() < 0.1 &&
          lighterRatio < ratio &&
          darkerRatio < ratio;
      return lighterRatio >= ratio ||
              lighterRatio >= darkerRatio ||
              negligibleDifference
          ? lighterTone
          : darkerTone;
    } else {
      return darkerRatio >= ratio || darkerRatio >= lighterRatio
          ? darkerTone
          : lighterTone;
    }
  }

  static double enableLightForeground(double tone) {
    if (tonePrefersLightForeground(tone) && !toneAllowsLightForeground(tone)) {
      return 49.0;
    }
    return tone;
  }

  static bool tonePrefersLightForeground(double tone) {
    return tone.round() < 60;
  }

  static bool toneAllowsLightForeground(double tone) {
    return tone.round() <= 49;
  }
}

enum TonePolarity { lighter, nearer }

class ToneDeltaPair {
  final DynamicColor roleA;
  final DynamicColor roleB;
  final double delta;
  final TonePolarity polarity;
  final bool stayTogether;

  ToneDeltaPair(
    this.roleA,
    this.roleB,
    this.delta,
    this.polarity,
    this.stayTogether,
  );
}

class Contrast {
  static double ratioOfTones(double toneA, double toneB) {
    toneA = MathUtils.clampDouble(0.0, 100.0, toneA);
    toneB = MathUtils.clampDouble(0.0, 100.0, toneB);
    return _ratioOfYs(
      ColorUtils.yFromLstar(toneA),
      ColorUtils.yFromLstar(toneB),
    );
  }

  static double _ratioOfYs(double y1, double y2) {
    final lighter = y1 > y2 ? y1 : y2;
    final darker = (lighter == y2) ? y1 : y2;
    return (lighter + 5.0) / (darker + 5.0);
  }

  static double lighter({required double tone, required double ratio}) {
    if (tone < 0.0 || tone > 100.0) {
      return -1.0;
    }

    final darkY = ColorUtils.yFromLstar(tone);
    final lightY = ratio * (darkY + 5.0) - 5.0;
    final realContrast = _ratioOfYs(lightY, darkY);
    final delta = (realContrast - ratio).abs();
    if (realContrast < ratio && delta > 0.04) {
      return -1;
    }

    final returnValue = ColorUtils.lstarFromY(lightY) + 0.4;
    if (returnValue < 0 || returnValue > 100) {
      return -1;
    }
    return returnValue;
  }

  static double darker({required double tone, required double ratio}) {
    if (tone < 0.0 || tone > 100.0) {
      return -1.0;
    }

    final lightY = ColorUtils.yFromLstar(tone);
    final darkY = ((lightY + 5.0) / ratio) - 5.0;
    final realContrast = _ratioOfYs(lightY, darkY);

    final delta = (realContrast - ratio).abs();
    if (realContrast < ratio && delta > 0.04) {
      return -1;
    }

    final returnValue = ColorUtils.lstarFromY(darkY) - 0.4;
    if (returnValue < 0 || returnValue > 100) {
      return -1;
    }
    return returnValue;
  }

  static double lighterUnsafe({required double tone, required double ratio}) {
    final lighterSafe = lighter(tone: tone, ratio: ratio);
    return (lighterSafe < 0.0) ? 100.0 : lighterSafe;
  }

  static double darkerUnsafe({required double tone, required double ratio}) {
    final darkerSafe = darker(tone: tone, ratio: ratio);
    return (darkerSafe < 0.0) ? 0.0 : darkerSafe;
  }
}
