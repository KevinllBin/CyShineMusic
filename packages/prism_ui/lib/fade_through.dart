import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

class _ChildEntry {
  _ChildEntry({
    required this.primaryController,
    required this.secondaryController,
    required this.transition,
    required this.widgetChild,
  });

  final AnimationController primaryController;

  final AnimationController secondaryController;

  Widget transition;

  Widget widgetChild;

  void dispose() {
    primaryController.dispose();
    secondaryController.dispose();
  }

  @override
  String toString() {
    return 'PageTransitionSwitcherEntry#${shortHash(this)}($widgetChild)';
  }
}

typedef PageTransitionSwitcherLayoutBuilder =
    Widget Function(List<Widget> entries);

typedef PageTransitionSwitcherTransitionBuilder =
    Widget Function(
      Widget child,
      Animation<double> primaryAnimation,
      Animation<double> secondaryAnimation,
    );

class PageTransitionSwitcher extends StatefulWidget {
  const PageTransitionSwitcher({
    super.key,
    this.duration = const Duration(milliseconds: 300),
    this.reverse = false,
    required this.transitionBuilder,
    this.layoutBuilder = defaultLayoutBuilder,
    this.child,
  });

  final Widget? child;

  final Duration duration;

  final bool reverse;

  final PageTransitionSwitcherTransitionBuilder transitionBuilder;

  final PageTransitionSwitcherLayoutBuilder layoutBuilder;

  static Widget defaultLayoutBuilder(List<Widget> entries) {
    return Stack(alignment: Alignment.center, children: entries);
  }

  @override
  State<PageTransitionSwitcher> createState() => _PageTransitionSwitcherState();
}

class _PageTransitionSwitcherState extends State<PageTransitionSwitcher>
    with TickerProviderStateMixin {
  final List<_ChildEntry> _activeEntries = <_ChildEntry>[];
  _ChildEntry? _currentEntry;
  int _childNumber = 0;

  @override
  void initState() {
    super.initState();
    _addEntryForNewChild(shouldAnimate: false);
  }

  @override
  void didUpdateWidget(PageTransitionSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);

    // If the transition builder changed, then update all of the old
    // transitions.
    if (widget.transitionBuilder != oldWidget.transitionBuilder) {
      _activeEntries.forEach(_updateTransitionForEntry);
    }

    final hasNewChild = widget.child != null;
    final hasOldChild = _currentEntry != null;
    if (hasNewChild != hasOldChild ||
        hasNewChild &&
            !Widget.canUpdate(widget.child!, _currentEntry!.widgetChild)) {
      // Child has changed, fade current entry out and add new entry.
      _childNumber += 1;
      _addEntryForNewChild(shouldAnimate: true);
    } else if (_currentEntry != null) {
      assert(hasOldChild && hasNewChild);
      assert(Widget.canUpdate(widget.child!, _currentEntry!.widgetChild));
      // Child has been updated. Make sure we update the child widget and
      // transition in _currentEntry even though we're not going to start a new
      // animation, but keep the key from the old transition so that we
      // update the transition instead of replacing it.
      _currentEntry!.widgetChild = widget.child!;
      _updateTransitionForEntry(_currentEntry!); // uses entry.widgetChild
    }
  }

  void _addEntryForNewChild({required bool shouldAnimate}) {
    assert(shouldAnimate || _currentEntry == null);
    if (_currentEntry != null) {
      assert(shouldAnimate);
      if (widget.reverse) {
        _currentEntry!.primaryController.reverse();
      } else {
        _currentEntry!.secondaryController.forward();
      }
      _currentEntry = null;
    }
    if (widget.child == null) {
      return;
    }
    final primaryController = AnimationController(
      duration: widget.duration,
      vsync: this,
    );
    final secondaryController = AnimationController(
      duration: widget.duration,
      vsync: this,
    );
    if (shouldAnimate) {
      if (widget.reverse) {
        primaryController.value = 1.0;
        secondaryController.value = 1.0;
        secondaryController.reverse();
      } else {
        primaryController.forward();
      }
    } else {
      assert(_activeEntries.isEmpty);
      primaryController.value = 1.0;
    }
    _currentEntry = _newEntry(
      child: widget.child!,
      primaryController: primaryController,
      secondaryController: secondaryController,
      builder: widget.transitionBuilder,
    );
    if (widget.reverse && _activeEntries.isNotEmpty) {
      // Add below old child.
      _activeEntries.insert(_activeEntries.length - 1, _currentEntry!);
    } else {
      // Add on top of old child.
      _activeEntries.add(_currentEntry!);
    }
  }

  _ChildEntry _newEntry({
    required Widget child,
    required PageTransitionSwitcherTransitionBuilder builder,
    required AnimationController primaryController,
    required AnimationController secondaryController,
  }) {
    final Widget transition = builder(
      child,
      primaryController,
      secondaryController,
    );
    final entry = _ChildEntry(
      widgetChild: child,
      transition: KeyedSubtree.wrap(transition, _childNumber),
      primaryController: primaryController,
      secondaryController: secondaryController,
    );
    secondaryController.addStatusListener((AnimationStatus status) {
      if (status == AnimationStatus.completed) {
        assert(mounted);
        assert(_activeEntries.contains(entry));
        setState(() {
          _activeEntries.remove(entry);
          entry.dispose();
        });
      }
    });
    primaryController.addStatusListener((AnimationStatus status) {
      if (status == AnimationStatus.dismissed) {
        assert(mounted);
        assert(_activeEntries.contains(entry));
        setState(() {
          _activeEntries.remove(entry);
          entry.dispose();
        });
      }
    });
    return entry;
  }

  void _updateTransitionForEntry(_ChildEntry entry) {
    final Widget transition = widget.transitionBuilder(
      entry.widgetChild,
      entry.primaryController,
      entry.secondaryController,
    );
    entry.transition = KeyedSubtree(
      key: entry.transition.key,
      child: transition,
    );
  }

  @override
  void dispose() {
    for (final _ChildEntry entry in _activeEntries) {
      entry.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.layoutBuilder(
      _activeEntries
          .map<Widget>((_ChildEntry entry) => entry.transition)
          .toList(),
    );
  }
}

class FadeThroughTransition extends StatelessWidget {
  const FadeThroughTransition({
    super.key,
    required this.animation,
    required this.secondaryAnimation,
    this.child,
  });

  final Animation<double> animation;

  final Animation<double> secondaryAnimation;

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return _ZoomedFadeInFadeOut(
      animation: animation,
      child: _ZoomedFadeInFadeOut(
        animation: ReverseAnimation(secondaryAnimation),
        child: child,
      ),
    );
  }
}

class _ZoomedFadeInFadeOut extends StatelessWidget {
  const _ZoomedFadeInFadeOut({required this.animation, this.child});

  final Animation<double> animation;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return DualTransitionBuilder(
      animation: animation,
      forwardBuilder:
          (BuildContext context, Animation<double> animation, Widget? child) {
            return _ZoomedFadeIn(animation: animation, child: child);
          },
      reverseBuilder:
          (BuildContext context, Animation<double> animation, Widget? child) {
            return _FadeOut(animation: animation, child: child);
          },
      child: child,
    );
  }
}

class _ZoomedFadeIn extends StatelessWidget {
  const _ZoomedFadeIn({this.child, required this.animation});

  final Widget? child;
  final Animation<double> animation;

  static final CurveTween _inCurve = CurveTween(
    curve: const Cubic(0.0, 0.0, 0.2, 1.0),
  );
  static final TweenSequence<double> _scaleIn =
      TweenSequence<double>(<TweenSequenceItem<double>>[
        TweenSequenceItem<double>(
          tween: ConstantTween<double>(0.92),
          weight: 6 / 20,
        ),
        TweenSequenceItem<double>(
          tween: Tween<double>(begin: 0.92, end: 1.0).chain(_inCurve),
          weight: 14 / 20,
        ),
      ]);
  static final TweenSequence<double> _fadeInOpacity =
      TweenSequence<double>(<TweenSequenceItem<double>>[
        TweenSequenceItem<double>(
          tween: ConstantTween<double>(0.0),
          weight: 6 / 20,
        ),
        TweenSequenceItem<double>(
          tween: Tween<double>(begin: 0.0, end: 1.0).chain(_inCurve),
          weight: 14 / 20,
        ),
      ]);

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeInOpacity.animate(animation),
      child: ScaleTransition(scale: _scaleIn.animate(animation), child: child),
    );
  }
}

class _FadeOut extends StatelessWidget {
  const _FadeOut({this.child, required this.animation});

  final Widget? child;
  final Animation<double> animation;

  static final CurveTween _outCurve = CurveTween(
    curve: const Cubic(0.4, 0.0, 1.0, 1.0),
  );
  static final TweenSequence<double> _fadeOutOpacity =
      TweenSequence<double>(<TweenSequenceItem<double>>[
        TweenSequenceItem<double>(
          tween: Tween<double>(begin: 1.0, end: 0.0).chain(_outCurve),
          weight: 6 / 20,
        ),
        TweenSequenceItem<double>(
          tween: ConstantTween<double>(0.0),
          weight: 14 / 20,
        ),
      ]);

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeOutOpacity.animate(animation),
      child: child,
    );
  }
}
