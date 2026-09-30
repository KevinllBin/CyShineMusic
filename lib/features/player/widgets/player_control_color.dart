import 'dart:async';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/cover_image_source.dart';
import '../../../theme/app_motion.dart';
import '../flow_palette.dart';
import '../player_controller.dart';
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

final _artworkAccentProvider = FutureProvider.autoDispose<Color?>((ref) async {
  final provider = ref.watch(playerArtworkProvider);
  if (provider == null) return null;
  final result = Completer<Color?>();
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
      try {
        final image = info.image;
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        if (data != null) {
          final palette = extractFlowPalette(
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
            image.width,
            image.height,
          );
          if (palette != FlowPalette.fallback) {
            accent = Color(palette.accentsArgb.first);
          }
        }
      } catch (_) {
        // Artwork failures should leave playback controls usable.
      } finally {
        info.dispose();
        if (!result.isCompleted) result.complete(accent);
      }
    },
    onError: (Object error, StackTrace? stackTrace) {
      if (!result.isCompleted) result.complete(null);
    },
  );
  ref.onDispose(() {
    // Release a pending request when a newer cover supersedes it.
    if (!result.isCompleted) result.complete(null);
  });
  stream.addListener(listener);
  try {
    return await result.future;
  } finally {
    stream.removeListener(listener);
  }
});

/// Keeps the cover's hue while using dark ink in light mode and pale ink in
/// dark mode. Only the transport controls opt into this color.
class PlayerControlColor extends ConsumerWidget {
  const PlayerControlColor({super.key, required this.builder});

  final Widget Function(BuildContext context, Color color) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artworkAccent = ref.watch(_artworkAccentProvider);
    // 新封面尚未就绪时沿用上次取色，避免换曲先闪回默认色。
    final accent = artworkAccent.hasError ? null : artworkAccent.valueOrNull;
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
