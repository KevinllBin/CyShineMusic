import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/cover_image_source.dart';
import '../../../theme/app_motion.dart';
import '../artwork_colors.dart';
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

// AppShell keeps this alive, so selecting a song prepares its colors even
// before the player page is mounted or opened.
final playerArtworkColorsProvider = FutureProvider.autoDispose<ArtworkColors?>((
  ref,
) async {
  final provider = ref.watch(playerArtworkProvider);
  if (provider == null) return null;
  return loadArtworkColors(provider);
});

final playerLyricInkProvider = Provider.autoDispose<Color?>((ref) {
  final colors = ref.watch(playerArtworkColorsProvider);
  return colors.hasError ? null : colors.valueOrNull?.lyricInk;
});

/// Keeps the cover's hue while using dark ink in light mode and pale ink in
/// dark mode. Only the transport controls opt into this color.
class PlayerControlColor extends ConsumerWidget {
  const PlayerControlColor({super.key, required this.builder});

  final Widget Function(BuildContext context, Color color) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artworkColors = ref.watch(playerArtworkColorsProvider);
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
      tween: ColorTween(begin: color, end: color),
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : AppMotion.long,
      curve: AppMotion.emphasized,
      builder: (context, value, _) => builder(context, value ?? fallback),
    );
  }
}
