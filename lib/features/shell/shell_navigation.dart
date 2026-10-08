import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'shell_route_utils.dart';
import 'player_pull_scope.dart';
import 'tab_location_memory.dart';
import 'widgets/toolbar_metrics.dart';

/// Gives the shell's toolbar access to the retained tab navigators below it.
class ShellTabNavigationScope extends InheritedWidget {
  const ShellTabNavigationScope({
    super.key,
    required this.navigationKey,
    required super.child,
  });

  final GlobalKey<StatefulNavigationShellState> navigationKey;

  static StatefulNavigationShellState? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<ShellTabNavigationScope>()
      ?.navigationKey
      .currentState;

  @override
  bool updateShouldNotify(ShellTabNavigationScope oldWidget) =>
      navigationKey != oldWidget.navigationKey;
}

void navigateShellTo(
  BuildContext context,
  String currentLocation,
  String path,
) {
  _dismissTransientRoutes(context);
  if (currentLocation == path) return;
  if (path == '/player') {
    final pull = PlayerPullScope.maybeOf(context);
    if (pull != null) {
      pull.onOpen();
      return;
    }
  }
  context.go(
    path,
    extra: path == '/player'
        ? normalizedPlayerReturnLocation(currentLocation, '/songs')
        : null,
  );
}

void openPlayer(BuildContext context, {required String returnLocation}) {
  final pull = PlayerPullScope.maybeOf(context);
  if (pull != null) {
    FocusManager.instance.primaryFocus?.unfocus();
    pull.onOpen();
  } else {
    context.push('/player', extra: returnLocation);
  }
}

/// Both navigation styles use the original logical tab indices (0, 1, 3),
/// regardless of where their buttons are displayed.
void navigateToShellTab(
  BuildContext context,
  WidgetRef ref,
  String location,
  String routeLocation,
  String path,
) {
  _dismissTransientRoutes(context);
  final targetIndex = toolbarIndexFor(path);
  final switchesTab = toolbarIndexFor(location) != targetIndex;
  final navigation = ShellTabNavigationScope.maybeOf(context);
  if (switchesTab && navigation != null) {
    navigation.goBranch(targetIndex == 3 ? 2 : targetIndex);
    return;
  }
  final target = switchesTab
      ? (ref.read(tabLocationMemoryProvider)[targetIndex] ?? path)
      : path;
  if (target != routeLocation) {
    context.go(target, extra: switchesTab ? const ShellTabSwitch() : null);
  }
}

void _dismissTransientRoutes(BuildContext context) {
  FocusManager.instance.primaryFocus?.unfocus();
  Navigator.of(context, rootNavigator: true).popUntil((route) => route.isFirst);
}
