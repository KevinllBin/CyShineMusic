library;

import 'dart:math' as math;

const Duration kFlowingLightFrameInterval = Duration(milliseconds: 42);

const Duration kFlowingLightArtworkFade = Duration(milliseconds: 500);

const double kFlowingLightRevealThreshold = 0.95;

const int kFlowingLightFeedbackAlpha = 64;

const double kFlowingLightSaturation = 2.5;

/// The 4x5 colour matrix for [saturation], laid out the way `ColorFilter.matrix`
/// wants it.
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

int compositionScaleFor(double devicePixelRatio) =>
    devicePixelRatio * 160 >= 420 ? 32 : 20;

/// Extra pixels added to each axis of the composition buffer.
const double _kBufferMargin = 58;
