import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show FontVariation, ImageFilter;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/settings_store.dart';
import '../../../theme/app_motion.dart';
import '../lyric_parser.dart';
import 'karaoke_line_text.dart';
import 'player_control_color.dart';
import 'player_palette.dart';

const double _kLyricSelectionHorizontalPadding = 18;
const double _kLyricInactiveScale = 0.95;
const Duration _kLyricFocusInDuration = Duration(milliseconds: 600);
const Duration _kLyricFocusOutDuration = Duration(milliseconds: 500);
const Duration _kLyricFocusOutDelay = Duration(milliseconds: 100);
const Curve _kLyricFocusCurve = Cubic(0.25, 0, 0.2, 1);
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
    // Each generation starts from the exact list relocation delta. Carrying
    // a previous wave's residual offset adds it to the next line height and
    // makes dense lyrics accumulate a larger and larger visible swing.
    _controller.stop();
    final start = widget.shiftPx;
    if (start.abs() < 0.5) {
      _controller.value = 0;
      return;
    }

    _controller.value = start;
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
        _controller.animateWith(SpringSimulation(_spring, start, 0, 0)),
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
      child: RepaintBoundary(child: widget.child),
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

class LyricLineTile extends ConsumerWidget {
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
    required this.buffering,
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
  final ValueListenable<bool> buffering;
  final VoidCallback onSelect;
  final VoidCallback onSeek;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final font = ref.watch(
      settingsProvider.select(
        (settings) =>
            (weight: settings.lyricFontWeight, size: settings.lyricFontSize),
      ),
    );
    final blurDisabled = ref.watch(
      settingsProvider.select((settings) => settings.lyricViewBlurDisabled),
    );
    final secondaryWeight = (font.weight - 100).clamp(
      kLyricFontWeightMin,
      kLyricFontWeightMax,
    );
    final sizeScale = font.size / kLyricFontSizeDefault;
    final ink = Theme.of(context).brightness == Brightness.dark
        ? Colors.white
        : ref.watch(playerLyricInkProvider) ?? const Color(0xFF050F19);
    // Fixed metrics keep line breaks and row heights stable on focus changes.
    // Color, focus scale and per-character lift only affect painting.
    final mainStyle = TextStyle(
      color: ink.withValues(alpha: line.hasWordTiming || active ? 1 : 0.3),
      fontFamilyFallback: kPlayerFontFallback,
      fontSize: font.size,
      fontWeight: FontWeight(font.weight.round()),
      fontVariations: [FontVariation.weight(font.weight)],
      height: 1.20,
      letterSpacing: 0,
    );
    final subStyle = TextStyle(
      color: ink.withValues(alpha: active && !line.hasWordTiming ? 1 : 0.3),
      fontFamilyFallback: kPlayerFontFallback,
      fontSize: 14 * sizeScale,
      fontWeight: FontWeight(secondaryWeight.round()),
      fontVariations: [FontVariation.weight(secondaryWeight)],
      height: 1.30,
      letterSpacing: 0,
    );

    final translation = line.translation?.trim();
    final roman = line.roman?.trim();
    final hasTranslationLine = translation != null && translation.isNotEmpty;
    final hasRomanLine = roman != null && roman.isNotEmpty;
    final showTranslationLine = showTranslation && hasTranslationLine;
    final showRomanLine = showTranslation && hasRomanLine;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : AppMotion.medium;
    final colorDuration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 700);
    final lineContent = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _LyricTextStyle(
          duration: colorDuration,
          curve: _kLyricFocusCurve,
          style: mainStyle,
          textAlign: TextAlign.start,
          child: RepaintBoundary(child: _mainText()),
        ),
        if (hasTranslationLine)
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: showTranslationLine ? 1 : 0),
            duration: duration,
            curve: AppMotion.emphasized,
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _LyricTextStyle(
                duration: colorDuration,
                curve: _kLyricFocusCurve,
                style: subStyle,
                child: Text(translation, textAlign: TextAlign.start),
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
        if (hasRomanLine)
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: showRomanLine ? 1 : 0),
            duration: duration,
            curve: AppMotion.emphasized,
            child: Padding(
              padding: EdgeInsets.only(top: hasTranslationLine ? 2 : 8),
              child: _LyricTextStyle(
                duration: colorDuration,
                curve: _kLyricFocusCurve,
                style: subStyle.copyWith(fontSize: 12 * sizeScale),
                child: Text(roman, textAlign: TextAlign.start),
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
      ],
    );

    // Paint-only shrink for unfocused rows. Scaling never touches layout, so
    // focus changes cause zero relayout of the list — the stagger wave is the
    // only motion on a line advance.
    final scaledContent = _LyricFocusScale(
      lineStartMs: line.startMs,
      active: active,
      disableAnimations: MediaQuery.disableAnimationsOf(context),
      child: RepaintBoundary(child: lineContent),
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
          tween: Tween<double>(end: blurDisabled || suppressed ? 0 : blurSigma),
          duration: blurDisabled || suppressed ? Duration.zero : duration,
          curve: AppMotion.emphasized,
          child: child,
          builder: (context, sigma, child) {
            return ImageFiltered(
              // Decal, not clamp: clamp replicates the glyph-edge pixels
              // outward before blurring, which draws a hard rectangular seam
              // wherever text touches its paint bounds (line start, cap
              // height, wrapped-line right edge). Decal samples transparent
              // outside the bounds so the halo fades out naturally.
              imageFilter: ImageFilter.blur(
                sigmaX: sigma,
                sigmaY: sigma,
                tileMode: TileMode.decal,
              ),
              enabled: !blurDisabled && !suppressed && sigma > 0.05,
              child: child,
            );
          },
        );
      },
    );
  }

  Widget _mainText() {
    if (!line.hasWordTiming) {
      // No explicit style: the text inherits the AnimatedDefaultTextStyle
      // above, so color can transition without changing layout metrics.
      return Text(line.text, textAlign: TextAlign.start);
    }
    return KaraokeLineText(
      line: line,
      anchorMs: anchorMs,
      playing: playing,
      buffering: buffering,
      active: active,
    );
  }
}

/// Animate color alone: font settings take effect once without interpolating
/// paragraph widths and line breaks throughout the color transition.
class _LyricTextStyle extends StatelessWidget {
  const _LyricTextStyle({
    required this.style,
    required this.duration,
    required this.curve,
    required this.child,
    this.textAlign = TextAlign.start,
  });

  final TextStyle style;
  final Duration duration;
  final Curve curve;
  final TextAlign textAlign;
  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<Color?>(
    tween: ColorTween(end: style.color),
    duration: duration,
    curve: curve,
    child: child,
    builder: (context, color, child) => DefaultTextStyle(
      style: style.copyWith(color: color),
      textAlign: textAlign,
      child: child!,
    ),
  );
}

class _LyricFocusScale extends StatefulWidget {
  const _LyricFocusScale({
    required this.lineStartMs,
    required this.active,
    required this.disableAnimations,
    required this.child,
  });

  final int lineStartMs;
  final bool active;
  final bool disableAnimations;
  final Widget child;

  @override
  State<_LyricFocusScale> createState() => _LyricFocusScaleState();
}

class _LyricFocusScaleState extends State<_LyricFocusScale>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    value: widget.active ? 1 : 0,
  );
  Timer? _delayTimer;

  @override
  void didUpdateWidget(covariant _LyricFocusScale oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active == oldWidget.active &&
        widget.disableAnimations == oldWidget.disableAnimations) {
      return;
    }
    _driveToTarget();
  }

  void _driveToTarget() {
    _delayTimer?.cancel();
    _controller.stop();
    final target = widget.active ? 1.0 : 0.0;
    if (widget.disableAnimations) {
      _controller.value = target;
      return;
    }
    if (widget.active) {
      unawaited(
        _controller.animateTo(
          target,
          duration: _kLyricFocusInDuration,
          curve: _kLyricFocusCurve,
        ),
      );
      return;
    }
    _delayTimer = Timer(_kLyricFocusOutDelay, () {
      if (!mounted || widget.active) return;
      unawaited(
        _controller.animateTo(
          target,
          duration: _kLyricFocusOutDuration,
          curve: _kLyricFocusCurve,
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
        final scale = widget.disableAnimations
            ? (widget.active ? 1.0 : _kLyricInactiveScale)
            : _kLyricInactiveScale +
                  (1 - _kLyricInactiveScale) * _controller.value;
        return Transform.scale(
          key: ValueKey('lyric-focus-scale-${widget.lineStartMs}'),
          scale: scale,
          alignment: Alignment.centerLeft,
          child: child,
        );
      },
    );
  }
}
