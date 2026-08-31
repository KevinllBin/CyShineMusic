import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/settings_store.dart';
import '../../../core/ui/cover_image_source.dart';
import '../../../theme/app_theme.dart';
import '../player_controller.dart';
import '../flowing_light_background.dart';
import 'player_palette.dart';
import 'track_change_switcher.dart';

class ImmersiveBackground extends ConsumerWidget {
  const ImmersiveBackground({super.key, this.revealProgress});

  /// The shell's player reveal progress, forwarded to the backdrop so its
  /// motion can hold while the page is being dragged.
  final Animation<double>? revealProgress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cover = ref.watch(
      playerControllerProvider.select(
        (s) => (url: s.track?.coverUrl, bytes: s.track?.coverBytes),
      ),
    );
    final hasTrack = ref.watch(
      playerControllerProvider.select((s) => s.track != null),
    );
    final playing = ref.watch(
      playerControllerProvider.select((s) => s.playing),
    );
    final flowingLightEnabled = ref.watch(
      settingsProvider.select((s) => s.flowingLightEnabled),
    );
    final normalized = CoverImageSource.normalizeUrl(cover.url, size: 700);
    final scheme = Theme.of(context).colorScheme;
    final baseSurface = hasTrack ? playerSurface(context) : scheme.appSurface;
    final ImageProvider<Object>? imageProvider;
    if (cover.bytes != null && cover.bytes!.isNotEmpty) {
      final memoryProvider = MemoryImage(cover.bytes!);
      imageProvider = ResizeImage(memoryProvider, width: 192, height: 192);
    } else if (normalized != null && normalized.isNotEmpty) {
      final networkProvider = CachedNetworkImageProvider(
        normalized,
        headers: CoverImageSource.headersFor(normalized),
      );
      imageProvider = ResizeImage(networkProvider, width: 192, height: 192);
    } else {
      imageProvider = null;
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: baseSurface),
        TrackChangeSwitcher(
          // Keyed on whether there is a cover at all, not on which cover. Track
          // changes are cross-faded inside FlowingLightBackground, so keying
          // per track would re-slot it, throw away its previous-frame history,
          // and leave two composite pipelines running against each other for
          // the length of the transition.
          transitionKey: imageProvider != null,
          incomingOffset: Offset.zero,
          duration: const Duration(milliseconds: 500),
          expand: true,
          child: imageProvider == null
              ? const SizedBox.expand()
              : FlowingLightBackground(
                  imageProvider: imageProvider,
                  backgroundColor: baseSurface,
                  brightness: scheme.brightness,
                  running: flowingLightEnabled && playing,
                  revealProgress: revealProgress,
                ),
        ),
      ],
    );
  }
}
