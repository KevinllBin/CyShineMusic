import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart' show Ticker;

import '../../../theme/app_motion.dart';
import '../lyric_parser.dart';
import 'player_palette.dart';

const double _kLyricSelectionHorizontalPadding = 18;
// Inactive rows render at 25.5px visually, but layout always runs at the
// focused 32px metrics (see LyricLineTile.build) — the shrink is pure paint.
const double _kLyricInactiveScale = 25.5 / 32;
const double _kLyricStaggerBaseDelayMs = 50;
const double _kLyricStaggerDelayDecay = 1.05;
const double _kLyricStaggerStiffness = 200;
const double _kLyricStaggerDampingRatio = 1.1;

class StaggeredLyricLine extends StatefulWidget {
  const StaggeredLyricLine({
    super.key,
    required this.lineStartMs,
    required this.index,
    required this.generation,
    required this.shiftPx,
    required this.visibleStartIndex,
    required this.child,
  });

  final int lineStartMs;
  final int index;
  final int generation;
  final double shiftPx;
  final int visibleStartIndex;
  final Widget child;

  @override
  State<StaggeredLyricLine> createState() => _StaggeredLyricLineState();
}

class _StaggeredLyricLineState extends State<StaggeredLyricLine>
    with SingleTickerProviderStateMixin {
  static final SpringDescription _spring = SpringDescription(
    mass: 1,
    stiffness: _kLyricStaggerStiffness,
    damping:
        2 * math.sqrt(_kLyricStaggerStiffness) * _kLyricStaggerDampingRatio,
  );

  late final AnimationController _controller = AnimationController.unbounded(
    vsync: this,
  );
  Timer? _delayTimer;

  @override
  void initState() {
    super.initState();
    // Rows materialized right after the stagger jump (newly revealed at a
    // viewport edge) must join the wave like rows that were already built.
    // The view zeroes shiftPx once the wave is over, so rows created by
    // ordinary scrolling never pick up a stale shift here.
    if (widget.shiftPx.abs() >= 0.01) {
      _startMotion();
    }
  }

  @override
  void didUpdateWidget(covariant StaggeredLyricLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.generation != oldWidget.generation) {
      _startMotion();
    }
  }

  void _startMotion() {
    _delayTimer?.cancel();
    // Carry the offset/velocity left from an interrupted wave so a new
    // advance starts exactly where the line is currently drawn instead of
    // teleporting it (visible on fast, dense lyrics).
    final residualVelocity = _controller.velocity;
    _controller.stop();
    final start = widget.shiftPx + _controller.value;
    if (start.abs() < 0.5) {
      _controller.value = 0;
      return;
    }

    _controller.value = start;
    if (widget.shiftPx.abs() < 0.01) {
      // Cancelled wave: settle the leftover offset right away, no delay.
      unawaited(
        _controller.animateWith(
          SpringSimulation(_spring, start, 0, residualVelocity),
        ),
      );
      return;
    }
    final distance = (widget.index - widget.visibleStartIndex).abs();
    var delayMs = 0.0;
    var stepMs = _kLyricStaggerBaseDelayMs;
    for (var index = 0; index < distance; index++) {
      delayMs += stepMs;
      stepMs /= _kLyricStaggerDelayDecay;
    }
    _delayTimer = Timer(Duration(microseconds: (delayMs * 1000).round()), () {
      if (!mounted) return;
      unawaited(
        _controller.animateWith(
          SpringSimulation(_spring, start, 0, residualVelocity),
        ),
      );
    });
  }

  @override
  void dispose() {
    _delayTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        return Transform.translate(
          key: ValueKey('lyric-stagger-${widget.lineStartMs}'),
          offset: Offset(0, _controller.value),
          child: child,
        );
      },
    );
  }
}

class LyricLineTile extends StatelessWidget {
  const LyricLineTile({
    super.key,
    required this.line,
    required this.active,
    required this.selected,
    required this.distance,
    required this.blurSuppressed,
    required this.showTranslation,
    required this.anchorMs,
    required this.playing,
    required this.onSelect,
    required this.onSeek,
  });

  final KaraokeLyricLine line;
  final bool active;
  final bool selected;
  final int distance;
  final ValueListenable<bool> blurSuppressed;
  final bool showTranslation;
  final ValueListenable<int> anchorMs;
  final ValueListenable<bool> playing;
  final VoidCallback onSelect;
  final VoidCallback onSeek;

  @override
  Widget build(BuildContext context) {
    final inactiveOpacity = active
        ? 1.0
        : (0.58 - math.min(distance, 6) * 0.055).clamp(0.24, 0.53);
    // Layout ALWAYS runs at the focused metrics (32px / w500): font size and
    // weight never change, so Wrap line-breaking is identical in both focus
    // states. Animating the font size instead used to re-wrap long lines at
    // some mid-animation size, shifting every row below by a whole wrapped
    // line in a single frame — the big occasional jitter on line advance.
    // Inactive rows are shrunk visually with the Transform.scale below; the
    // animated DefaultTextStyle now only drives *color* (layout-neutral).
    final mainStyle = TextStyle(
      color: active
          ? playerInk(context)
          : playerMuted(context).withValues(alpha: inactiveOpacity),
      fontFamilyFallback: kPlayerFontFallback,
      fontSize: 32,
      fontWeight: FontWeight.w500,
      height: 1.20,
      letterSpacing: 0,
    );
    final karaokeDimColor = playerInk(context).withValues(alpha: 0.24);
    final subStyle = TextStyle(
      color: active
          ? playerMuted(context).withValues(alpha: 0.78)
          : playerMuted(context).withValues(alpha: inactiveOpacity),
      fontFamilyFallback: kPlayerFontFallback,
      fontSize: 14,
      fontWeight: FontWeight.w400,
      height: 1.30,
      letterSpacing: 0,
    );

    final translation = line.translation?.trim();
    final roman = line.roman?.trim();
    final hasTranslationLine = translation != null && translation.isNotEmpty;
    final showTranslationLine = showTranslation && hasTranslationLine;
    final showRomanLine = roman != null && roman.isNotEmpty;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : AppMotion.medium;
    final lineContent = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedDefaultTextStyle(
          duration: duration,
          curve: AppMotion.emphasized,
          style: mainStyle,
          textAlign: TextAlign.start,
          child: _mainText(karaokeDimColor),
        ),
        if (hasTranslationLine)
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: showTranslationLine ? 1 : 0),
            duration: duration,
            curve: AppMotion.emphasized,
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                translation,
                textAlign: TextAlign.start,
                style: subStyle,
              ),
            ),
            builder: (context, value, child) {
              return ClipRect(
                child: Align(
                  alignment: Alignment.topLeft,
                  heightFactor: value,
                  child: Opacity(
                    opacity: value,
                    child: Transform.translate(
                      offset: Offset(0, 6 * (1 - value)),
                      child: child,
                    ),
                  ),
                ),
              );
            },
          ),
        if (showRomanLine)
          AnimatedPadding(
            duration: duration,
            curve: AppMotion.emphasized,
            padding: EdgeInsets.only(
              top: hasTranslationLine && showTranslationLine ? 0 : 8,
            ),
            child: Text(
              roman,
              textAlign: TextAlign.start,
              style: subStyle.copyWith(fontSize: 12),
            ),
          ),
      ],
    );

    // Paint-only shrink for unfocused rows. Scaling never touches layout, so
    // focus changes cause zero relayout of the list — the stagger wave is the
    // only motion on a line advance.
    final scaledContent = TweenAnimationBuilder<double>(
      tween: Tween<double>(end: active ? 1.0 : _kLyricInactiveScale),
      duration: duration,
      curve: AppMotion.emphasized,
      child: lineContent,
      builder: (context, scale, child) {
        return Transform.scale(
          scale: scale,
          alignment: Alignment.centerLeft,
          child: child,
        );
      },
    );

    final tile = GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTapDown: (_) => onSelect(),
      onTap: onSeek,
      child: AnimatedContainer(
        duration: duration,
        curve: AppMotion.emphasized,
        margin: const EdgeInsets.symmetric(vertical: 1),
        padding: EdgeInsets.symmetric(
          horizontal: selected ? _kLyricSelectionHorizontalPadding : 0,
          vertical: 11,
        ),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          color: selected
              ? playerInk(context).withValues(alpha: 0.075)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(22),
        ),
        child: scaledContent,
      ),
    );

    final blurSigma = switch (distance) {
      0 => 0.0,
      1 => 1.1,
      2 => 2.0,
      3 => 3.0,
      _ => 3.65,
    };
    // One stable wrapper for every line, focused or not: swapping widget
    // types on the focus boundary would rebuild the subtree and kill the
    // style transitions above. The sigma tween also eases per-line blur
    // changes on focus advance instead of snapping them.
    return ValueListenableBuilder<bool>(
      valueListenable: blurSuppressed,
      child: tile,
      builder: (context, suppressed, child) {
        return TweenAnimationBuilder<double>(
          tween: Tween<double>(end: blurSigma),
          duration: duration,
          curve: AppMotion.emphasized,
          child: child,
          builder: (context, sigma, child) {
            return ImageFiltered(
              imageFilter: ImageFilter.blur(
                sigmaX: sigma,
                sigmaY: sigma,
                tileMode: TileMode.clamp,
              ),
              enabled: !suppressed && sigma > 0.05,
              child: child,
            );
          },
        );
      },
    );
  }

  Widget _mainText(Color karaokeDimColor) {
    if (!active || !line.hasWordTiming) {
      // No explicit style: the text inherits the AnimatedDefaultTextStyle
      // above, so font size and color keep transitioning on focus changes.
      return Text(line.text, textAlign: TextAlign.start);
    }
    return _KaraokeLineText(
      line: line,
      dimColor: karaokeDimColor,
      anchorMs: anchorMs,
      playing: playing,
    );
  }
}

class _KaraokeLineText extends StatefulWidget {
  const _KaraokeLineText({
    required this.line,
    required this.dimColor,
    required this.anchorMs,
    required this.playing,
  });

  final KaraokeLyricLine line;

  /// Un-swept base color. Applied as a color-only override so both text
  /// layers keep inheriting (and animating with) the ambient
  /// AnimatedDefaultTextStyle and always lay out identically.
  final Color dimColor;

  /// Latest value from the player's position stream — an anchor, not a
  /// per-frame clock (just_audio emits it only every ~200 ms).
  final ValueListenable<int> anchorMs;
  final ValueListenable<bool> playing;

  @override
  State<_KaraokeLineText> createState() => _KaraokeLineTextState();
}

class _KaraokeLineTextState extends State<_KaraokeLineText>
    with SingleTickerProviderStateMixin {
  // The ~200 ms position stream is far too coarse for per-character sweeps —
  // words often last less than one stream period, so progress would jump in
  // one or two visible steps. While playing, extrapolate wall-clock time past
  // the latest anchor with a per-frame ticker; every new anchor resets the
  // stopwatch, so drift never exceeds one stream period. The ticker writes
  // into a ValueNotifier instead of calling setState, so each frame only the
  // per-word Align widgets listening below rebuild — never this whole line.
  late final Ticker _ticker;
  final Stopwatch _sinceAnchor = Stopwatch();
  late final ValueNotifier<int> _effectiveMs;

  @override
  void initState() {
    super.initState();
    _effectiveMs = ValueNotifier<int>(widget.anchorMs.value);
    _ticker = createTicker((_) => _publish());
    widget.anchorMs.addListener(_handleAnchorChanged);
    widget.playing.addListener(_handlePlayingChanged);
    _syncDrive();
  }

  @override
  void didUpdateWidget(covariant _KaraokeLineText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.anchorMs, oldWidget.anchorMs)) {
      oldWidget.anchorMs.removeListener(_handleAnchorChanged);
      widget.anchorMs.addListener(_handleAnchorChanged);
      _handleAnchorChanged();
    }
    if (!identical(widget.playing, oldWidget.playing)) {
      oldWidget.playing.removeListener(_handlePlayingChanged);
      widget.playing.addListener(_handlePlayingChanged);
      _syncDrive();
    }
  }

  void _handleAnchorChanged() {
    _sinceAnchor.reset();
    _publish();
  }

  void _handlePlayingChanged() {
    _syncDrive();
  }

  void _syncDrive() {
    if (widget.playing.value) {
      _sinceAnchor.start();
      if (!_ticker.isActive) _ticker.start();
    } else {
      _sinceAnchor.stop();
      if (_ticker.isActive) _ticker.stop();
      _publish();
    }
  }

  void _publish() {
    _effectiveMs.value =
        widget.anchorMs.value + _sinceAnchor.elapsedMilliseconds;
  }

  @override
  void dispose() {
    widget.anchorMs.removeListener(_handleAnchorChanged);
    widget.playing.removeListener(_handlePlayingChanged);
    _ticker.dispose();
    _effectiveMs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.start,
      runAlignment: WrapAlignment.start,
      children: [
        for (final word in widget.line.words)
          _WordHighlight(
            word: word,
            dimColor: widget.dimColor,
            positionMs: _effectiveMs,
          ),
      ],
    );
  }
}

class _WordHighlight extends StatelessWidget {
  const _WordHighlight({
    required this.word,
    required this.dimColor,
    required this.positionMs,
  });

  final KaraokeWordTiming word;
  final Color dimColor;
  final ValueListenable<int> positionMs;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Color-only override: size and weight come from the inherited
        // DefaultTextStyle, so both layers stay in animated lockstep.
        Text(word.text, style: TextStyle(color: dimColor)),
        ClipRect(
          // Only the Align rebuilds per frame; both Text render objects (and
          // their laid-out glyphs) are reused untouched.
          child: ValueListenableBuilder<int>(
            valueListenable: positionMs,
            child: Text(word.text),
            builder: (context, ms, child) {
              return Align(
                alignment: Alignment.centerLeft,
                widthFactor: word.progressAt(ms),
                child: child,
              );
            },
          ),
        ),
      ],
    );
  }
}
