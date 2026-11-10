import 'package:flutter/material.dart';

import '../../../core/models/enums.dart';
import '../../../theme/app_motion.dart';

/// Fades out, then lifts in the selected platform, with at most two live pages.
class DiscoverySourceTransition extends StatefulWidget {
  const DiscoverySourceTransition({
    super.key,
    required this.source,
    required this.child,
  });

  final MusicSource source;
  final Widget child;

  @override
  State<DiscoverySourceTransition> createState() =>
      _DiscoverySourceTransitionState();
}

class _DiscoverySourceTransitionState extends State<DiscoverySourceTransition>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
    value: 1,
  )..addStatusListener(_finish);
  late final _enterProgress = _controller.drive(
    CurveTween(curve: const Interval(0.32, 1, curve: AppMotion.emphasized)),
  );
  late final _exitProgress = _controller.drive(
    CurveTween(curve: const Interval(0, 0.32, curve: Curves.easeOut)),
  );
  late Widget _current = widget.child;
  Widget? _previous;
  double _exitStartOpacity = 1;
  double _exitOffset = 0;

  void _finish(AnimationStatus status) {
    if (status == AnimationStatus.completed && _previous != null) {
      setState(() => _previous = null);
    }
  }

  @override
  void didUpdateWidget(covariant DiscoverySourceTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source == widget.source) {
      _current = widget.child;
      return;
    }
    // During the first 70 ms the incoming page is still invisible. Keep fading
    // the visible outgoing page when another selection arrives in that phase.
    if (_previous != null && _enterProgress.value == 0) {
      _exitStartOpacity *= 1 - _exitProgress.value;
    } else {
      _previous = _current;
      _exitStartOpacity = _enterProgress.value;
      _exitOffset = 12 * (1 - _enterProgress.value);
    }
    _current = widget.child;
    if (MediaQuery.disableAnimationsOf(context) ||
        _previous?.key == _current.key) {
      _previous = null;
      _controller.value = 1;
    } else {
      _controller.forward(from: 0);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context) && _previous != null) {
      _previous = null;
      _controller.value = 1;
    }
  }

  Widget _page(Widget child, {required bool current}) {
    // Keep the keyed page subtree stable across frames. Only opacity and the
    // paint transform animate; nested card animations/pagination stay paused.
    return Positioned.fill(
      key: child.key,
      child: IgnorePointer(
        ignoring: !current || _previous != null,
        child: ExcludeSemantics(
          excluding: !current,
          child: TickerMode(
            enabled: current && _previous == null,
            child: FadeTransition(
              opacity: current
                  ? _enterProgress
                  : _exitProgress.drive(
                      Tween<double>(begin: _exitStartOpacity, end: 0),
                    ),
              child: AnimatedBuilder(
                animation: _enterProgress,
                builder: (context, child) => Transform.translate(
                  offset: Offset(
                    0,
                    current ? 12 * (1 - _enterProgress.value) : _exitOffset,
                  ),
                  child: child,
                ),
                child: RepaintBoundary(
                  child: ColoredBox(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final previous = _previous;
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (previous != null) _page(previous, current: false),
          _page(_current, current: true),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
