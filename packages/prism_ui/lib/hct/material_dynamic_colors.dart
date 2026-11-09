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

import 'dynamic_color.dart';
import 'dynamic_scheme.dart';
import 'hct.dart';

bool _isContent(DynamicScheme scheme) => scheme.variant == Variant.content;

bool _isMonochrome(DynamicScheme scheme) =>
    scheme.variant == Variant.monochrome;

class MaterialDynamicColors {
  static DynamicColor highestSurface(DynamicScheme s) {
    return s.isDark ? surfaceBright : surfaceDim;
  }

  static final DynamicColor surface = DynamicColor(
    palette: (s) => s.neutralPalette,
    tone: (s) => s.isDark ? 6 : 98,
    isBackground: true,
  );

  static final DynamicColor surfaceDim = DynamicColor(
    palette: (s) => s.neutralPalette,
    tone: (s) => s.isDark ? 6 : 87,
    isBackground: true,
  );

  static final DynamicColor surfaceBright = DynamicColor(
    palette: (s) => s.neutralPalette,
    tone: (s) => s.isDark ? 24 : 98,
    isBackground: true,
  );

  static final DynamicColor surfaceContainerLowest = DynamicColor(
    palette: (s) => s.neutralPalette,
    tone: (s) => s.isDark ? 4 : 100,
    isBackground: true,
  );

  static final DynamicColor surfaceContainerLow = DynamicColor(
    palette: (s) => s.neutralPalette,
    tone: (s) => s.isDark ? 10 : 96,
    isBackground: true,
  );

  static final DynamicColor surfaceContainer = DynamicColor(
    palette: (s) => s.neutralPalette,
    tone: (s) => s.isDark ? 12 : 94,
    isBackground: true,
  );

  static final DynamicColor surfaceContainerHigh = DynamicColor(
    palette: (s) => s.neutralPalette,
    tone: (s) => s.isDark ? 17 : 92,
    isBackground: true,
  );

  static final DynamicColor surfaceContainerHighest = DynamicColor(
    palette: (s) => s.neutralPalette,
    tone: (s) => s.isDark ? 22 : 90,
    isBackground: true,
  );

  static final DynamicColor onSurface = DynamicColor(
    palette: (s) => s.neutralPalette,
    tone: (s) => s.isDark ? 90 : 10,
    background: MaterialDynamicColors.highestSurface,
    contrast: 7,
  );

  static final DynamicColor onSurfaceVariant = DynamicColor(
    palette: (s) => s.neutralVariantPalette,
    tone: (s) => s.isDark ? 80 : 30,
    background: MaterialDynamicColors.highestSurface,
    contrast: 4.5,
  );

  static final DynamicColor inverseSurface = DynamicColor(
    palette: (s) => s.neutralPalette,
    tone: (s) => s.isDark ? 90 : 20,
  );

  static final DynamicColor inverseOnSurface = DynamicColor(
    palette: (s) => s.neutralPalette,
    tone: (s) => s.isDark ? 20 : 95,
    background: (s) => MaterialDynamicColors.inverseSurface,
    contrast: 7,
  );

  static final DynamicColor outline = DynamicColor(
    palette: (s) => s.neutralVariantPalette,
    tone: (s) => s.isDark ? 60 : 50,
    background: MaterialDynamicColors.highestSurface,
    contrast: 3,
  );

  static final DynamicColor outlineVariant = DynamicColor(
    palette: (s) => s.neutralVariantPalette,
    tone: (s) => s.isDark ? 30 : 80,
    background: MaterialDynamicColors.highestSurface,
    contrast: 1,
  );

  static final DynamicColor shadow = DynamicColor(
    palette: (s) => s.neutralPalette,
    tone: (s) => 0,
  );

  static final DynamicColor scrim = DynamicColor(
    palette: (s) => s.neutralPalette,
    tone: (s) => 0,
  );

  static final DynamicColor primary = DynamicColor(
    palette: (s) => s.primaryPalette,
    tone: (s) {
      if (_isMonochrome(s)) {
        return s.isDark ? 100 : 0;
      }
      return s.isDark ? 80 : 40;
    },
    isBackground: true,
    background: MaterialDynamicColors.highestSurface,
    contrast: 4.5,
    toneDeltaPair: (s) => ToneDeltaPair(
      MaterialDynamicColors.primaryContainer,
      MaterialDynamicColors.primary,
      10,
      TonePolarity.nearer,
      false,
    ),
  );

  static final DynamicColor onPrimary = DynamicColor(
    palette: (s) => s.primaryPalette,
    tone: (s) {
      if (_isMonochrome(s)) {
        return s.isDark ? 10 : 90;
      }
      return s.isDark ? 20 : 100;
    },
    background: (s) => MaterialDynamicColors.primary,
    contrast: 7,
  );

  static final DynamicColor primaryContainer = DynamicColor(
    palette: (s) => s.primaryPalette,
    tone: (s) {
      if (_isContent(s)) {
        return s.sourceColorHct.tone;
      }
      if (_isMonochrome(s)) {
        return s.isDark ? 85 : 25;
      }
      return s.isDark ? 30 : 90;
    },
    isBackground: true,
    background: MaterialDynamicColors.highestSurface,
    contrast: 1,
    toneDeltaPair: (s) => ToneDeltaPair(
      MaterialDynamicColors.primaryContainer,
      MaterialDynamicColors.primary,
      10,
      TonePolarity.nearer,
      false,
    ),
  );

  static final DynamicColor onPrimaryContainer = DynamicColor(
    palette: (s) => s.primaryPalette,
    tone: (s) {
      if (_isContent(s)) {
        return DynamicColor.foregroundTone(
          MaterialDynamicColors.primaryContainer.tone(s),
          4.5,
        );
      }
      if (_isMonochrome(s)) {
        return s.isDark ? 0 : 100;
      }
      return s.isDark ? 90 : 30;
    },
    background: (s) => MaterialDynamicColors.primaryContainer,
    contrast: 4.5,
  );

  static final DynamicColor inversePrimary = DynamicColor(
    palette: (s) => s.primaryPalette,
    tone: (s) => s.isDark ? 40 : 80,
    background: (s) => MaterialDynamicColors.inverseSurface,
    contrast: 4.5,
  );

  static final DynamicColor secondary = DynamicColor(
    palette: (s) => s.secondaryPalette,
    tone: (s) => s.isDark ? 80 : 40,
    isBackground: true,
    background: MaterialDynamicColors.highestSurface,
    contrast: 4.5,
    toneDeltaPair: (s) => ToneDeltaPair(
      MaterialDynamicColors.secondaryContainer,
      MaterialDynamicColors.secondary,
      10,
      TonePolarity.nearer,
      false,
    ),
  );

  static final DynamicColor onSecondary = DynamicColor(
    palette: (s) => s.secondaryPalette,
    tone: (s) {
      if (_isMonochrome(s)) {
        return s.isDark ? 10 : 100;
      } else {
        return s.isDark ? 20 : 100;
      }
    },
    background: (s) => MaterialDynamicColors.secondary,
    contrast: 7,
  );

  static final DynamicColor secondaryContainer = DynamicColor(
    palette: (s) => s.secondaryPalette,
    tone: (s) {
      final initialTone = s.isDark ? 30.0 : 90.0;
      if (_isMonochrome(s)) {
        return s.isDark ? 30 : 85;
      }
      if (!_isContent(s)) {
        return initialTone;
      }
      return _findDesiredChromaByTone(
        s.secondaryPalette.hue,
        s.secondaryPalette.chroma,
        initialTone,
        s.isDark ? false : true,
      );
    },
    isBackground: true,
    background: MaterialDynamicColors.highestSurface,
    contrast: 1,
    toneDeltaPair: (s) => ToneDeltaPair(
      MaterialDynamicColors.secondaryContainer,
      MaterialDynamicColors.secondary,
      10,
      TonePolarity.nearer,
      false,
    ),
  );

  static final DynamicColor onSecondaryContainer = DynamicColor(
    palette: (s) => s.secondaryPalette,
    tone: (s) {
      if (_isMonochrome(s)) {
        return s.isDark ? 90 : 10;
      }
      if (!_isContent(s)) {
        return s.isDark ? 90 : 30;
      }
      return DynamicColor.foregroundTone(
        MaterialDynamicColors.secondaryContainer.tone(s),
        4.5,
      );
    },
    background: (s) => MaterialDynamicColors.secondaryContainer,
    contrast: 4.5,
  );

  static final DynamicColor tertiary = DynamicColor(
    palette: (s) => s.tertiaryPalette,
    tone: (s) {
      if (_isMonochrome(s)) {
        return s.isDark ? 90 : 25;
      }
      return s.isDark ? 80 : 40;
    },
    isBackground: true,
    background: MaterialDynamicColors.highestSurface,
    contrast: 4.5,
    toneDeltaPair: (s) => ToneDeltaPair(
      MaterialDynamicColors.tertiaryContainer,
      MaterialDynamicColors.tertiary,
      10,
      TonePolarity.nearer,
      false,
    ),
  );

  static final DynamicColor onTertiary = DynamicColor(
    palette: (s) => s.tertiaryPalette,
    tone: (s) {
      if (_isMonochrome(s)) {
        return s.isDark ? 10 : 90;
      }
      return s.isDark ? 20 : 100;
    },
    background: (s) => MaterialDynamicColors.tertiary,
    contrast: 7,
  );

  static final DynamicColor tertiaryContainer = DynamicColor(
    palette: (s) => s.tertiaryPalette,
    tone: (s) {
      if (_isMonochrome(s)) {
        return s.isDark ? 60 : 49;
      }
      if (!_isContent(s)) {
        return s.isDark ? 30 : 90;
      }
      final proposedHct = s.tertiaryPalette.getHct(s.sourceColorHct.tone);
      return fixIfDisliked(proposedHct).tone;
    },
    isBackground: true,
    background: MaterialDynamicColors.highestSurface,
    contrast: 1,
    toneDeltaPair: (s) => ToneDeltaPair(
      MaterialDynamicColors.tertiaryContainer,
      MaterialDynamicColors.tertiary,
      10,
      TonePolarity.nearer,
      false,
    ),
  );

  static final DynamicColor onTertiaryContainer = DynamicColor(
    palette: (s) => s.tertiaryPalette,
    tone: (s) {
      if (_isMonochrome(s)) {
        return s.isDark ? 0 : 100;
      }
      if (!_isContent(s)) {
        return s.isDark ? 90 : 30;
      }
      return DynamicColor.foregroundTone(
        MaterialDynamicColors.tertiaryContainer.tone(s),
        4.5,
      );
    },
    background: (s) => MaterialDynamicColors.tertiaryContainer,
    contrast: 4.5,
  );

  static final DynamicColor error = DynamicColor(
    palette: (s) => s.errorPalette,
    tone: (s) => s.isDark ? 80 : 40,
    isBackground: true,
    background: MaterialDynamicColors.highestSurface,
    contrast: 4.5,
    toneDeltaPair: (s) => ToneDeltaPair(
      MaterialDynamicColors.errorContainer,
      MaterialDynamicColors.error,
      10,
      TonePolarity.nearer,
      false,
    ),
  );

  static final DynamicColor onError = DynamicColor(
    palette: (s) => s.errorPalette,
    tone: (s) => s.isDark ? 20 : 100,
    background: (s) => MaterialDynamicColors.error,
    contrast: 7,
  );

  static final DynamicColor errorContainer = DynamicColor(
    palette: (s) => s.errorPalette,
    tone: (s) => s.isDark ? 30 : 90,
    isBackground: true,
    background: MaterialDynamicColors.highestSurface,
    contrast: 1,
    toneDeltaPair: (s) => ToneDeltaPair(
      MaterialDynamicColors.errorContainer,
      MaterialDynamicColors.error,
      10,
      TonePolarity.nearer,
      false,
    ),
  );

  static final DynamicColor onErrorContainer = DynamicColor(
    palette: (s) => s.errorPalette,
    tone: (s) {
      if (_isMonochrome(s)) {
        return s.isDark ? 90 : 10;
      }
      return s.isDark ? 90 : 30;
    },
    background: (s) => MaterialDynamicColors.errorContainer,
    contrast: 4.5,
  );

  static final DynamicColor primaryFixed = DynamicColor(
    palette: (s) => s.primaryPalette,
    tone: (s) => _isMonochrome(s) ? 40.0 : 90.0,
    isBackground: true,
    background: MaterialDynamicColors.highestSurface,
    contrast: 1,
    toneDeltaPair: (s) => ToneDeltaPair(
      MaterialDynamicColors.primaryFixed,
      MaterialDynamicColors.primaryFixedDim,
      10,
      TonePolarity.lighter,
      true,
    ),
  );

  static final DynamicColor primaryFixedDim = DynamicColor(
    palette: (s) => s.primaryPalette,
    tone: (s) => _isMonochrome(s) ? 30.0 : 80.0,
    isBackground: true,
    background: MaterialDynamicColors.highestSurface,
    contrast: 1,
    toneDeltaPair: (s) => ToneDeltaPair(
      MaterialDynamicColors.primaryFixed,
      MaterialDynamicColors.primaryFixedDim,
      10,
      TonePolarity.lighter,
      true,
    ),
  );

  static final DynamicColor onPrimaryFixed = DynamicColor(
    palette: (s) => s.primaryPalette,
    tone: (s) => _isMonochrome(s) ? 100.0 : 10.0,
    background: (s) => MaterialDynamicColors.primaryFixedDim,
    secondBackground: (s) => MaterialDynamicColors.primaryFixed,
    contrast: 7,
  );

  static final DynamicColor onPrimaryFixedVariant = DynamicColor(
    palette: (s) => s.primaryPalette,
    tone: (s) => _isMonochrome(s) ? 90.0 : 30.0,
    background: (s) => MaterialDynamicColors.primaryFixedDim,
    secondBackground: (s) => MaterialDynamicColors.primaryFixed,
    contrast: 4.5,
  );

  static final DynamicColor secondaryFixed = DynamicColor(
    palette: (s) => s.secondaryPalette,
    tone: (s) => _isMonochrome(s) ? 80.0 : 90.0,
    isBackground: true,
    background: MaterialDynamicColors.highestSurface,
    contrast: 1,
    toneDeltaPair: (s) => ToneDeltaPair(
      MaterialDynamicColors.secondaryFixed,
      MaterialDynamicColors.secondaryFixedDim,
      10,
      TonePolarity.lighter,
      true,
    ),
  );

  static final DynamicColor secondaryFixedDim = DynamicColor(
    palette: (s) => s.secondaryPalette,
    tone: (s) => _isMonochrome(s) ? 70.0 : 80.0,
    isBackground: true,
    background: MaterialDynamicColors.highestSurface,
    contrast: 1,
    toneDeltaPair: (s) => ToneDeltaPair(
      MaterialDynamicColors.secondaryFixed,
      MaterialDynamicColors.secondaryFixedDim,
      10,
      TonePolarity.lighter,
      true,
    ),
  );

  static final DynamicColor onSecondaryFixed = DynamicColor(
    palette: (s) => s.secondaryPalette,
    tone: (s) => 10.0,
    background: (s) => MaterialDynamicColors.secondaryFixedDim,
    secondBackground: (s) => MaterialDynamicColors.secondaryFixed,
    contrast: 7,
  );

  static final DynamicColor onSecondaryFixedVariant = DynamicColor(
    palette: (s) => s.secondaryPalette,
    tone: (s) => _isMonochrome(s) ? 25.0 : 30.0,
    background: (s) => MaterialDynamicColors.secondaryFixedDim,
    secondBackground: (s) => MaterialDynamicColors.secondaryFixed,
    contrast: 4.5,
  );

  static final DynamicColor tertiaryFixed = DynamicColor(
    palette: (s) => s.tertiaryPalette,
    tone: (s) => _isMonochrome(s) ? 40.0 : 90.0,
    isBackground: true,
    background: MaterialDynamicColors.highestSurface,
    contrast: 1,
    toneDeltaPair: (s) => ToneDeltaPair(
      MaterialDynamicColors.tertiaryFixed,
      MaterialDynamicColors.tertiaryFixedDim,
      10,
      TonePolarity.lighter,
      true,
    ),
  );

  static final DynamicColor tertiaryFixedDim = DynamicColor(
    palette: (s) => s.tertiaryPalette,
    tone: (s) => _isMonochrome(s) ? 30.0 : 80.0,
    isBackground: true,
    background: MaterialDynamicColors.highestSurface,
    contrast: 1,
    toneDeltaPair: (s) => ToneDeltaPair(
      MaterialDynamicColors.tertiaryFixed,
      MaterialDynamicColors.tertiaryFixedDim,
      10,
      TonePolarity.lighter,
      true,
    ),
  );

  static final DynamicColor onTertiaryFixed = DynamicColor(
    palette: (s) => s.tertiaryPalette,
    tone: (s) => _isMonochrome(s) ? 100.0 : 10.0,
    background: (s) => MaterialDynamicColors.tertiaryFixedDim,
    secondBackground: (s) => MaterialDynamicColors.tertiaryFixed,
    contrast: 7,
  );

  static final DynamicColor onTertiaryFixedVariant = DynamicColor(
    palette: (s) => s.tertiaryPalette,
    tone: (s) => _isMonochrome(s) ? 90.0 : 30.0,
    background: (s) => MaterialDynamicColors.tertiaryFixedDim,
    secondBackground: (s) => MaterialDynamicColors.tertiaryFixed,
    contrast: 4.5,
  );

  static double _findDesiredChromaByTone(
    double hue,
    double chroma,
    double tone,
    bool byDecreasingTone,
  ) {
    var answer = tone;

    var closestToChroma = Hct.from(hue, chroma, tone);
    if (closestToChroma.chroma < chroma) {
      var chromaPeak = closestToChroma.chroma;
      while (closestToChroma.chroma < chroma) {
        answer += byDecreasingTone ? -1.0 : 1.0;
        final potentialSolution = Hct.from(hue, chroma, answer);
        if (chromaPeak > potentialSolution.chroma) {
          break;
        }
        if ((potentialSolution.chroma - chroma).abs() < 0.4) {
          break;
        }

        final potentialDelta = (potentialSolution.chroma - chroma).abs();
        final currentDelta = (closestToChroma.chroma - chroma).abs();
        if (potentialDelta < currentDelta) {
          closestToChroma = potentialSolution;
        }
        chromaPeak = math.max(chromaPeak, potentialSolution.chroma);
      }
    }

    return answer;
  }
}
