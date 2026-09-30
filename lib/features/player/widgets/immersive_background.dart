import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/settings_store.dart';
import '../../../theme/app_theme.dart';
import '../player_controller.dart';
import '../flowing_light_background.dart';
import 'player_palette.dart';
import 'player_control_color.dart';
import 'track_change_switcher.dart';

class ImmersiveBackground extends ConsumerWidget {
  const ImmersiveBackground({super.key, this.revealProgress});

  /// The shell's player reveal progress, forwarded to the backdrop so its
  /// motion can hold while the page is being dragged.
  final Animation<double>? revealProgress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final imageProvider = ref.watch(playerArtworkProvider);
    final hasTrack = ref.watch(
      playerControllerProvider.select((s) => s.track != null),
    );
    final playing = ref.watch(
      playerControllerProvider.select((s) => s.playing),
    );
    final flowingLightEnabled = ref.watch(
      settingsProvider.select((s) => s.flowingLightEnabled),
    );
    final scheme = Theme.of(context).colorScheme;
    final baseSurface = hasTrack ? playerSurface(context) : scheme.appSurface;
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
