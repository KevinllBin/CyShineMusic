import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/cover_image_source.dart';
import '../../../theme/app_motion.dart';
import '../flow_palette.dart';
import '../player_controller.dart';
import 'lyric_ink.dart';
import 'player_palette.dart';

// Share the backdrop's resized image cache entry, including local artwork.
final playerArtworkProvider = Provider<ImageProvider<Object>?>((ref) {
  final cover = ref.watch(
    playerControllerProvider.select(
      (s) => (url: s.track?.coverUrl, bytes: s.track?.coverBytes),
    ),
  );
  final bytes = cover.bytes;
  if (bytes != null && bytes.isNotEmpty) {
    return ResizeImage(MemoryImage(bytes), width: 192, height: 192);
  }
  final url = CoverImageSource.normalizeUrl(cover.url, size: 700);
  if (url == null || url.isEmpty) return null;
  return ResizeImage(
    CachedNetworkImageProvider(url, headers: CoverImageSource.headersFor(url)),
    width: 192,
    height: 192,
  );
});

typedef _ArtworkColors = ({Color? accent, Color? lyricInk});
const _emptyArtworkColors = (accent: null, lyricInk: null);
typedef _ArtworkPixels = ({Uint8List rgba, int width, int height});

// Only pixel bytes cross the isolate boundary; image handles stay on the UI
// isolate. In particular, the lyric-ink histogram must not block reveal frames.
_ArtworkColors _extractArtworkColors(_ArtworkPixels pixels) {
  final palette = extractFlowPalette(pixels.rgba, pixels.width, pixels.height);
  return (
    accent: palette == FlowPalette.fallback
        ? null
        : Color(palette.accentsArgb.first),
    lyricInk: extractLyricInk(pixels.rgba),
  );
}

final _artworkColorsProvider = FutureProvider.autoDispose<_ArtworkColors>((
  ref,
) async {
  final provider = ref.watch(playerArtworkProvider);
  if (provider == null) return _emptyArtworkColors;
  final result = Completer<_ArtworkColors>();
  final stream = provider.resolve(ImageConfiguration.empty);
  var sampling = false;
  final listener = ImageStreamListener(
    (info, _) async {
      if (sampling || result.isCompleted) {
        info.dispose();
        return;
      }
      sampling = true;
      Color? accent;
      Color? lyricInk;
      try {
        final image = info.image;
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        if (data != null && !result.isCompleted) {
          final pixels = data.buffer.asUint8List(
            data.offsetInBytes,
            data.lengthInBytes,
          );
          final input = (
            rgba: pixels,
            width: image.width,
            height: image.height,
          );
          // Tiny placeholders cost less to sample than to send to an isolate.
          final colors = pixels.length <= 32 * 32 * 4
              ? _extractArtworkColors(input)
              : await compute(
                  _extractArtworkColors,
                  input,
                  debugLabel: 'player-artwork-colors',
                );
          accent = colors.accent;
          lyricInk = colors.lyricInk;
        }
      } catch (_) {
        // Artwork failures should leave playback controls usable.
      } finally {
        info.dispose();
        if (!result.isCompleted) {
          result.complete((accent: accent, lyricInk: lyricInk));
        }
      }
    },
    onError: (Object error, StackTrace? stackTrace) {
      if (!result.isCompleted) result.complete(_emptyArtworkColors);
    },
  );
  ref.onDispose(() {
    // Release a pending request when a newer cover supersedes it.
    if (!result.isCompleted) result.complete(_emptyArtworkColors);
  });
  stream.addListener(listener);
  try {
    return await result.future;
  } finally {
    stream.removeListener(listener);
  }
});

final playerLyricInkProvider = Provider.autoDispose<Color?>((ref) {
  final colors = ref.watch(_artworkColorsProvider);
  return colors.hasError ? null : colors.valueOrNull?.lyricInk;
});

/// Keeps the cover's hue while using dark ink in light mode and pale ink in
/// dark mode. Only the transport controls opt into this color.
class PlayerControlColor extends ConsumerWidget {
  const PlayerControlColor({super.key, required this.builder});

  final Widget Function(BuildContext context, Color color) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artworkColors = ref.watch(_artworkColorsProvider);
    // 新封面尚未就绪时沿用上次取色，避免换曲先闪回默认色。
    final accent = artworkColors.hasError
        ? null
        : artworkColors.valueOrNull?.accent;
    final fallback = playerInk(context);
    var color = fallback;
    if (accent != null) {
      final hsl = HSLColor.fromColor(accent);
      // The flow palette gives neutral artwork a small artificial saturation.
      // Keep genuinely monochrome covers neutral instead of tinting them red.
      if (hsl.saturation > 0.22) {
        final dark = Theme.of(context).brightness == Brightness.dark;
        color = hsl
            .withSaturation(hsl.saturation.clamp(0.35, 0.75))
            // 略收紧浅色明度，为高亮黄色及队列角标保留对比度余量。
            .withLightness(dark ? 0.82 : 0.23)
            .toColor();
      }
    }
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(begin: fallback, end: color),
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : AppMotion.long,
      curve: AppMotion.emphasized,
      builder: (context, value, _) => builder(context, value ?? fallback),
    );
  }
}
