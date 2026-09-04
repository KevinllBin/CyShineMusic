import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/ui/cover_image_source.dart';
import '../../../theme/app_motion.dart';

class LeaderboardArtwork extends StatelessWidget {
  const LeaderboardArtwork({
    super.key,
    required this.name,
    required this.index,
    this.coverUrl,
  });

  final String name;
  final int index;
  final String? coverUrl;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = switch (index % 4) {
      0 => [scheme.primaryContainer, scheme.primary],
      1 => [scheme.tertiaryContainer, scheme.tertiary],
      2 => [scheme.secondaryContainer, scheme.secondary],
      _ => [scheme.surfaceContainerHighest, scheme.primary],
    };
    final normalized = CoverImageSource.normalizeUrl(coverUrl, size: 640);
    final fallback = _FallbackArtwork(
      name: name,
      colors: colors,
      foreground: scheme.onPrimaryContainer,
    );
    if (normalized == null) return fallback;
    return CachedNetworkImage(
      imageUrl: normalized,
      httpHeaders: CoverImageSource.headersFor(normalized),
      fit: BoxFit.cover,
      fadeInDuration: AppMotion.medium,
      fadeOutDuration: AppMotion.short,
      placeholder: (_, _) => fallback,
      errorWidget: (_, _, _) => fallback,
    );
  }
}

class _FallbackArtwork extends StatelessWidget {
  const _FallbackArtwork({
    required this.name,
    required this.colors,
    required this.foreground,
  });

  final String name;
  final List<Color> colors;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            right: -18,
            bottom: -24,
            child: Icon(
              Icons.equalizer_rounded,
              size: 94,
              color: foreground.withValues(alpha: 0.12),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  'TOP',
                  style: TextStyle(
                    color: foreground.withValues(alpha: 0.72),
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 16,
                    height: 1.12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
