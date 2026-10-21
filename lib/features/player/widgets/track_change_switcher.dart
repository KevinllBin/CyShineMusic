import 'package:flutter/material.dart';

import '../../../theme/app_motion.dart';

class TrackChangeSwitcher extends StatelessWidget {
  const TrackChangeSwitcher({
    super.key,
    required this.transitionKey,
    required this.child,
    this.alignment = Alignment.center,
    this.incomingOffset = const Offset(0.16, 0),
    this.scaleBegin = 1,
    this.expand = false,
    this.duration,
    this.fade = true,
  });

  final Object transitionKey;
  final Widget child;
  final AlignmentGeometry alignment;
  final Offset incomingOffset;
  final double scaleBegin;
  final bool expand;
  final Duration? duration;
  final bool fade;

  @override
  Widget build(BuildContext context) {
    final childKey = ValueKey<Object>(transitionKey);
    final resolvedDuration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : duration ?? AppMotion.long;
    return AnimatedSwitcher(
      duration: resolvedDuration,
      reverseDuration: resolvedDuration,
      switchInCurve: const Cubic(0.4, 0, 0.2, 1),
      switchOutCurve: const Cubic(0.4, 0, 0.2, 1),
      layoutBuilder: (currentChild, previousChildren) {
        return TrackChangeLayout(
          alignment: alignment,
          expand: expand,
          currentChild: currentChild,
          previousChildren: previousChildren,
        );
      },
      transitionBuilder: (transitionChild, animation) {
        final incoming = transitionChild.key == childKey;
        final slideBegin = incoming
            ? incomingOffset
            : Offset(-incomingOffset.dx, -incomingOffset.dy);
        Widget animated = SlideTransition(
          position: Tween<Offset>(
            begin: slideBegin,
            end: Offset.zero,
          ).animate(animation),
          child: transitionChild,
        );
        if (scaleBegin != 1) {
          animated = ScaleTransition(
            scale: Tween<double>(begin: scaleBegin, end: 1).animate(animation),
            child: animated,
          );
        }
        return fade
            ? FadeTransition(opacity: animation, child: animated)
            : animated;
      },
      child: KeyedSubtree(key: childKey, child: child),
    );
  }
}

/// Keeps the outgoing entry chosen at the start of a handoff. An interrupted
/// short-lived entry can finish before an older one inside AnimatedSwitcher;
/// choosing `previousChildren.last` every frame would bring that older one back.
class TrackChangeLayout extends StatefulWidget {
  const TrackChangeLayout({
    super.key,
    required this.currentChild,
    required this.previousChildren,
    this.alignment = Alignment.center,
    this.expand = false,
  });

  final Widget? currentChild;
  final List<Widget> previousChildren;
  final AlignmentGeometry alignment;
  final bool expand;

  @override
  State<TrackChangeLayout> createState() => _TrackChangeLayoutState();
}

class _TrackChangeLayoutState extends State<TrackChangeLayout> {
  Key? _outgoingKey;

  @override
  void initState() {
    super.initState();
    _outgoingKey = widget.previousChildren.lastOrNull?.key;
  }

  @override
  void didUpdateWidget(covariant TrackChangeLayout oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentChild?.key != oldWidget.currentChild?.key) {
      _outgoingKey = widget.previousChildren.lastOrNull?.key;
    }
  }

  @override
  Widget build(BuildContext context) {
    final outgoing = widget.previousChildren
        .where((child) => child.key == _outgoingKey)
        .firstOrNull;
    return Stack(
      alignment: widget.alignment,
      fit: widget.expand ? StackFit.expand : StackFit.loose,
      clipBehavior: Clip.none,
      children: [
        if (outgoing != null)
          IgnorePointer(
            child: ExcludeSemantics(
              child: TickerMode(enabled: false, child: outgoing),
            ),
          ),
        ?widget.currentChild,
      ],
    );
  }
}
