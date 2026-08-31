/// The arithmetic half of the Salt flowing-light replica.
///
/// Deliberately free of `dart:ui` so `test/unit_test.dart` — the repo's only
/// locally runnable test entry — can pin these constants. Every number here was
/// read back out of Salt 12.1.1's decompiled `hi.java`; a drift of one value is
/// the difference between "looks like Salt" and "looks like something else", so
/// they are asserted rather than trusted.
library;

import 'dart:math' as math;

/// Salt's per-frame cadence: `postInvalidateDelayed(42L)`, i.e. ~23.8fps.
///
/// Not tied to the display refresh rate on purpose. The low rate is what the
/// previous-frame feedback below is compensating for, and running faster makes
/// the trail shorter rather than smoother.
const Duration kFlowingLightFrameInterval = Duration(milliseconds: 42);

/// Cross-fade applied when the artwork changes, matching Salt's
/// `AlphaAnimation(1, 0)` with `PathInterpolator(0, 0, 0.3, 1)`.
const Duration kFlowingLightArtworkFade = Duration(milliseconds: 500);

/// How far the player has to be pulled open before the motion is allowed to
/// run.
///
/// Salt gates on the same 95%: below it the page is still being dragged, which
/// is exactly when the extra raster work is least affordable.
const double kFlowingLightRevealThreshold = 0.95;

/// Alpha Salt draws the previous composed frame back in with.
///
/// `64 / 255 = 0.251`, so each frame is `0.749 * current + 0.251 * previous`.
/// Because the blended result is what gets stored as the next frame's history,
/// this is a recursive low-pass filter over time — the source of the slow
/// "flowing" quality that a plain rotation does not have.
const int kFlowingLightFeedbackAlpha = 64;

/// Saturation Salt pushes the artwork to before compositing.
const double kFlowingLightSaturation = 2.5;

/// The 4x5 colour matrix for [saturation], laid out the way `ColorFilter.matrix`
/// wants it.
///
/// Derived rather than tabulated so the luminance weights stay visible: these
/// are the ones baked into Android's `ColorMatrix.setSaturation`, and a replica
/// that quietly used the sRGB or Rec.709 weights instead would shift every
/// colour the backdrop produces.
List<double> flowingLightSaturationMatrix(double saturation) {
  const luminanceRed = 0.213;
  const luminanceGreen = 0.715;
  const luminanceBlue = 0.072;
  final red = (1 - saturation) * luminanceRed;
  final green = (1 - saturation) * luminanceGreen;
  final blue = (1 - saturation) * luminanceBlue;
  return <double>[
    red + saturation, green, blue, 0, 0, //
    red, green + saturation, blue, 0, 0, //
    red, green, blue + saturation, 0, 0, //
    0, 0, 0, 1, 0, //
  ];
}

/// Blur strength, expressed the way Salt expresses it: a RenderScript /
/// `com.google.android.renderscript.Toolkit` *radius*.
const double kFlowingLightBlurRadius = 25;

/// The same blur as a Gaussian sigma, which is what `ImageFilter.blur` wants.
///
/// AOSP's `rsCpuIntrinsicBlur` derives its kernel with
/// `sigma = 0.4 * radius + 0.6`, and the Toolkit replacement library mirrors it
/// to stay bit-compatible. Passing the radius straight through as a sigma —
/// which is what this file's predecessor did — over-blurs by about 2.4x.
const double kFlowingLightBlurSigma = 0.4 * kFlowingLightBlurRadius + 0.6;

/// Each artwork copy is drawn at `max(bufferW, bufferH) * 1.3` so its corners
/// stay outside the buffer through a full rotation.
const double kFlowingLightCoverScale = 1.3;

/// Fixed offsets of the second and third artwork copies, in buffer units.
const double kFlowingLightLayer2OffsetX = -0.95;
const double kFlowingLightLayer2OffsetY = -0.70;
const double kFlowingLightLayer3OffsetX = -0.50;
const double kFlowingLightLayer3OffsetY = 0.70;

/// Rotation periods of the three copies.
///
/// The signs differ and the periods are mutually non-harmonic, so the three
/// phases only realign every `lcm(100, 70, 40) = 1400` seconds — 23 minutes and
/// 20 seconds. That is why the motion never reads as a loop.
const Duration kFlowingLightLayer1Period = Duration(seconds: 100);
const Duration kFlowingLightLayer2Period = Duration(seconds: 70);
const Duration kFlowingLightLayer3Period = Duration(seconds: 40);

/// Rotation of the first copy, in degrees. Clockwise.
double flowingLightLayer1Angle(Duration clock) =>
    360 * _phase(clock, kFlowingLightLayer1Period);

/// Rotation of the second copy, in degrees. Counter-clockwise.
double flowingLightLayer2Angle(Duration clock) =>
    -360 * _phase(clock, kFlowingLightLayer2Period);

/// Rotation of the third copy, in degrees. Counter-clockwise.
///
/// Applied twice per frame — once about the artwork's own centre and again
/// about the buffer's centre — so this copy orbits as well as spins.
double flowingLightLayer3Angle(Duration clock) =>
    -360 * _phase(clock, kFlowingLightLayer3Period);

double _phase(Duration clock, Duration period) {
  final micros = clock.inMicroseconds % period.inMicroseconds;
  return micros / period.inMicroseconds;
}

/// Resolution and crop geometry for one composition, derived from the viewport.
///
/// Salt composes into a buffer roughly `92x133` on a 1080x2400 phone and then
/// scales that up to fill the screen. The tiny buffer is not only a performance
/// trick: it is why a radius-25 blur reads as enormous soft fields of colour
/// rather than a mildly defocused album cover.
class FlowingLightSpec {
  const FlowingLightSpec({
    required this.compositionWidth,
    required this.compositionHeight,
    required this.visibleWidth,
    required this.visibleHeight,
    required this.dark,
  });

  /// Builds the spec for a viewport measured in physical pixels.
  factory FlowingLightSpec.forViewport({
    required int physicalWidth,
    required int physicalHeight,
    required double devicePixelRatio,
    required bool dark,
  }) {
    final scale = compositionScaleFor(devicePixelRatio);
    final visibleWidth = physicalWidth / scale;
    final visibleHeight = physicalHeight / scale;
    return FlowingLightSpec(
      compositionWidth: math.max(1, (visibleWidth + _kBufferMargin).round()),
      compositionHeight: math.max(1, (visibleHeight + _kBufferMargin).round()),
      visibleWidth: visibleWidth,
      visibleHeight: visibleHeight,
      dark: dark,
    );
  }

  /// Buffer width in pixels, margin included.
  final int compositionWidth;

  /// Buffer height in pixels, margin included.
  final int compositionHeight;

  /// The centred sub-rectangle of the buffer that maps onto the viewport. The
  /// margin around it is drawn but never shown; it exists so the rotating
  /// copies never expose an edge.
  final double visibleWidth;
  final double visibleHeight;

  final bool dark;

  /// Left inset of the visible crop within the composition.
  double get cropLeft => math.max(0, (compositionWidth - visibleWidth) / 2);

  /// Top inset of the visible crop within the composition.
  double get cropTop => math.max(0, (compositionHeight - visibleHeight) / 2);

  @override
  bool operator ==(Object other) {
    return other is FlowingLightSpec &&
        compositionWidth == other.compositionWidth &&
        compositionHeight == other.compositionHeight &&
        visibleWidth == other.visibleWidth &&
        visibleHeight == other.visibleHeight &&
        dark == other.dark;
  }

  @override
  int get hashCode => Object.hash(
    compositionWidth,
    compositionHeight,
    visibleWidth,
    visibleHeight,
    dark,
  );
}

/// Divisor applied to the viewport to get the composition size.
///
/// Salt switches on `densityDpi`, which Flutter exposes only as a device pixel
/// ratio; `densityDpi = devicePixelRatio * 160` recovers it.
int compositionScaleFor(double devicePixelRatio) =>
    devicePixelRatio * 160 >= 420 ? 32 : 20;

/// Extra pixels added to each axis of the composition buffer.
const double _kBufferMargin = 58;
