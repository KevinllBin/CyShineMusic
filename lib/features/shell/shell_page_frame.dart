import '../../theme/app_theme.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/settings_store.dart';
import 'shell_bottom_area.dart';
import 'shell_route_utils.dart';
import 'widgets/shell_header.dart';
import 'widgets/scrolling_page_header.dart';

/// Each retained route owns its header, so changing tabs cannot resize another
/// tab's scroll viewport and clamp its saved position.
class ShellPageFrame extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final area = ShellBottomArea.maybeOf(context);
    // Floating controls own their system inset. The page can draw to the
    // screen edge; ShellBottomArea pads scrollables to clear those controls.
    final bottomPadding = area?.navigationMode == AppNavigationMode.native
        ? area!.extent > 0
              ? area.extent - area.floatingExtent
              : MediaQuery.paddingOf(context).bottom
        : 0.0;
    final hidesHeader =
        isDiscoveryLocation(location) ||
        isImmersivePlaylistDetailLocation(location);
    return ColoredBox(
      color: location.startsWith('/settings')
          ? Theme.of(context).colorScheme.appSettingsSurface
          : Colors.transparent,
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomPadding),
        child: hidesHeader
            ? child
            : ScrollingPageHeader(
                key: ValueKey(location),
                topInset: MediaQuery.viewPaddingOf(context).top + 72,
                headerBuilder: (context, offset) => ShellHeader(
                  location: location,
                  playlistBackLocation: playlistBackLocation,
                  scrollOffset: offset,
                  floating: true,
                ),
                child: child,
              ),
      ),
    );
  }
}
