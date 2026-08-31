import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'flowing_light_spec.dart';

/// The drawing half of the Salt flowing-light replica.
///
/// Split out of `flowing_light_background.dart` so the widget file stays about
/// state and scheduling while this one stays about pixels. Nothing here touches
/// the element tree, so it can be reasoned about — and its geometry checked
/// against `hi.java` — without a `BuildContext` in sight.

/// Composites one frame and rasterises it.
///
/// The returned image is both what gets painted this frame and what gets passed
/// back as [history] on the next one, so callers must keep it alive until the
/// following frame has been composed. `toImageSync` hands back an immutable
/// image, which is why — unlike Salt, which copies its buffer into a separate
/// history bitmap — no extra copy is needed here.
ui.Image composeFlowingLightFrame({
  required ui.Image artwork,
  required Color baseColor,
  required FlowingLightSpec spec,
  required Duration clock,
  required ui.Image? history,
}) {
  final width = spec.compositionWidth.toDouble();
  final height = spec.compositionHeight.toDouble();
  final bounds = Rect.fromLTWH(0, 0, width, height);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..clipRect(bounds);

  // Everything inside this layer gets blurred together. The base colour goes
  // down first so the layer is opaque before the blur samples it — a
  // transparent margin would bleed in and darken the edges of the screen.
  canvas.saveLayer(
    bounds,
    Paint()
      ..imageFilter = ui.ImageFilter.blur(
        sigmaX: kFlowingLightBlurSigma,
        sigmaY: kFlowingLightBlurSigma,
        tileMode: TileMode.clamp,
      ),
  );
  canvas.drawColor(baseColor, BlendMode.src);

  final artworkPaint = Paint()
    ..isAntiAlias = true
    ..filterQuality = FilterQuality.low
    ..colorFilter = _saturationFilter;

  final side = (math.max(width, height) * kFlowingLightCoverScale)
      .roundToDouble();
  final scale = side / artwork.height;
  final left = -(side - width) / 2;
  final top = -(side - height) / 2;
  final pivot = side / 2;

  // Salt builds these with Android's `post*` calls, which left-multiply — the
  // last `post` is the outermost transform. Canvas ops compose outermost-first,
  // so each block below reads as that matrix expression reversed.
  _drawCopy(canvas, artwork, artworkPaint, () {
    canvas.translate(left, top);
    _rotateAbout(canvas, flowingLightLayer1Angle(clock), pivot, pivot);
    canvas.scale(scale, scale);
  });

  _drawCopy(canvas, artwork, artworkPaint, () {
    canvas.translate(
      left + width * kFlowingLightLayer2OffsetX,
      top + height * kFlowingLightLayer2OffsetY,
    );
    _rotateAbout(canvas, flowingLightLayer2Angle(clock), pivot, pivot);
    canvas.scale(scale, scale);
  });

  // The third copy rotates twice: once about its own centre like the others,
  // then again about the centre of the buffer. That second rotation is what
  // makes it orbit instead of just spinning in place.
  final layer3Angle = flowingLightLayer3Angle(clock);
  _drawCopy(canvas, artwork, artworkPaint, () {
    _rotateAbout(canvas, layer3Angle, width / 2, height / 2);
    canvas.translate(
      left + width * kFlowingLightLayer3OffsetX,
      top + height * kFlowingLightLayer3OffsetY,
    );
    _rotateAbout(canvas, layer3Angle, pivot, pivot);
    canvas.scale(scale, scale);
  });

  for (final scrim in spec.dark ? _darkScrims : _lightScrims) {
    canvas.drawColor(scrim, BlendMode.srcOver);
  }
  canvas.restore();

  // Outside the blur layer on purpose: Salt blurs first and only then blends
  // the previous frame in, so the trail is made of already-blurred output
  // rather than being smeared a second time.
  if (history != null) {
    canvas.drawImage(
      history,
      Offset.zero,
      Paint()
        ..filterQuality = FilterQuality.none
        ..color = const Color.fromARGB(kFlowingLightFeedbackAlpha, 0, 0, 0),
    );
  }

  final picture = recorder.endRecording();
  try {
    return picture.toImageSync(spec.compositionWidth, spec.compositionHeight);
  } finally {
    picture.dispose();
  }
}

/// Paints [image] scaled to fill [size], cropped to the spec's visible window.
///
/// Salt does this with a `BitmapShader` and a scale matrix; `drawImageRect` is
/// the same operation with the arithmetic already folded in. Bilinear filtering
/// matches Salt's `Paint(7)`, and the content is blurred enough that a 20-32x
/// upscale still reads as smooth.
void paintFlowingLightFrame(
  Canvas canvas,
  Size size,
  ui.Image image,
  FlowingLightSpec spec, {
  required double opacity,
}) {
  if (opacity <= 0) return;
  final source = Rect.fromLTRB(
    spec.cropLeft,
    spec.cropTop,
    spec.compositionWidth - spec.cropLeft,
    spec.compositionHeight - spec.cropTop,
  );
  canvas.drawImageRect(
    image,
    source,
    Offset.zero & size,
    Paint()
      ..filterQuality = FilterQuality.low
      ..color = Color.fromARGB((opacity.clamp(0, 1) * 255).round(), 0, 0, 0),
  );
}

/// Average colour of a 5x5 grid of samples, weighted by alpha.
///
/// Only fills the gaps the three rotating copies leave uncovered, so it never
/// needs to be a "dominant colour" in the palette sense. Note the divisor:
/// Salt divides by the sample count rather than by total alpha, so artwork with
/// transparent regions genuinely does average out darker. That is reproduced
/// here rather than corrected.
Future<Color> sampleFlowingLightBaseColor(ui.Image source) async {
  if (source.width <= 0 || source.height <= 0) return const Color(0xFF000000);
  final data = await source.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (data == null) return const Color(0xFF000000);

  final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  var red = 0;
  var green = 0;
  var blue = 0;
  var count = 0;
  for (var row = 0; row < 5; row++) {
    final y = (((row + 0.5) * source.height) / 5).floor().clamp(
      0,
      source.height - 1,
    );
    for (var column = 0; column < 5; column++) {
      final x = (((column + 0.5) * source.width) / 5).floor().clamp(
        0,
        source.width - 1,
      );
      final offset = (y * source.width + x) * 4;
      final alpha = bytes[offset + 3];
      red += bytes[offset] * alpha ~/ 255;
      green += bytes[offset + 1] * alpha ~/ 255;
      blue += bytes[offset + 2] * alpha ~/ 255;
      count++;
    }
  }
  if (count == 0) return const Color(0xFF000000);
  return Color.fromARGB(255, red ~/ count, green ~/ count, blue ~/ count);
}

void _drawCopy(
  Canvas canvas,
  ui.Image artwork,
  Paint paint,
  VoidCallback applyTransform,
) {
  canvas.save();
  applyTransform();
  canvas.drawImage(artwork, Offset.zero, paint);
  canvas.restore();
}

void _rotateAbout(Canvas canvas, double degrees, double x, double y) {
  canvas.translate(x, y);
  canvas.rotate(degrees * math.pi / 180);
  canvas.translate(-x, -y);
}

/// Theme scrims, applied in order after the artwork copies and before the blur.
const List<Color> _lightScrims = [Color(0x95FFFFFF), Color(0x2AFFFFFF)];
const List<Color> _darkScrims = [Color(0x52000000), Color(0x1A000000)];

/// Derived once: the matrix itself never changes, and rebuilding a
/// `ColorFilter` per frame would churn a native handle 24 times a second.
final ColorFilter _saturationFilter = ColorFilter.matrix(
  flowingLightSaturationMatrix(kFlowingLightSaturation),
);
