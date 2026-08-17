import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/settings_store.dart';
import '../../../theme/app_motion.dart';
import '../lyric_parser.dart';
import '../player_controller.dart';

/// Blur applied directly to the previous and next lyric text. Increase this
/// value for a stronger effect; the active line always stays sharp.
const double miniLyricsInactiveBlurSigma = 0.45;

const double _miniLyricLineExtent = 22;
const int _miniLyricVisibleLineCount = 3;
const Duration _miniLyricScrollDuration = Duration(milliseconds: 380);
// Breathing room INSIDE the list viewport so the first/last row's blur halo
// fades out before reaching the viewport clip instead of being sliced flat
// against it. The panel padding below hands back the same amount, so text
// keeps its exact on-screen position and the window math is untouched:
// row i starts at bleed + i*extent, and the existing `windowStart * extent`
// scroll target leaves the top row exactly `bleed` inside the viewport.
const double _miniLyricBlurBleed = 4;

class MiniLyricsPanel extends ConsumerWidget {
  const MiniLyricsPanel({super.key, required this.onOpenLyrics});

  final VoidCallback onOpenLyrics;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(
      settingsProvider.select((settings) => settings.showMiniLyrics),
    );
    if (!enabled) return const SizedBox.shrink();
    final vm = ref.watch(
      playerControllerProvider.select(
        (state) => (
          lyrics: state.lyrics,
          activeIndex: state.lyricLoading || state.lyrics.isEmpty
              ? -1
              : state.lyrics.activeIndex(state.position),
        ),
      ),
    );
    if (vm.activeIndex < 0 || vm.lyrics.isEmpty) {
      return const SizedBox.shrink();
    }

    return Semantics(
      button: true,
      label: '打开歌词页面',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Material(
          key: const ValueKey('player-mini-lyrics-surface'),
          color: Colors.transparent,
          child: InkWell(
            key: const ValueKey('player-mini-lyrics'),
            onTap: onOpenLyrics,
            child: SizedBox(
              height: 84,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14 - _miniLyricBlurBleed,
                  vertical: 9 - _miniLyricBlurBleed,
                ),
                child: _MiniLyricsScroller(
                  lyrics: vm.lyrics,
                  activeIndex: vm.activeIndex,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniLyricsScroller extends StatefulWidget {
  const _MiniLyricsScroller({required this.lyrics, required this.activeIndex});

  final KaraokeLyrics lyrics;
  final int activeIndex;

  @override
  State<_MiniLyricsScroller> createState() => _MiniLyricsScrollerState();
}

class _MiniLyricsScrollerState extends State<_MiniLyricsScroller> {
  late final ScrollController _controller;
  late int _windowStart;
  int _scrollGeneration = 0;

  @override
  void initState() {
    super.initState();
    _windowStart = _resolveWindowStart();
    _controller = ScrollController(
      initialScrollOffset: _windowStart * _miniLyricLineExtent,
    );
  }

  @override
  void didUpdateWidget(covariant _MiniLyricsScroller oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextStart = _resolveWindowStart();
    final lyricsChanged = !identical(widget.lyrics, oldWidget.lyrics);
    if (!lyricsChanged && nextStart == _windowStart) return;
    _windowStart = nextStart;
    _scheduleScroll(animate: !lyricsChanged);
  }

  @override
  void dispose() {
    _scrollGeneration++;
    _controller.dispose();
    super.dispose();
  }

  int _resolveWindowStart() {
    final lineCount = widget.lyrics.lines.length;
    final maxStart = (lineCount - _miniLyricVisibleLineCount).clamp(
      0,
      lineCount,
    );
    return (widget.activeIndex - 1).clamp(0, maxStart);
  }

  void _scheduleScroll({required bool animate}) {
    final generation = ++_scrollGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          generation != _scrollGeneration ||
          !_controller.hasClients) {
        return;
      }
      final target = (_windowStart * _miniLyricLineExtent).clamp(
        0.0,
        _controller.position.maxScrollExtent,
      );
      if (!animate || MediaQuery.disableAnimationsOf(context)) {
        _controller.jumpTo(target);
        return;
      }
      unawaited(
        _controller.animateTo(
          target,
          duration: _miniLyricScrollDuration,
          curve: AppMotion.emphasized,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lines = widget.lyrics.lines;
    final blurDuration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : _miniLyricScrollDuration;
    return ListView.builder(
      key: const ValueKey('player-mini-lyrics-scroll'),
      controller: _controller,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(_miniLyricBlurBleed),
      itemExtent: _miniLyricLineExtent,
      // ignore: deprecated_member_use
      cacheExtent: 0,
      itemCount: lines.length,
      itemBuilder: (context, index) {
        final active = index == widget.activeIndex;
        final targetSigma = active ? 0.0 : miniLyricsInactiveBlurSigma;
        return TweenAnimationBuilder<double>(
          tween: Tween<double>(end: targetSigma),
          duration: blurDuration,
          curve: AppMotion.emphasized,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              lines[index].text,
              key: ValueKey('player-mini-lyric-line-$index'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: active
                    ? scheme.onSurface
                    : scheme.onSurfaceVariant.withValues(alpha: 0.72),
                fontSize: active ? 14 : 12.5,
                fontWeight: FontWeight.w400,
                height: 1.15,
              ),
            ),
          ),
          builder: (context, sigma, child) => ImageFiltered(
            key: ValueKey('player-mini-lyric-blur-$index'),
            // Decal so the blur halo fades past the text bounds instead of
            // clamp's hard seam at the glyph edges.
            imageFilter: ImageFilter.blur(
              sigmaX: sigma,
              sigmaY: sigma,
              tileMode: TileMode.decal,
            ),
            enabled: sigma > 0.05,
            child: child,
          ),
        );
      },
    );
  }
}
