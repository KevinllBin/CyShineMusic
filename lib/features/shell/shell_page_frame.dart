import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/storage/settings_store.dart';
import 'shell_bottom_area.dart';
import 'shell_route_utils.dart';
import 'widgets/shell_header.dart';

/// Each retained route owns its header, so changing tabs cannot resize another
/// tab's scroll viewport and clamp its saved position.
class ShellPageFrame extends StatelessWidget {
  const ShellPageFrame({
    super.key,
    required this.location,
    required this.playlistBackLocation,
    required this.child,
  });

  final String location;
  final String playlistBackLocation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final area = ShellBottomArea.maybeOf(context);
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    final bottomPadding = area?.navigationMode == AppNavigationMode.native
        ? area!.extent > 0
              ? area.extent - area.floatingExtent
              : MediaQuery.paddingOf(context).bottom
        : math.max(bottomInset, 12.0);
    final hidesHeader =
        isDiscoveryLocation(location) ||
        isImmersivePlaylistDetailLocation(location);
    return Padding(
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: Column(
        children: [
          if (!hidesHeader)
            ShellHeader(
              location: location,
              playlistBackLocation: playlistBackLocation,
            ),
          Expanded(child: child),
        ],
      ),
    );
  }
}
