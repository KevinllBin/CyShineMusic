import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/ui/cover_image_source.dart';
import '../../../core/ui/cover_placeholder.dart';
import '../../../theme/app_motion.dart';
import '../discovery_controller.dart';

class DiscoveryPlaylistCover extends StatelessWidget {
  const DiscoveryPlaylistCover({
    super.key,
    required this.url,
    required this.size,
  });

  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final unavailable = CoverUnavailablePlaceholder(
      iconSize: (size * 0.9).clamp(28.0, 42.0),
    );
    final value = CoverImageSource.normalizeUrl(
      url,
      size: discoveryPlaylistArtworkSize,
    );
    if (value == null || value.isEmpty) return unavailable;
    return CachedNetworkImage(
      imageUrl: value,
      httpHeaders: CoverImageSource.headersFor(value),
      fit: BoxFit.cover,
      fadeInDuration: AppMotion.medium,
      fadeOutDuration: AppMotion.short,
      placeholder: (_, _) => const CoverLoadingSkeleton(),
      errorWidget: (_, _, _) => unavailable,
    );
  }
}
