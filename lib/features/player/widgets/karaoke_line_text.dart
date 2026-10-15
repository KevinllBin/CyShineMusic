import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart'
    show ValueListenable, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;

import '../lyric_parser.dart';

const _dimAlpha = 0.3;
const _clockCorrectionMs = 200.0;
const _clockDiscontinuityMs = 160.0;
const _colorDuration = Duration(milliseconds: 700);
const _colorCurve = Cubic(0.25, 0, 0.2, 1);

/// A single shaped paragraph, with playback effects applied only at paint time.
class KaraokeLineText extends StatefulWidget {
  const KaraokeLineText({
    super.key,
    required this.line,
    required this.anchorMs,
    required this.playing,
    required this.buffering,
    required this.active,
  });

  final KaraokeLyricLine line;
  final ValueListenable<int> anchorMs;
  final ValueListenable<bool> playing;
  final ValueListenable<bool> buffering;
  final bool active;

  @override
  KaraokeLineTextState createState() => KaraokeLineTextState();
}

class KaraokeLineTextState extends State<KaraokeLineText>
    with TickerProviderStateMixin {
  late final Ticker _ticker;
  final _sinceAnchor = Stopwatch();
  late final ValueNotifier<double> _position;
  late double _anchorPositionMs;
  double _anchorErrorMs = 0;
  late final AnimationController _emphasis;
  late final Listenable _repaint;
  _LyricParagraph? _paragraph;
  bool _reduceMotion = false;

  /// The playback time consumed by the painter, including clock interpolation.
  @visibleForTesting
  double get debugPlaybackPositionMs => _position.value;

  @override
  void initState() {
    super.initState();
    _anchorPositionMs = widget.anchorMs.value.toDouble();
    _position = ValueNotifier(_anchorPositionMs);
    _emphasis = AnimationController(
      vsync: this,
      value: widget.active ? 1 : 0,
      duration: _colorDuration,
    );
    _repaint = Listenable.merge([_position, _emphasis]);
    _ticker = createTicker((_) => _publish());
    _emphasis.addStatusListener((_) => _syncClock());
    widget.anchorMs.addListener(_handleAnchor);
    widget.playing.addListener(_handlePlayback);
    widget.buffering.addListener(_handlePlayback);
    _syncClock();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion) _emphasis.value = widget.active ? 1 : 0;
  }

  @override
  void didUpdateWidget(covariant KaraokeLineText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.anchorMs, oldWidget.anchorMs)) {
      oldWidget.anchorMs.removeListener(_handleAnchor);
      widget.anchorMs.addListener(_handleAnchor);
      _handleAnchor();
    }
    if (!identical(widget.playing, oldWidget.playing)) {
      oldWidget.playing.removeListener(_handlePlayback);
      widget.playing.addListener(_handlePlayback);
    }
    if (!identical(widget.buffering, oldWidget.buffering)) {
      oldWidget.buffering.removeListener(_handlePlayback);
      widget.buffering.addListener(_handlePlayback);
    }
    if (widget.active != oldWidget.active) {
      final target = widget.active ? 1.0 : 0.0;
      if (_reduceMotion) {
        _emphasis.value = target;
      } else {
        unawaited(_emphasis.animateTo(target, curve: _colorCurve));
      }
    }
    _syncClock();
  }

  double get _clockPosition {
    final elapsedMs = _sinceAnchor.elapsedMicroseconds / 1000;
    return _anchorPositionMs +
        elapsedMs +
        _anchorErrorMs * math.exp(-elapsedMs / _clockCorrectionMs);
  }

  void _handleAnchor() {
    final anchor = widget.anchorMs.value.toDouble();
    final error = _clockPosition - anchor;
    // Native position samples can arrive slightly behind the interpolated
    // clock. Absorb small corrections without moving any glyph backwards;
    // a seek or other large discontinuity must still take effect immediately.
    _anchorErrorMs =
        _sinceAnchor.isRunning && error.abs() < _clockDiscontinuityMs
        ? error
        : 0;
    _anchorPositionMs = anchor;
    _sinceAnchor.reset();
    _publish();
  }

  void _handlePlayback() {
    // Freeze at the displayed time instead of losing the partial anchor
    // interval when pausing or buffering. Resume from that same position.
    _anchorPositionMs = _clockPosition;
    _anchorErrorMs = 0;
    _sinceAnchor.reset();
    _syncClock();
  }

  void _syncClock() {
    if (widget.playing.value && !widget.buffering.value) {
      _sinceAnchor.start();
      if ((widget.active || _emphasis.isAnimating) && !_ticker.isActive) {
        _ticker.start();
      }
    } else {
      _sinceAnchor.stop();
      if (_ticker.isActive) _ticker.stop();
    }
    if (!widget.active && !_emphasis.isAnimating && _ticker.isActive) {
      _ticker.stop();
    }
    _publish();
  }

  void _publish() {
    // Keep sub-millisecond precision between BASS's 40 ms samples. Only paint
    // is invalidated; the shaped paragraph and its layout stay unchanged.
    _position.value = _clockPosition;
  }

  @override
  void dispose() {
    widget.anchorMs.removeListener(_handleAnchor);
    widget.playing.removeListener(_handlePlayback);
    widget.buffering.removeListener(_handlePlayback);
    _ticker.dispose();
    _emphasis.dispose();
    _position.dispose();
    _paragraph?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style;
    final scaler = MediaQuery.textScalerOf(context);
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    final direction = Directionality.of(context);
    final locale = Localizations.maybeLocaleOf(context);
    return Semantics(
      label: widget.line.text,
      child: LayoutBuilder(
        builder: (context, constraints) {
          var paragraph = _paragraph;
          if (paragraph == null ||
              !identical(paragraph.line, widget.line) ||
              paragraph.style != style ||
              paragraph.scaler != scaler ||
              paragraph.pixelRatio != pixelRatio ||
              paragraph.direction != direction ||
              paragraph.locale != locale ||
              paragraph.width != constraints.maxWidth) {
            paragraph?.dispose();
            paragraph = _paragraph = _LyricParagraph(
              widget.line,
              style,
              scaler,
              pixelRatio,
              direction,
              locale,
              constraints.maxWidth,
            );
          }
          if (widget.active && !_reduceMotion) paragraph.prepareGlyphImages();
          return CustomPaint(
            size: Size(paragraph.width, paragraph.text.height + paragraph.lift),
            painter: _KaraokePainter(
              paragraph,
              _position,
              _emphasis,
              _repaint,
              active: widget.active,
              reduceMotion: _reduceMotion,
            ),
          );
        },
      ),
    );
  }
}

class _Glyph {
  _Glyph(this.rect, this.center, this.from, this.to);
  final Rect rect;
  final double center;
  final int from;
  final int to;
  ui.Image? image;
  Offset imageOrigin = Offset.zero;
}

class _VisualLine {
  _VisualLine(this.rect, this.start);
  final Rect rect;
  final double start;
  final glyphs = <_Glyph>[];
}

class _TimedSweep {
  const _TimedSweep(this.word, this.start, this.end);
  final KaraokeWordTiming word;
  final double start;
  final double end;
}

class _LyricParagraph {
  _LyricParagraph(
    this.line,
    this.style,
    this.scaler,
    this.pixelRatio,
    this.direction,
    this.locale,
    this.width,
  ) {
    final raw = line.words.map((word) => word.text).join();
    final content = raw.trim();
    final trimOffset = raw.length - raw.trimLeft().length;
    final fontSize = scaler.scale(style.fontSize ?? 32);
    lift = (fontSize * pixelRatio * 0.1).roundToDouble() / pixelRatio;
    feather = fontSize * 0.25;
    liftRange = fontSize * 3;
    text = TextPainter(
      text: TextSpan(text: content, style: style),
      textDirection: direction,
      textScaler: scaler,
      locale: locale,
    )..layout(maxWidth: width);
    var start = 0.0;
    for (final metrics in text.computeLineMetrics()) {
      final top = metrics.baseline - metrics.ascent;
      visualLines.add(
        _VisualLine(
          Rect.fromLTWH(metrics.left, top, metrics.width, metrics.height),
          start,
        ),
      );
      start += metrics.width + feather;
    }
    end = math.max(0, start - feather);
    final boundaries = <int>[0];
    for (final character in content.characters) {
      boundaries.add(boundaries.last + character.length);
    }
    final glyphs = <_Glyph>[];
    for (var index = 0; index + 1 < boundaries.length; index++) {
      final from = boundaries[index];
      var to = boundaries[index + 1];
      var boxes = text.getBoxesForSelection(
        TextSelection(baseOffset: from, extentOffset: to),
      );
      // Font shaping may combine several graphemes (fi/ffi, for example).
      // Partial selections omit that glyph; keep its whole cluster together.
      while (boxes.isEmpty && index + 2 < boundaries.length) {
        to = boundaries[++index + 1];
        boxes = text.getBoxesForSelection(
          TextSelection(baseOffset: from, extentOffset: to),
        );
      }
      for (final box in boxes) {
        final rect = box.toRect();
        if (rect.width <= 0) continue;
        final row = _rowFor(rect);
        final glyph = _Glyph(
          rect,
          row.start + rect.center.dx - row.rect.left,
          from,
          to,
        );
        row.glyphs.add(glyph);
        glyphs.add(glyph);
      }
    }
    var offset = -trimOffset;
    for (final word in line.words) {
      final next = offset + word.text.length;
      final from = offset.clamp(0, content.length);
      final to = next.clamp(0, content.length);
      if (to > from) {
        final covered = glyphs.where(
          (glyph) => glyph.to > from && glyph.from < to,
        );
        if (covered.isNotEmpty) {
          final firstGlyph = covered.first;
          final lastGlyph = covered.last;
          final first = firstGlyph.rect;
          final last = lastGlyph.rect;
          final firstRow = _rowFor(first);
          final lastRow = _rowFor(last);
          final firstX =
              first.left +
              first.width *
                  ((from - firstGlyph.from) / (firstGlyph.to - firstGlyph.from))
                      .clamp(0.0, 1.0);
          final lastX =
              last.left +
              last.width *
                  ((to - lastGlyph.from) / (lastGlyph.to - lastGlyph.from))
                      .clamp(0.0, 1.0);
          final atStart = (firstX - firstRow.rect.left).abs() < 0.5;
          sweeps.add(
            _TimedSweep(
              word,
              firstRow.start +
                  firstX -
                  firstRow.rect.left -
                  (atStart ? feather : 0),
              lastRow.start + lastX - lastRow.rect.left,
            ),
          );
        }
      }
      offset = next;
    }
  }

  final KaraokeLyricLine line;
  final TextStyle style;
  final TextScaler scaler;
  final double pixelRatio;
  final TextDirection direction;
  final Locale? locale;
  final double width;
  late final TextPainter text;
  late final double lift;
  late final double feather;
  late final double liftRange;
  late final double end;
  final visualLines = <_VisualLine>[];
  final sweeps = <_TimedSweep>[];

  _VisualLine _rowFor(Rect glyph) => visualLines.firstWhere(
    (row) =>
        glyph.center.dy >= row.rect.top && glyph.center.dy <= row.rect.bottom,
    orElse: () => visualLines.last,
  );

  double frontAt(double ms) {
    if (sweeps.isEmpty) return end;
    var front = sweeps.first.start;
    for (final sweep in sweeps) {
      if (ms < sweep.word.startMs) return front;
      if (ms < sweep.word.endMs) {
        return sweep.start +
            (sweep.end - sweep.start) *
                ((ms - sweep.word.startMs) /
                    math.max(1, sweep.word.endMs - sweep.word.startMs));
      }
      front = sweep.end;
    }
    return end;
  }

  double riseAt(double center, double front) {
    final halfRange = liftRange / 2;
    final phase = (center - front + halfRange) / liftRange;
    if (phase <= 0) return 1;
    if (phase >= 1) return 0;
    final tail = (1 - (end - front) / halfRange).clamp(0.0, 1.0);
    final settle = tail * tail;
    return math.cos(phase * math.pi) * (1 - settle) / 2 + (1 + settle) / 2;
  }

  void prepareGlyphImages() {
    for (final row in visualLines) {
      for (final glyph in row.glyphs) {
        if (glyph.image != null) continue;
        final width = (glyph.rect.width * pixelRatio).ceil();
        final height = (glyph.rect.height * pixelRatio).ceil();
        if (width <= 0 || height <= 0) continue;
        final origin = Offset(
          (glyph.rect.left * pixelRatio).roundToDouble(),
          (glyph.rect.top * pixelRatio).roundToDouble(),
        );
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder)
          ..translate(-origin.dx, -origin.dy)
          ..scale(pixelRatio);
        // Capture the already-shaped cluster once at a fixed physical-pixel
        // origin. During motion only the bitmap moves, so rasterization and
        // the glyph's clip edges cannot change from frame to frame.
        text.paint(canvas, Offset.zero);
        final picture = recorder.endRecording();
        try {
          glyph.image = picture.toImageSync(width, height);
          glyph.imageOrigin = origin / pixelRatio;
        } finally {
          picture.dispose();
        }
      }
    }
  }

  void dispose() {
    for (final row in visualLines) {
      for (final glyph in row.glyphs) {
        glyph.image?.dispose();
      }
    }
    text.dispose();
  }
}

class _KaraokePainter extends CustomPainter {
  _KaraokePainter(
    this.paragraph,
    this.position,
    this.emphasis,
    Listenable repaint, {
    required this.active,
    required this.reduceMotion,
  }) : super(repaint: repaint);

  final _LyricParagraph paragraph;
  final ValueListenable<double> position;
  final Animation<double> emphasis;
  final bool active;
  final bool reduceMotion;
  final _imagePaint = Paint()..filterQuality = FilterQuality.low;

  @override
  void paint(Canvas canvas, Size size) {
    final p = paragraph;
    final ms = position.value;
    final peak = _dimAlpha + (1 - _dimAlpha) * emphasis.value;
    if (!active) {
      final dy = !reduceMotion && ms < p.line.startMs ? p.lift : 0.0;
      canvas.saveLayer(
        Offset.zero & size,
        Paint()..color = Colors.white.withValues(alpha: peak),
      );
      p.text.paint(canvas, Offset(0, dy));
      canvas.restore();
      return;
    }
    final front = p.frontAt(ms);
    for (final row in p.visualLines) {
      final bounds = Rect.fromLTRB(
        0,
        row.rect.top,
        size.width,
        row.rect.bottom + p.lift,
      );
      canvas.saveLayer(bounds, Paint());
      for (final glyph in row.glyphs) {
        final dy = reduceMotion
            ? 0.0
            : p.lift * (1 - p.riseAt(glyph.center, front));
        final image = glyph.image;
        canvas.save();
        if (image != null && !reduceMotion) {
          canvas.translate(glyph.imageOrigin.dx, glyph.imageOrigin.dy + dy);
          canvas.scale(1 / p.pixelRatio);
          canvas.drawImage(image, Offset.zero, _imagePaint);
        } else {
          canvas.translate(0, dy);
          canvas.clipRect(glyph.rect);
          p.text.paint(canvas, Offset.zero);
        }
        canvas.restore();
      }
      final x = row.rect.left + front - row.start;
      canvas.drawRect(
        bounds,
        Paint()
          ..blendMode = BlendMode.dstIn
          ..shader =
              ui.Gradient.linear(Offset(x, 0), Offset(x + p.feather, 0), [
                Colors.white.withValues(alpha: peak),
                Colors.white.withValues(alpha: _dimAlpha),
              ]),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_KaraokePainter oldDelegate) =>
      paragraph != oldDelegate.paragraph ||
      position != oldDelegate.position ||
      emphasis != oldDelegate.emphasis ||
      active != oldDelegate.active ||
      reduceMotion != oldDelegate.reduceMotion;
}
