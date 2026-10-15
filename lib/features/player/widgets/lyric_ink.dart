import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Derives dark lyric ink for a light cover; dark covers keep the fallback ink.
Color? extractLyricInk(Uint8List rgba) {
  final buckets = <int, _Bucket>{};
  for (var i = 0; i + 3 < rgba.length; i += 4) {
    if (rgba[i + 3] < 125) continue;
    final r = rgba[i];
    final g = rgba[i + 1];
    final b = rgba[i + 2];
    final key = ((r >> 4) << 8) | ((g >> 4) << 4) | (b >> 4);
    final bucket = buckets.putIfAbsent(key, _Bucket.new);
    bucket.count++;
    bucket.r += r;
    bucket.g += g;
    bucket.b += b;
  }
  if (buckets.isEmpty) return null;
  final swatches = buckets.values.map((bucket) => bucket.swatch).toList();
  final maxCount = swatches.map((swatch) => swatch.count).reduce(math.max);
  final base = swatches.reduce((a, b) => a.count >= b.count ? a : b);
  var background = base;
  final useful = swatches.where((swatch) => !swatch.extreme).toList();
  if (background.extreme) {
    final alternatives = useful.where(
      (swatch) => swatch.count >= maxCount / 2.5,
    );
    for (final swatch in alternatives) {
      if (background.extreme ||
          swatch.hsl.saturation > background.hsl.saturation) {
        background = swatch;
      }
    }
  }
  final luminance = background.color.computeLuminance();
  if (luminance <= 0.5) return null;
  final prominent = useful.isEmpty
      ? base
      : useful.reduce((a, b) => a.count >= b.count ? a : b);

  _Swatch? pick(bool dark, bool vibrant) {
    _Swatch? result;
    var best = -1.0;
    final targetL = dark ? 0.26 : 0.5;
    final targetS = vibrant ? 1.0 : 0.3;
    for (final swatch in swatches) {
      final hsl = swatch.hsl;
      if (dark
          ? hsl.lightness > 0.45
          : hsl.lightness < 0.3 || hsl.lightness > 0.7) {
        continue;
      }
      if (vibrant ? hsl.saturation < 0.35 : hsl.saturation > 0.4) continue;
      final score =
          0.24 * swatch.count / maxCount +
          0.52 * (1 - (hsl.lightness - targetL).abs()) +
          0.24 * (1 - (hsl.saturation - targetS).abs());
      if (score > best) {
        best = score;
        result = swatch;
      }
    }
    return result;
  }

  _Swatch? morePopulated(_Swatch? a, _Swatch? b) => a == null
      ? b
      : b == null || a.count >= b.count
      ? a
      : b;
  var selected =
      morePopulated(pick(true, true), pick(false, true)) ??
      morePopulated(pick(true, false), pick(false, false));
  if (selected == null) {
    final total = swatches.fold(0, (sum, swatch) => sum + swatch.count);
    selected = prominent.count / total >= 0.01
        ? prominent
        : _Swatch(Colors.black, 0);
  } else if (selected.count / prominent.count < 0.01 &&
      prominent.hsl.saturation > 0.19) {
    selected = prominent;
  }
  final chosen = selected.hsl;
  final dominant = background.hsl;
  final main = prominent.hsl;
  final hue = chosen.saturation >= 0.18
      ? chosen.hue
      : main.saturation >= 0.15
      ? main.hue
      : dominant.saturation >= 0.1
      ? dominant.hue
      : 225.0;
  final saturation =
      (chosen.saturation >= 0.3
              ? chosen.saturation
              : main.saturation >= 0.3
              ? main.saturation * 0.85
              : dominant.saturation >= 0.15
              ? dominant.saturation * 0.75
              : 0.3)
          .clamp(0.3, 0.6);
  for (var step = 0; step <= 12; step++) {
    final ink = HSLColor.fromAHSL(
      1,
      hue,
      saturation,
      0.3 - step * 0.015,
    ).toColor();
    final inkLuminance = ink.computeLuminance();
    final contrast =
        (math.max(luminance, inkLuminance) + 0.05) /
        (math.min(luminance, inkLuminance) + 0.05);
    if (contrast >= 4.5 || step == 12) return ink;
  }
  return null;
}

class _Bucket {
  int count = 0;
  int r = 0;
  int g = 0;
  int b = 0;

  _Swatch get swatch => _Swatch(
    Color.fromARGB(
      255,
      (r / count).round(),
      (g / count).round(),
      (b / count).round(),
    ),
    count,
  );
}

class _Swatch {
  _Swatch(this.color, this.count) : hsl = HSLColor.fromColor(color);
  final Color color;
  final int count;
  final HSLColor hsl;
  bool get extreme => hsl.lightness < 0.08 || hsl.lightness > 0.9;
}
