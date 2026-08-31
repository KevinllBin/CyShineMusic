import 'dart:math' as math;
import 'dart:typed_data';

/// A small set of visually distinct colors pulled out of one artwork, used to
/// drive the player's flowing-light layer.
///
/// Colors are plain ARGB ints rather than `Color` on purpose: this file sits
/// inside the pure Dart test boundary (`test/unit_test.dart` imports it), and
/// `dart:ui` is unavailable there. The widget layer converts to `Color`.
class FlowPalette {
  const FlowPalette({required this.baseArgb, required this.accentsArgb});

  /// Alpha-weighted mean of the whole artwork. Mirrors what the existing
  /// static backdrop uses to tint its base, and doubles as the brightness
  /// signal for picking a flow intensity.
  final int baseArgb;

  /// Exactly [accentCount] entries, ordered most to least prominent.
  final List<int> accentsArgb;

  /// The shader declares one uniform per accent (Impeller's shader compiler
  /// rejects uniform arrays), so this count is baked into the GLSL too.
  static const int accentCount = 4;

  static const FlowPalette fallback = FlowPalette(
    baseArgb: 0xFF3A3A3C,
    accentsArgb: [0xFF5B6B8C, 0xFF8C5B72, 0xFF5B8C6B, 0xFF8C7F5B],
  );

  /// Perceived lightness of [baseArgb] in 0..1, used to scale flow opacity —
  /// dark artwork can carry a stronger glow before lyrics lose contrast.
  double get baseLightness {
    final r = (baseArgb >> 16) & 0xFF;
    final g = (baseArgb >> 8) & 0xFF;
    final b = baseArgb & 0xFF;
    return (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255;
  }

  @override
  bool operator ==(Object other) {
    if (other is! FlowPalette) return false;
    if (other.baseArgb != baseArgb) return false;
    if (other.accentsArgb.length != accentsArgb.length) return false;
    for (var i = 0; i < accentsArgb.length; i++) {
      if (other.accentsArgb[i] != accentsArgb[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(baseArgb, Object.hashAll(accentsArgb));
}

/// Extracts [FlowPalette.accentCount] flow colors from raw RGBA pixels.
///
/// [rgba] must be tightly packed, 4 bytes per pixel, row-major — the format
/// `ui.Image.toByteData(format: rawRgba)` returns. Artwork is expected to be
/// already downscaled (the player decodes covers at 192x192), so this walks a
/// bounded sample grid rather than every pixel.
///
/// Returns [FlowPalette.fallback] when the buffer is empty or fully
/// transparent, so callers never have to null-check.
FlowPalette extractFlowPalette(Uint8List rgba, int width, int height) {
  if (width <= 0 || height <= 0 || rgba.length < width * height * 4) {
    return FlowPalette.fallback;
  }

  const grid = 4;
  final blocks = <_Hsl>[];
  var totalRed = 0.0;
  var totalGreen = 0.0;
  var totalBlue = 0.0;
  var totalWeight = 0.0;

  for (var blockY = 0; blockY < grid; blockY++) {
    for (var blockX = 0; blockX < grid; blockX++) {
      final startX = blockX * width ~/ grid;
      final endX = math.max(startX + 1, (blockX + 1) * width ~/ grid);
      final startY = blockY * height ~/ grid;
      final endY = math.max(startY + 1, (blockY + 1) * height ~/ grid);
      final stepX = math.max(1, (endX - startX) ~/ 6);
      final stepY = math.max(1, (endY - startY) ~/ 6);

      var red = 0.0;
      var green = 0.0;
      var blue = 0.0;
      var weight = 0.0;
      for (var y = startY; y < endY && y < height; y += stepY) {
        for (var x = startX; x < endX && x < width; x += stepX) {
          final offset = (y * width + x) * 4;
          final alpha = rgba[offset + 3] / 255;
          if (alpha <= 0) continue;
          red += rgba[offset] * alpha;
          green += rgba[offset + 1] * alpha;
          blue += rgba[offset + 2] * alpha;
          weight += alpha;
        }
      }
      if (weight <= 0) continue;
      totalRed += red;
      totalGreen += green;
      totalBlue += blue;
      totalWeight += weight;
      blocks.add(_rgbToHsl(red / weight, green / weight, blue / weight));
    }
  }

  if (totalWeight <= 0 || blocks.isEmpty) return FlowPalette.fallback;

  final baseArgb = _packRgb(
    totalRed / totalWeight,
    totalGreen / totalWeight,
    totalBlue / totalWeight,
  );

  // Prefer saturated, mid-lightness blocks: near-white and near-black regions
  // carry a hue but no usable color once blended over the backdrop.
  final ranked = List<_Hsl>.of(blocks)
    ..sort((a, b) => _flowScore(b).compareTo(_flowScore(a)));

  final picked = <_Hsl>[];
  for (final candidate in ranked) {
    if (picked.length >= FlowPalette.accentCount) break;
    final duplicate = picked.any(
      (existing) =>
          _hueDistance(existing.h, candidate.h) < 25 &&
          (existing.l - candidate.l).abs() < 0.14,
    );
    if (duplicate) continue;
    picked.add(candidate);
  }

  // Monochrome artwork yields too few distinct blocks. Spin extra accents off
  // the ones we did find so the layer always has four bodies to move.
  if (picked.isEmpty) picked.add(ranked.first);
  final seeds = List<_Hsl>.of(picked);
  var spin = 0;
  while (picked.length < FlowPalette.accentCount) {
    final seed = seeds[spin % seeds.length];
    final turn = 30.0 * (spin ~/ seeds.length + 1);
    final signed = spin.isEven ? turn : -turn;
    picked.add(
      _Hsl(
        (seed.h + signed) % 360,
        seed.s,
        (seed.l + (spin.isEven ? 0.05 : -0.05)).clamp(0.0, 1.0),
      ),
    );
    spin++;
  }

  return FlowPalette(
    baseArgb: baseArgb,
    accentsArgb: List<int>.unmodifiable(
      picked.map((hsl) => _hslToArgb(_normalizeForFlow(hsl))),
    ),
  );
}

/// Lifts washed-out or clipped colors into a range that stays visible when
/// composited at low opacity over the blurred artwork.
_Hsl _normalizeForFlow(_Hsl hsl) {
  final saturation = hsl.s < 0.18
      ? 0.18 + hsl.s * 0.9
      : math.min(1.0, hsl.s * 1.15);
  return _Hsl(hsl.h, saturation.clamp(0.0, 1.0), hsl.l.clamp(0.32, 0.68));
}

double _flowScore(_Hsl hsl) =>
    hsl.s * (1 - (hsl.l - 0.5).abs() * 1.1) + hsl.s * 0.12;

double _hueDistance(double a, double b) {
  final delta = (a - b).abs() % 360;
  return delta > 180 ? 360 - delta : delta;
}

class _Hsl {
  const _Hsl(this.h, this.s, this.l);

  final double h;
  final double s;
  final double l;
}

_Hsl _rgbToHsl(double red, double green, double blue) {
  final r = red / 255;
  final g = green / 255;
  final b = blue / 255;
  final max = math.max(r, math.max(g, b));
  final min = math.min(r, math.min(g, b));
  final lightness = (max + min) / 2;
  final delta = max - min;
  if (delta <= 0) return _Hsl(0, 0, lightness);

  final saturation = lightness > 0.5
      ? delta / (2 - max - min)
      : delta / (max + min);
  final double hue;
  if (max == r) {
    hue = (g - b) / delta + (g < b ? 6 : 0);
  } else if (max == g) {
    hue = (b - r) / delta + 2;
  } else {
    hue = (r - g) / delta + 4;
  }
  return _Hsl(hue * 60, saturation, lightness);
}

int _hslToArgb(_Hsl hsl) {
  if (hsl.s <= 0) {
    final value = hsl.l * 255;
    return _packRgb(value, value, value);
  }
  final hue = (hsl.h % 360) / 360;
  final q = hsl.l < 0.5
      ? hsl.l * (1 + hsl.s)
      : hsl.l + hsl.s - hsl.l * hsl.s;
  final p = 2 * hsl.l - q;
  return _packRgb(
    _hueToChannel(p, q, hue + 1 / 3) * 255,
    _hueToChannel(p, q, hue) * 255,
    _hueToChannel(p, q, hue - 1 / 3) * 255,
  );
}

double _hueToChannel(double p, double q, double t) {
  var offset = t % 1;
  if (offset < 0) offset += 1;
  if (offset < 1 / 6) return p + (q - p) * 6 * offset;
  if (offset < 1 / 2) return q;
  if (offset < 2 / 3) return p + (q - p) * (2 / 3 - offset) * 6;
  return p;
}

int _packRgb(double red, double green, double blue) =>
    0xFF000000 |
    (red.round().clamp(0, 255) << 16) |
    (green.round().clamp(0, 255) << 8) |
    blue.round().clamp(0, 255);
