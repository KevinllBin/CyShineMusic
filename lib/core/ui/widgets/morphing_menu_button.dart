import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'morphing_menu_motion.dart';
import 'morphing_menu_surface.dart';

export 'morphing_menu_motion.dart' show MorphingMenuMotionStyle;

/// An action menu shared by toolbar and song-row overflow buttons.
class MorphingMenuAction {
  const MorphingMenuAction({
    required this.label,
    required this.leading,
    this.onSelected,
    this.danger = false,
    this.showLeading = true,
  });

  final String label;
  final Widget leading;
  final VoidCallback? onSelected;
  final bool danger;
  final bool showLeading;
}

class MorphingMenuButton extends StatefulWidget {
  const MorphingMenuButton({
    super.key,
    required this.tooltip,
    required this.actions,
    this.icon = Icons.more_vert_rounded,
    this.buttonBuilder,
    this.width = 280,
    this.motionStyle = MorphingMenuMotionStyle.list,
  }) : assert(width > 0);

  final String tooltip;
  final List<MorphingMenuAction> actions;
  final IconData icon;
  final Widget Function(Widget button)? buttonBuilder;
  final double width;
  final MorphingMenuMotionStyle motionStyle;

  @override
  State<MorphingMenuButton> createState() => _MorphingMenuButtonState();
}

class _MorphingMenuButtonState extends State<MorphingMenuButton> {
  _MorphingMenuRoute? _route;

  @override
  void didUpdateWidget(covariant MorphingMenuButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    final route = _route;
    if (route == null) return;
    // Toolbar state can change while the popup is open (playlist refresh).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && identical(_route, route) && route.isCurrent) {
        route.actions.value = widget.actions;
      }
    });
  }

  Future<void> _openMenu() async {
    if (widget.actions.isEmpty) return;
    final previous = _route;
    if (previous != null) {
      if (!previous.canReopen) return;
      // The barrier already lets taps through while reversing. Finish the
      // old route's settling tail so this tap can open a fresh menu now.
      previous.finishClosing();
    }
    final navigator = Navigator.of(context, rootNavigator: true);
    final anchorBox = context.findRenderObject();
    final overlayBox = navigator.overlay?.context.findRenderObject();
    if (anchorBox is! RenderBox ||
        overlayBox is! RenderBox ||
        !anchorBox.hasSize) {
      return;
    }

    // Relative to the root overlay, so car-display scaling applies once.
    final anchorRect =
        anchorBox.localToGlobal(Offset.zero, ancestor: overlayBox) &
        anchorBox.size;
    final route = _MorphingMenuRoute(
      currentAnchorRect: () {
        if (!anchorBox.attached || !overlayBox.attached) return anchorRect;
        return anchorBox.localToGlobal(Offset.zero, ancestor: overlayBox) &
            anchorBox.size;
      },
      label: widget.tooltip,
      initialActions: widget.actions,
      width: widget.width,
      motionStyle: widget.motionStyle,
      sourceIcon: widget.icon,
      themes: InheritedTheme.capture(from: context, to: navigator.context),
      reduceMotion: MediaQuery.disableAnimationsOf(context),
    );
    setState(() => _route = route);
    final action = await navigator.push<VoidCallback>(route);
    try {
      // Pop returns the selection as closing starts. Run it now while the
      // surface contracts, rather than waiting for the spring to settle.
      if (mounted) action?.call();
    } finally {
      await route.completed;
      // A quick reopen may already own the button when this route finishes.
      if (mounted && identical(_route, route)) {
        setState(() => _route = null);
      }
    }
  }

  @override
  void dispose() {
    final route = _route;
    if (route != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (route.isActive) route.navigator?.removeRoute(route);
      });
    }
    super.dispose();
  }

  /// How much of the source button the menu surface currently covers.
  ///
  /// A list menu dissolves at the end of its exit instead of collapsing into
  /// the button, so on the way out the button has to fade back in on the same
  /// curve the surface fades out — otherwise both ends are invisible while
  /// the rectangle dissolves.
  double _surfaceCover() {
    final route = _route;
    if (route == null) return 0;
    final frame = route.motion;
    final dissolving =
        widget.motionStyle == MorphingMenuMotionStyle.list &&
        route.animation?.status == AnimationStatus.reverse;
    return dissolving
        ? listMenuExitSurfaceOpacity(frame.size)
        : frame.surfaceOpacity;
  }

  @override
  Widget build(BuildContext context) {
    final button = IconButton(
      tooltip: widget.tooltip,
      onPressed: _openMenu,
      visualDensity: VisualDensity.compact,
      style: IconButton.styleFrom(
        backgroundColor: Colors.transparent,
        side: BorderSide.none,
        elevation: 0,
      ),
      icon: Icon(widget.icon, size: 21),
    );
    return SizedBox.square(
      dimension: 44,
      child: Semantics(
        expanded: _route != null,
        child: AnimatedBuilder(
          animation: _route?.animation ?? kAlwaysDismissedAnimation,
          builder: (context, child) => Opacity(
            opacity: 1 - _surfaceCover(),
            // Hide the whole source surface, including its border, shadow
            // and ink. Opacity keeps the hit area for a quick reopen.
            child: child,
          ),
          child:
              widget.buttonBuilder?.call(button) ??
              Material(type: MaterialType.transparency, child: button),
        ),
      ),
    );
  }
}

class _MorphingMenuRoute extends PopupRoute<VoidCallback> {
  _MorphingMenuRoute({
    required this.currentAnchorRect,
    required this.label,
    required List<MorphingMenuAction> initialActions,
    required this.width,
    required this.motionStyle,
    required this.sourceIcon,
    required this.themes,
    required this.reduceMotion,
  }) : actions = ValueNotifier(initialActions),
       super(
         requestFocus: true,
         traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
       );

  final Rect Function() currentAnchorRect;
  final String label;
  final double width;
  final MorphingMenuMotionStyle motionStyle;
  final IconData sourceIcon;
  final CapturedThemes themes;
  final bool reduceMotion;
  final ValueNotifier<List<MorphingMenuAction>> actions;
  MorphingMenuSimulation? _motionSimulation;
  bool _canReopen = false;

  bool get canReopen => _canReopen;

  void finishClosing() {
    if (canReopen && animation?.status == AnimationStatus.reverse) {
      controller?.value = 0;
    }
  }

  @override
  bool didPop(VoidCallback? result) {
    _canReopen = result == null;
    return super.didPop(result);
  }

  double get _elapsedSeconds =>
      (controller?.lastElapsedDuration?.inMicroseconds ?? 0) /
      Duration.microsecondsPerSecond;

  MorphingMenuFrame get motion {
    final simulation = _motionSimulation;
    if (simulation == null) {
      return (controller?.value ?? 0) == 1
          ? MorphingMenuFrame.open
          : MorphingMenuFrame.closed;
    }
    if (controller?.lastElapsedDuration == null) {
      return simulation.forward
          ? MorphingMenuFrame.open
          : MorphingMenuFrame.closed;
    }
    return simulation.frame(_elapsedSeconds);
  }

  @override
  Duration get transitionDuration =>
      reduceMotion ? Duration.zero : const Duration(milliseconds: 420);

  @override
  Duration get reverseTransitionDuration =>
      reduceMotion ? Duration.zero : const Duration(milliseconds: 400);

  @override
  Simulation? createSimulation({required bool forward}) {
    if (reduceMotion) return null;
    final previous = _motionSimulation;
    final elapsed = _elapsedSeconds;
    final moving = controller?.isAnimating ?? false;
    return _motionSimulation = MorphingMenuSimulation(
      forward: forward,
      from: motion,
      style: motionStyle,
      sizeVelocity: moving ? previous?.size.dx(elapsed) ?? 0 : 0,
      positionVelocity: moving ? previous?.position.dx(elapsed) ?? 0 : 0,
    );
  }

  @override
  bool get barrierDismissible => true;

  @override
  Color? get barrierColor => null;

  @override
  String get barrierLabel => '关闭菜单';

  void _dismiss([VoidCallback? action]) {
    if (isCurrent) navigator?.pop(action);
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return themes.wrap(
      Semantics(
        scopesRoute: true,
        namesRoute: true,
        explicitChildNodes: true,
        label: label,
        child: Focus(
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.escape) {
              _dismiss();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: ValueListenableBuilder<List<MorphingMenuAction>>(
            valueListenable: actions,
            builder: (context, entries, _) {
              final isToolbar = motionStyle == MorphingMenuMotionStyle.toolbar;
              final textScaler = MediaQuery.textScalerOf(context);
              final textStyle = Theme.of(context).textTheme.labelLarge
                  ?.copyWith(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    height: 1.35,
                  );
              final itemHeight = math.max(
                isToolbar ? 52.0 : 48.0,
                textScaler.scale(15) * 1.35 + (isToolbar ? 24 : 17),
              );
              var listMenuWidth = 200.0;
              if (!isToolbar) {
                for (final entry in entries) {
                  final painter = TextPainter(
                    text: TextSpan(text: entry.label, style: textStyle),
                    textDirection: Directionality.of(context),
                    textScaler: textScaler,
                    maxLines: 1,
                  )..layout();
                  listMenuWidth = math.max(
                    listMenuWidth,
                    painter.width + (entry.showLeading ? 60 : 28),
                  );
                }
              }
              final firstEnabled = entries.indexWhere(
                (entry) => entry.onSelected != null,
              );
              return MorphingMenuSurface(
                anchorRect: currentAnchorRect,
                animation: animation,
                motion: () => motion,
                motionStyle: motionStyle,
                preferredWidth: isToolbar
                    ? width
                    : math.min(width, math.min(280, listMenuWidth)),
                sourceIcon: sourceIcon,
                itemHeight: itemHeight,
                children: [
                  for (var index = 0; index < entries.length; index++)
                    _MorphingMenuTile(
                      action: entries[index],
                      height: itemHeight,
                      autofocus: index == firstEnabled,
                      onSelected: () => _dismiss(entries[index].onSelected),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    actions.dispose();
    super.dispose();
  }
}

class _MorphingMenuTile extends StatelessWidget {
  const _MorphingMenuTile({
    required this.action,
    required this.height,
    required this.autofocus,
    required this.onSelected,
  });

  final MorphingMenuAction action;
  final double height;
  final bool autofocus;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = action.onSelected != null;
    final foreground = (action.danger ? scheme.error : scheme.onSurface)
        .withValues(alpha: enabled ? 1 : 0.38);
    return Semantics(
      button: true,
      enabled: enabled,
      child: SizedBox(
        height: height,
        child: InkWell(
          autofocus: autofocus,
          onTap: enabled ? onSelected : null,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                if (action.showLeading) ...[
                  IconTheme.merge(
                    data: IconThemeData(color: foreground, size: 20),
                    child: action.leading,
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Text(
                    action.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: foreground,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
