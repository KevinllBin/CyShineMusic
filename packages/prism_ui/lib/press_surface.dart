import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:prism_ui/card_surface.dart';
import 'package:prism_ui/context.dart';
import 'package:prism_ui/focus.dart';
import 'package:prism_ui/press_sparkle.dart';
import 'package:prism_ui/surface.dart';
import 'package:prism_ui/theme_data.dart';

/// A surface that answers a press with ink or a tint, rings
/// itself when a key or remote moves focus to it, and eases between fills.
/// See Press in `.agents/surfaces.md`.
class PressSurface extends StatefulWidget {
  const PressSurface({
    super.key,
    required this.fill,
    required this.shape,
    this.look = PressLook.ink,
    this.side = BorderSide.none,
    this.ringColor,
    this.ringStandsOff = false,
    this.foreground,
    this.inkColor,
    this.iconSize,
    this.textStyle,
    this.padding = EdgeInsets.zero,
    this.minimum = const BoxConstraints(),
    this.tapTarget = Size.zero,
    this.onPressed,
    this.inert = false,
    this.selected = false,
    this.statesController,
    this.reportsHover = false,
    this.showsHover = true,
    this.onKeyEvent,
    this.childFills = false,
    this.clipsChild = false,
    required this.child,
  });

  final Color fill;
  final OutlinedBorder shape;
  final PressLook look;

  /// Drawn round [shape] whenever the focus ring is not.
  final BorderSide side;
  final Color? ringColor;
  final bool ringStandsOff;

  /// Colors icons, and text in [textStyle], easing along with [fill].
  final Color? foreground;

  /// The ink's content color where [foreground] is not the content's.
  final Color? inkColor;
  final double? iconSize;
  final TextStyle? textStyle;
  final EdgeInsets padding;
  final BoxConstraints minimum;
  final Size tapTarget;
  final VoidCallback? onPressed;

  /// Ignores presses in the enabled colors, so toggling it animates nothing.
  final bool inert;
  final bool selected;
  final WidgetStatesController? statesController;

  /// Whether a hover reaches [statesController].
  final bool reportsHover;

  /// Whether a pointer resting on the surface shades it. A surface that shows
  /// no press leaves the hover to its owner as well.
  final bool showsHover;
  final FocusOnKeyEventCallback? onKeyEvent;
  final bool childFills;
  final bool clipsChild;
  final Widget child;

  @override
  State<PressSurface> createState() => _PressSurfaceState();
}

typedef _Look = ({Color fill, BorderSide side, Color? foreground});

class _PressSurfaceState extends State<PressSurface>
    with TickerProviderStateMixin {
  // UIScrollView holds a touch this long before a cell highlights.
  static const _revealDelay = Duration(milliseconds: 150);
  static const _lookDuration = Duration(milliseconds: 200);
  static const _tintRelease = Duration(milliseconds: 250);
  static const _inkFade = Duration(milliseconds: 200);

  late final _tap = _PressTapRecognizer(debugOwner: this)
    ..onTapDown = _handleTapDown
    ..onTap = _handleTap
    ..onRejected = _cancelPress;
  late final _actions = <Type, Action<Intent>>{
    ActivateIntent: CallbackAction<ActivateIntent>(
      onInvoke: (_) => _activate(),
    ),
    ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(
      onInvoke: (_) => _activate(),
    ),
  };
  final _sparkles = PressSparkles();
  bool _inking = false;
  bool _inkHeld = false;
  AnimationController? _press;
  AnimationController? _lookMotion;
  CurvedAnimation? _lookCurve;
  _Look? _look;
  _Look? _previousLook;
  ColorScheme? _colorScheme;
  bool _themeChanged = false;
  int? _pointer;
  Timer? _reveal;
  bool _focused = false;
  bool _watchingKeys = false;

  ValueListenable<TickerModeData>? _tickerMode;

  bool get _enabled => widget.onPressed != null && !widget.inert;

  @override
  void initState() {
    super.initState();
    widget.statesController?.update(WidgetState.disabled, !_enabled);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scheme = Theme.of(context).colorScheme;
    if (_colorScheme != null && _colorScheme != scheme) _themeChanged = true;
    _colorScheme = scheme;
    final tickerMode = TickerMode.getValuesNotifier(context);
    if (tickerMode != _tickerMode) {
      _tickerMode?.removeListener(_dropSparklesWhenHidden);
      _tickerMode = tickerMode..addListener(_dropSparklesWhenHidden);
    }
  }

  // A covered page's sparkle would freeze midway and resume on its return.
  void _dropSparklesWhenHidden() {
    if (!_tickerMode!.value.enabled) {
      _sparkles.clear();
    }
  }

  @override
  void didUpdateWidget(PressSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_enabled && (_reveal != null || (_press?.value ?? 0) > 0)) {
      _cancelPress();
    }
    final states = widget.statesController;
    if (states != null && states != oldWidget.statesController) {
      states
        ..update(WidgetState.pressed, (_press?.value ?? 0) > 0)
        ..update(WidgetState.focused, _focused);
    }
    states?.update(WidgetState.disabled, !_enabled);
  }

  @override
  void dispose() {
    _reveal?.cancel();
    _stopWatchingKeys();
    _tickerMode?.removeListener(_dropSparklesWhenHidden);
    _tap
      ..onRejected = null
      ..dispose();
    _sparkles.dispose();
    _press?.dispose();
    _lookCurve?.dispose();
    _lookMotion?.dispose();
    super.dispose();
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (_pointer != null || !_tap.isPointerAllowed(event)) {
      return;
    }
    _pointer = event.pointer;
    _tap.addPointer(event);
    _inking = widget.look == PressLook.ink;
    if (_inking) {
      if (event.kind == PointerDeviceKind.mouse) {
        _fadeInInk();
      }
      return;
    }
    if (_inScrollView()) {
      _reveal = Timer(_revealDelay, _showPress);
    } else {
      _showPress();
    }
  }

  void _handlePointerEnd(PointerEvent event) {
    if (event.pointer == _pointer) {
      _pointer = null;
    }
  }

  // UIScrollView holds a touch back, so a quick tap shows no press, only where
  // it can scroll, which is where a Scrollable drags.
  bool _inScrollView() {
    for (
      var scrollable = context.findAncestorStateOfType<ScrollableState>();
      scrollable != null;
      scrollable = scrollable.context.findAncestorStateOfType<ScrollableState>()
    ) {
      final position = scrollable.position;
      if (position.hasContentDimensions &&
          position.physics.shouldAcceptUserOffset(position)) {
        return true;
      }
    }
    return false;
  }

  void _handleTapDown(TapDownDetails details) {
    if (!_inking) {
      return;
    }
    if (_sparkling) {
      _sparkles.start(
        details.localPosition,
        vsync: this,
        timing: context.motionDuration,
      );
    }
    _fadeInInk();
  }

  bool get _sparkling => Theme.of(context).platform == TargetPlatform.android;

  void _fadeInInk() {
    if (_inkHeld) {
      return;
    }
    _inkHeld = true;
    if (_press == null) {
      setState(() => _press = AnimationController(vsync: this));
    }
    _press!.animateTo(1, duration: context.motionDuration(_inkFade));
    widget.statesController?.update(WidgetState.pressed, true);
  }

  void _handleTap() {
    _releasePress();
    _invoke();
  }

  void _activate() {
    if (!_enabled) {
      return;
    }
    if (widget.look == PressLook.ink && _sparkling) {
      _sparkles.start(null, vsync: this, timing: context.motionDuration);
    } else {
      _showPress();
      _releasePress();
    }
    _invoke();
  }

  void _invoke() {
    if (!_enabled) {
      return;
    }
    Feedback.forTap(context);
    widget.onPressed?.call();
  }

  void _showPress() {
    _reveal = null;
    final press = _press;
    if (press == null) {
      setState(() => _press = AnimationController(vsync: this, value: 1));
    } else {
      press.value = 1;
    }
    widget.statesController?.update(WidgetState.pressed, true);
  }

  void _releasePress() {
    _inkHeld = false;
    _reveal?.cancel();
    _reveal = null;
    final press = _press;
    if (press == null || press.value == 0) {
      press?.stop();
      widget.statesController?.update(WidgetState.pressed, false);
      return;
    }
    if (widget.look == PressLook.none) {
      _cancelPress();
      return;
    }
    final ink = widget.look == PressLook.ink;
    press
        .animateTo(
          0,
          duration: context.motionDuration(ink ? _inkFade : _tintRelease),
          curve: ink ? Curves.linear : Curves.easeInOut,
        )
        .whenCompleteOrCancel(() {
          if (mounted && press.value == 0) {
            widget.statesController?.update(WidgetState.pressed, false);
          }
        });
  }

  void _cancelPress() {
    if (widget.look == PressLook.ink) {
      _releasePress();
      return;
    }
    _reveal?.cancel();
    _reveal = null;
    _press?.value = 0;
    widget.statesController?.update(WidgetState.pressed, false);
  }

  void _handleFocusChange(bool focused) {
    widget.statesController?.update(WidgetState.focused, focused);
    if (focused && !_watchingKeys) {
      FocusMovedByKey.instance.addListener(_handleKeyFocus);
      _watchingKeys = true;
    } else if (!focused) {
      _stopWatchingKeys();
    }
    setState(() => _focused = focused);
  }

  void _handleKeyFocus() => setState(() {});

  void _handleHover(bool hovered) {
    widget.statesController?.update(WidgetState.hovered, hovered && _enabled);
  }

  void _stopWatchingKeys() {
    if (_watchingKeys) {
      FocusMovedByKey.instance.removeListener(_handleKeyFocus);
      _watchingKeys = false;
    }
  }

  BorderSide _sideOf(ColorScheme colorScheme) {
    final ringed =
        _focused &&
        (RemoteFocusAdapter.isEnabledOf(context) ||
            FocusMovedByKey.instance.value);
    if (!ringed) {
      return widget.side;
    }
    final side = focusRingSide(colorScheme, standsOff: widget.ringStandsOff);
    return switch (widget.ringColor) {
      final color? => side.copyWith(color: color),
      null => side,
    };
  }

  void _moveLook(_Look look) {
    final current = _look;
    _look = look;
    if (_themeChanged) {
      // A covered page's muted ticker must not resume a light-to-dark tween
      // when it becomes visible again. Press/selection changes still animate.
      _themeChanged = false;
      _previousLook = null;
      _lookMotion?.stop();
      return;
    }
    if (current == null || current == look) {
      return;
    }
    final from = _previousLook ?? current;
    final progress = _lookCurve?.value ?? 1;
    _previousLook = (
      fill: Color.lerp(from.fill, current.fill, progress)!,
      side: BorderSide.lerp(from.side, current.side, progress),
      foreground: Color.lerp(from.foreground, current.foreground, progress),
    );
    final motion = _lookMotion ??= AnimationController(vsync: this);
    _lookCurve ??= CurvedAnimation(parent: motion, curve: Curves.fastOutSlowIn);
    motion
      ..duration = context.motionDuration(_lookDuration)
      ..forward(from: 0);
  }

  // As faint as the sidebar's hover: iOS shows none, a desktop pointer expects
  // one.
  static const _hoverAlpha = 0.04;

  static const _inkAlpha = 0.1;

  bool _canRequestFocus(BuildContext context) =>
      _enabled ||
      MediaQuery.maybeNavigationModeOf(context) == NavigationMode.directional;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    _tap.gestureSettings = MediaQuery.maybeGestureSettingsOf(context);
    _moveLook((
      fill: widget.fill,
      side: _sideOf(colorScheme),
      foreground: widget.foreground,
    ));
    final look = _look!;
    final previousLook = _previousLook ?? look;
    final transition = _lookCurve ?? kAlwaysCompleteAnimation;
    return CardSurface(
      shape: widget.shape,
      fill: look.fill,
      previousFill: previousLook.fill,
      side: look.side,
      previousSide: previousLook.side,
      transition: transition,
      pressed: _press ?? kAlwaysDismissedAnimation,
      hover: widget.showsHover && widget.look != PressLook.none
          ? colorScheme.onSurface.withValues(alpha: _hoverAlpha)
          : const Color(0x00000000),
      sparkles: _sparkles,
      inkColor: (widget.inkColor ?? widget.foreground ?? colorScheme.onSurface)
          .withValues(alpha: _inkAlpha),
      look: widget.look,
      brightness: colorScheme.brightness,
      padding: widget.padding,
      minimum: widget.minimum,
      tapTarget: widget.tapTarget,
      interactive: _enabled,
      selected: widget.selected,
      childFills: widget.childFills,
      clipsChild: widget.clipsChild,
      onTap: _activate,
      onPointerDown: _enabled ? _handlePointerDown : null,
      onPointerEnd: _handlePointerEnd,
      onHover: widget.reportsHover ? _handleHover : null,
      child: Actions(
        actions: _actions,
        child: Focus(
          canRequestFocus: _canRequestFocus(context),
          onFocusChange: _handleFocusChange,
          onKeyEvent: widget.onKeyEvent,
          child: _themedContent(look, previousLook, transition),
        ),
      ),
    );
  }

  Widget _themedContent(
    _Look look,
    _Look previousLook,
    Animation<double> transition,
  ) {
    final foreground = look.foreground;
    if (foreground == null &&
        widget.iconSize == null &&
        widget.textStyle == null) {
      return widget.child;
    }
    return ListenableBuilder(
      listenable: transition,
      builder: (context, child) {
        final color = Color.lerp(
          previousLook.foreground,
          foreground,
          transition.value,
        );
        final content = IconTheme.merge(
          data: IconThemeData(color: color, size: widget.iconSize),
          child: child!,
        );
        return switch (widget.textStyle) {
          final textStyle? => DefaultTextStyle(
            style: textStyle.copyWith(color: color),
            child: content,
          ),
          null => content,
        };
      },
      child: widget.child,
    );
  }
}

/// Reports every press it gives up, not only one it had reported down.
class _PressTapRecognizer extends TapGestureRecognizer {
  _PressTapRecognizer({super.debugOwner});

  VoidCallback? onRejected;

  @override
  void rejectGesture(int pointer) {
    final pressed = pointer == primaryPointer;
    super.rejectGesture(pointer);
    if (pressed) {
      onRejected?.call();
    }
  }
}
