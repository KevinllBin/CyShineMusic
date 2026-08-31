import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'flowing_light_pipeline.dart';
import 'flowing_light_spec.dart';

/// The player's animated backdrop, replicating Salt's flowing light.
///
/// Composites three rotating, over-saturated copies of the artwork into a
/// buffer of roughly `92x133`, blurs it, blends a quarter of the previous frame
/// back in, and scales the result up to fill the viewport — about 24 times a
/// second. See `flowing_light_spec.dart` for where each constant came from.
///
/// Motion is deliberately conditional: it costs a composite plus a rasterise
/// per frame, so it only runs while the player is open, playing, and pulled
/// most of the way up. When it is not running the last composed frame stays on
/// screen, which is why turning the effect off still leaves a backdrop rather
/// than a flat colour.
class FlowingLightBackground extends StatefulWidget {
  const FlowingLightBackground({
    super.key,
    required this.imageProvider,
    required this.backgroundColor,
    required this.brightness,
    this.running = false,
    this.revealProgress,
  });

  final ImageProvider<Object> imageProvider;
  final Color backgroundColor;
  final Brightness brightness;

  /// Whether the motion is allowed to advance: the flowing-light setting is on
  /// and something is actually playing.
  final bool running;

  /// The shell's player reveal progress, if available. Motion holds below
  /// [kFlowingLightRevealThreshold] so a drag does not compete with the
  /// composite for raster time.
  ///
  /// Read directly inside the ticker rather than listened to, so scrubbing the
  /// player open never rebuilds this subtree.
  final Animation<double>? revealProgress;

  @override
  State<FlowingLightBackground> createState() => _FlowingLightBackgroundState();
}

class _FlowingLightBackgroundState extends State<FlowingLightBackground>
    with TickerProviderStateMixin {
  /// Drives painting without rebuilding: a new frame lands ~24 times a second
  /// and only the painter needs to hear about it.
  final ValueNotifier<_Frames> _frames = ValueNotifier(const _Frames());

  late final Ticker _ticker = createTicker(_onTick);
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: kFlowingLightArtworkFade,
  );
  late final CurvedAnimation _fadeCurve = CurvedAnimation(
    parent: _fade,
    // Salt's PathInterpolator(0, 0, 0.3, 1).
    curve: const Cubic(0, 0, 0.3, 1),
  );

  ImageStream? _imageStream;
  ImageStreamListener? _imageListener;
  ui.Image? _artwork;
  Color _baseColor = const Color(0xFF000000);

  /// The frame fed back into the next composition. Always the same object as
  /// `_frames.value.current`, so it is never disposed on its own.
  ui.Image? _history;

  FlowingLightSpec? _spec;
  Duration _clock = Duration.zero;
  Duration? _lastTick;
  Duration? _lastCompose;
  int _artworkGeneration = 0;
  bool _needsCompose = false;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _fade.addStatusListener(_onFadeStatus);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    _subscribeToArtwork();
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant FlowingLightBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.imageProvider != oldWidget.imageProvider) {
      _subscribeToArtwork();
    }
    if (widget.running != oldWidget.running) _syncTicker();
  }

  // ---------------------------------------------------------------- artwork

  void _subscribeToArtwork() {
    final stream = widget.imageProvider.resolve(
      createLocalImageConfiguration(context),
    );
    if (_imageStream?.key == stream.key) return;

    final previous = _imageListener;
    if (previous != null) _imageStream?.removeListener(previous);

    final generation = ++_artworkGeneration;
    final listener = ImageStreamListener(
      (imageInfo, synchronousCall) {
        if (!mounted || generation != _artworkGeneration) return;
        _adoptArtwork(imageInfo.image.clone(), generation);
      },
      onError: (Object error, StackTrace? stackTrace) {},
    );
    _imageStream = stream;
    _imageListener = listener;
    stream.addListener(listener);
  }

  /// Salt's `setArtwork`: freeze what is on screen, restart the rotations from
  /// zero, drop the accumulated history so the old track's colour cannot bleed
  /// into the new one, and cross-fade over 500ms.
  Future<void> _adoptArtwork(ui.Image image, int generation) async {
    final Color baseColor;
    try {
      baseColor = await sampleFlowingLightBaseColor(image);
    } catch (_) {
      image.dispose();
      return;
    }
    if (!mounted || generation != _artworkGeneration) {
      image.dispose();
      return;
    }

    final displayed = _frames.value.current;
    final alreadyFading = _frames.value.outgoing;
    // Whatever was most recently on screen becomes the frozen layer. A track
    // change that lands before the new artwork's first frame has composed
    // therefore keeps fading the older one out rather than stacking a second
    // frozen layer on top of it, which is how Salt collapses rapid skips.
    final ui.Image? outgoing = displayed ?? alreadyFading;
    final ui.Image? superseded = displayed != null ? alreadyFading : null;
    final outgoingSpec = displayed != null
        ? _frames.value.spec
        : _frames.value.outgoingSpec ?? _frames.value.spec;

    _artwork?.dispose();
    _artwork = image;
    _baseColor = baseColor;
    // Not disposed: it is the same object as `displayed`, which now becomes the
    // outgoing layer and is released when the fade ends.
    _history = null;
    _clock = Duration.zero;
    _lastCompose = null;
    _needsCompose = true;
    _frames.value = _Frames(
      outgoing: outgoing,
      outgoingSpec: outgoingSpec,
      spec: _frames.value.spec,
    );

    if (outgoing == null) {
      _fade.value = 1;
    } else {
      _fade.forward(from: 0);
    }
    _disposeLater(superseded);
    _syncTicker();
  }

  void _onFadeStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    final outgoing = _frames.value.outgoing;
    if (outgoing == null) return;
    _frames.value = _frames.value.withoutOutgoing();
    _disposeLater(outgoing);
  }

  // ------------------------------------------------------------- scheduling

  /// The three conditions Salt requires before the rotations advance.
  bool get _motionAllowed {
    if (!widget.running || _reduceMotion) return false;
    final reveal = widget.revealProgress;
    return reveal == null || reveal.value >= kFlowingLightRevealThreshold;
  }

  /// Reveal progress is intentionally excluded: it changes without a rebuild,
  /// so stopping the ticker on it would leave nothing to notice it coming back.
  /// While the player is fully parked `TickerMode` mutes the ticker anyway.
  bool get _tickerWanted {
    if (_artwork == null || _spec == null) return false;
    return _needsCompose || (widget.running && !_reduceMotion);
  }

  void _syncTicker() {
    if (_tickerWanted) {
      if (!_ticker.isActive) {
        _lastTick = null;
        _ticker.start();
      }
    } else if (_ticker.isActive) {
      _ticker.stop();
      _lastTick = null;
    }
  }

  void _onTick(Duration elapsed) {
    final last = _lastTick;
    _lastTick = elapsed;

    if (_motionAllowed && last != null) {
      final delta = elapsed - last;
      // `TickerMode` mutes a ticker without resetting its clock, so the first
      // tick after the player is pulled back open reports the whole time it was
      // closed. Advancing by that would spin the artwork through a random
      // angle; treat any implausible gap as a resume instead.
      if (delta > _kResumeGap) {
        _lastCompose = _clock;
      } else {
        _clock += delta;
      }
    }

    final lastCompose = _lastCompose;
    final due =
        _motionAllowed &&
        (lastCompose == null || _clock - lastCompose >= kFlowingLightFrameInterval);
    if (_needsCompose || due) {
      _lastCompose = _clock;
      _compose();
      _syncTicker();
    }
  }

  // ---------------------------------------------------------------- drawing

  void _compose() {
    final artwork = _artwork;
    final spec = _spec;
    if (artwork == null || spec == null) return;
    _needsCompose = false;

    final ui.Image frame;
    try {
      frame = composeFlowingLightFrame(
        artwork: artwork,
        baseColor: _baseColor,
        spec: spec,
        clock: _clock,
        history: _history,
      );
    } catch (_) {
      // Leave whatever is already on screen. A backdrop is decoration; a raster
      // failure here should never take the player down with it.
      return;
    }

    // The outgoing frame was composed under its own spec and keeps painting
    // with it, so a resize mid-fade cannot crop it against the wrong geometry.
    //
    // Retire whatever was on screen rather than whatever was serving as
    // history: a spec change clears the latter early, and keying the dispose
    // off it would leak that frame.
    final retired = _frames.value.current;
    _history = frame;
    _frames.value = _frames.value.withCurrent(frame, spec);
    _disposeLater(retired);
  }

  void _disposeLater(ui.Image? image) {
    if (image == null) return;
    // The frame currently being built may still reference it.
    WidgetsBinding.instance.addPostFrameCallback((_) => image.dispose());
  }

  @override
  void dispose() {
    _artworkGeneration++;
    final listener = _imageListener;
    if (listener != null) _imageStream?.removeListener(listener);
    _ticker.dispose();
    _fade.removeStatusListener(_onFadeStatus);
    _fadeCurve.dispose();
    _fade.dispose();
    _artwork?.dispose();
    _frames.value.current?.dispose();
    _frames.value.outgoing?.dispose();
    _frames.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        if (!width.isFinite || !height.isFinite || width <= 0 || height <= 0) {
          return ColoredBox(color: widget.backgroundColor);
        }

        final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
        final spec = FlowingLightSpec.forViewport(
          physicalWidth: math.max(1, (width * devicePixelRatio).round()),
          physicalHeight: math.max(1, (height * devicePixelRatio).round()),
          devicePixelRatio: devicePixelRatio,
          dark: widget.brightness == Brightness.dark,
        );
        // Mutating state during build, matching this file's previous shape: the
        // painter reads the spec off the frame bundle rather than off the
        // widget, so nothing built here depends on it and no rebuild is owed.
        if (_spec != spec) {
          _spec = spec;
          // Salt invalidates its history on any of these too. Beyond matching
          // it, the feedback blend draws the previous frame 1:1, so a buffer
          // that changed size would land misaligned; the frame stays on screen
          // and is retired normally by the next compose.
          _history = null;
          _needsCompose = true;
          _lastCompose = null;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _syncTicker();
          });
        }

        return ClipRect(
          key: const ValueKey('flowing-light-background'),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: widget.backgroundColor),
              CustomPaint(
                key: const ValueKey('flowing-light-image'),
                painter: _FlowingLightPainter(frames: _frames, fade: _fadeCurve),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Longest tick delta still treated as continuous motion rather than a resume.
const Duration _kResumeGap = Duration(milliseconds: 100);

/// What the painter needs, bundled so a single notifier drives it.
@immutable
class _Frames {
  const _Frames({this.current, this.outgoing, this.outgoingSpec, this.spec});

  /// The newest composed frame.
  final ui.Image? current;

  /// The last frame of the previous artwork, frozen while it fades out. Salt
  /// keeps this as a plain shader snapshot and never regenerates it; doing the
  /// same here is what stops a track change from running two pipelines at once.
  final ui.Image? outgoing;

  final FlowingLightSpec? outgoingSpec;
  final FlowingLightSpec? spec;

  _Frames withCurrent(ui.Image image, FlowingLightSpec composedWith) {
    return _Frames(
      current: image,
      outgoing: outgoing,
      outgoingSpec: outgoingSpec ?? spec,
      spec: composedWith,
    );
  }

  _Frames withoutOutgoing() =>
      _Frames(current: current, spec: spec);
}

class _FlowingLightPainter extends CustomPainter {
  _FlowingLightPainter({required this.frames, required this.fade})
    : super(repaint: Listenable.merge([frames, fade]));

  final ValueListenable<_Frames> frames;
  final Animation<double> fade;

  @override
  void paint(Canvas canvas, Size size) {
    final bundle = frames.value;
    final outgoing = bundle.outgoing;
    final outgoingSpec = bundle.outgoingSpec ?? bundle.spec;
    if (outgoing != null && outgoingSpec != null) {
      paintFlowingLightFrame(canvas, size, outgoing, outgoingSpec, opacity: 1);
    }

    final current = bundle.current;
    final spec = bundle.spec;
    if (current == null || spec == null) return;
    paintFlowingLightFrame(
      canvas,
      size,
      current,
      spec,
      // Salt draws the frozen frame opaque and ramps the new one up over it,
      // so there is never a moment where both are partly transparent and the
      // background shows through.
      opacity: outgoing == null ? 1 : fade.value,
    );
  }

  @override
  bool shouldRepaint(covariant _FlowingLightPainter oldDelegate) =>
      oldDelegate.frames != frames || oldDelegate.fade != fade;
}
