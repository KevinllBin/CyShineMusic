import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../flow_palette.dart';

/// Radius of each color body, in short-side units, passed through the shader's
/// `w` component. Ordered to match [FlowPalette.accentsArgb].
///
/// Kept well under 1.0 on purpose: bodies wide enough to cover the whole
/// viewport make every pixel a blend of all four, which averages out to a
/// single flat color no matter how they move. The gaps between them are what
/// the motion is actually visible against.
const List<double> _kBodyRadii = [0.44, 0.38, 0.50, 0.41];

/// One full loop of the drift composition. All temporal frequencies in the
/// shader are integers, so the wrap at the end of this period is seamless.
///
/// The fastest orbit component completes in a third of this, which puts
/// perceptible movement inside the few seconds someone actually looks at the
/// page.
const Duration _kFlowPeriod = Duration(seconds: 30);

const Duration _kFadeInDuration = Duration(milliseconds: 420);

/// Process-wide cache of the compiled runtime effect.
///
/// `FragmentProgram.fromAsset` re-parses the shader on every call, and the
/// player layer is rebuilt on every track change, so the program is held for
/// the life of the process. This is the only copy in the repo — grep before
/// adding another.
ui.FragmentProgram? _flowingLightProgram;
Future<ui.FragmentProgram>? _flowingLightProgramLoad;

Future<ui.FragmentProgram> _obtainFlowingLightProgram() {
  final cached = _flowingLightProgram;
  if (cached != null) return Future<ui.FragmentProgram>.value(cached);
  return _flowingLightProgramLoad ??=
      ui.FragmentProgram.fromAsset('shaders/flowing_light.frag').then(
        (program) {
          _flowingLightProgram = program;
          return program;
        },
        onError: (Object error, StackTrace stackTrace) {
          // Clear the memo so a later mount can retry instead of latching the
          // failure forever.
          _flowingLightProgramLoad = null;
          throw error;
        },
      );
}

/// Animated color bodies drifting over the player's static backdrop.
///
/// Draws only the moving color: whatever this layer leaves transparent shows
/// the blurred artwork of [FlowingLightBackground] underneath, which is why it
/// is stacked on top of that widget rather than replacing it.
///
/// Renders nothing until both the compiled shader and the artwork palette are
/// available, and stays silent if the shader fails to load at all — widget
/// tests have no shader assets, and a device that cannot compile the runtime
/// effect should degrade to the static backdrop instead of crashing.
class FlowingLightLayer extends StatefulWidget {
  const FlowingLightLayer({
    super.key,
    required this.imageProvider,
    required this.brightness,
  });

  /// Should be the same provider instance the static backdrop resolves, so
  /// both share one `ImageCache` entry instead of decoding the cover twice.
  final ImageProvider<Object> imageProvider;

  final Brightness brightness;

  @override
  State<FlowingLightLayer> createState() => _FlowingLightLayerState();
}

class _FlowingLightLayerState extends State<FlowingLightLayer>
    with TickerProviderStateMixin {
  late final AnimationController _flow = AnimationController(
    vsync: this,
    duration: _kFlowPeriod,
  );
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: _kFadeInDuration,
  );
  ui.FragmentShader? _shader;
  FlowPalette? _palette;
  ImageStream? _imageStream;
  ImageStreamListener? _imageListener;
  int _paletteGeneration = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_loadShader());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _subscribeToArtwork();
    _syncMotion();
  }

  @override
  void didUpdateWidget(covariant FlowingLightLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.imageProvider != oldWidget.imageProvider) {
      _subscribeToArtwork();
    }
  }

  Future<void> _loadShader() async {
    try {
      final program = await _obtainFlowingLightProgram();
      if (!mounted) return;
      setState(() => _shader = program.fragmentShader());
    } catch (_) {
      // Static backdrop only. Intentionally silent: this is a visual
      // enhancement, not a functional path.
    }
  }

  /// Honors the platform "remove animations" setting by parking the drift at a
  /// fixed phase. The layer keeps rendering — the multi-color backdrop is the
  /// feature, the motion is the embellishment.
  void _syncMotion() {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (reduceMotion) {
      if (_flow.isAnimating) _flow.stop(canceled: false);
      _fade.value = 1;
      return;
    }
    if (!_flow.isAnimating) _flow.repeat();
    if (_fade.status == AnimationStatus.dismissed) _fade.forward();
  }

  void _subscribeToArtwork() {
    final stream = widget.imageProvider.resolve(
      createLocalImageConfiguration(context),
    );
    if (_imageStream?.key == stream.key) return;

    final previous = _imageListener;
    if (previous != null) _imageStream?.removeListener(previous);

    final generation = ++_paletteGeneration;
    final listener = ImageStreamListener(
      (imageInfo, synchronousCall) {
        if (!mounted || generation != _paletteGeneration) return;
        unawaited(_derivePalette(imageInfo.image.clone(), generation));
      },
      onError: (Object error, StackTrace? stackTrace) {},
    );
    _imageStream = stream;
    _imageListener = listener;
    stream.addListener(listener);
  }

  Future<void> _derivePalette(ui.Image image, int generation) async {
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (!mounted || generation != _paletteGeneration || data == null) return;
      final palette = extractFlowPalette(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        image.width,
        image.height,
      );
      if (palette == _palette) return;
      setState(() => _palette = palette);
    } finally {
      image.dispose();
    }
  }

  @override
  void dispose() {
    _paletteGeneration++;
    final listener = _imageListener;
    if (listener != null) _imageStream?.removeListener(listener);
    _flow.dispose();
    _fade.dispose();
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shader = _shader;
    final palette = _palette;
    if (shader == null || palette == null) return const SizedBox.expand();
    return RepaintBoundary(
      key: const ValueKey('flowing-light-layer'),
      child: CustomPaint(
        painter: _FlowPainter(
          shader: shader,
          flow: _flow,
          fade: _fade,
          palette: palette,
          intensity: _intensityFor(widget.brightness, palette),
          additive: widget.brightness == Brightness.dark,
        ),
      ),
    );
  }
}

/// Opacity ceiling for the layer.
///
/// The player's lyric colors are fixed constants (`kPlayerInk` in light mode,
/// `onSurface` in dark), so they do not adapt as the backdrop shifts. These
/// ceilings are the budget that keeps the text readable — raise them only
/// against a saturated cover on a real device, not against a muted one.
double _intensityFor(Brightness brightness, FlowPalette palette) {
  if (brightness == Brightness.dark) {
    // Additive over a dark scrim: bright artwork lifts the backdrop toward
    // the near-white lyrics, so pull the glow back as the cover gets lighter.
    return 0.30 + (1 - palette.baseLightness) * 0.16;
  }
  // Source-over onto a near-white scrim: dark artwork pushes the backdrop
  // toward the near-black lyrics instead, so the ceiling tightens as the
  // cover darkens.
  return 0.32 + palette.baseLightness * 0.14;
}

class _FlowPainter extends CustomPainter {
  _FlowPainter({
    required this.shader,
    required this.flow,
    required this.fade,
    required this.palette,
    required this.intensity,
    required this.additive,
  }) : super(repaint: Listenable.merge([flow, fade]));

  final ui.FragmentShader shader;
  final Animation<double> flow;
  final Animation<double> fade;
  final FlowPalette palette;
  final double intensity;

  /// Dark themes composite additively so the layer reads as light gaining on
  /// the backdrop. Source-over there would just paint the cover's own hues
  /// back over themselves — same colors, same brightness, invisible. Light
  /// themes keep source-over instead: the backdrop already carries a near-white
  /// scrim, and adding to it would blow out to white.
  final bool additive;

  @override
  void paint(Canvas canvas, Size size) {
    // Uniform indices are the shader's declaration order flattened to floats:
    // uSize 0-1, uTime 2, uIntensity 3, then one vec4 per body from 4.
    shader
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, flow.value)
      ..setFloat(3, intensity * fade.value);

    for (var i = 0; i < FlowPalette.accentCount; i++) {
      final argb = palette.accentsArgb[i];
      final slot = 4 + i * 4;
      shader
        ..setFloat(slot, ((argb >> 16) & 0xFF) / 255)
        ..setFloat(slot + 1, ((argb >> 8) & 0xFF) / 255)
        ..setFloat(slot + 2, (argb & 0xFF) / 255)
        ..setFloat(slot + 3, _kBodyRadii[i]);
    }

    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..blendMode = additive ? BlendMode.plus : BlendMode.srcOver
        ..shader = shader,
    );
  }

  @override
  bool shouldRepaint(covariant _FlowPainter oldDelegate) =>
      oldDelegate.shader != shader ||
      oldDelegate.palette != palette ||
      oldDelegate.intensity != intensity ||
      oldDelegate.additive != additive;
}
