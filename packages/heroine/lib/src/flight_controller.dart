part of 'heroines.dart';

/// Controls the lifecycle of a heroine flight animation.
///
/// A flight has two animations running in parallel:
/// 1. **Route animation**: The page transition (managed by Navigator)
/// 2. **Spring animation**: The hero's position/size (managed by MotionControllers)
///
/// The controller is responsible for:
/// - Creating and managing the overlay entry showing the flying hero
/// - Coordinating the spring animations for position and size
/// - Handling flight diversions (when navigation direction changes mid-flight)
/// - Performing the "handoff" when the route animation completes
///
/// Route-driven flights use one clock and end with the route. Independent
/// spring flights end when both animations complete.
class _FlightController {
  _FlightController(this._spec, this.onEnd) {
    if (_spec.routeFlightCurve == null) {
      _spec.controllingHero._createMotionController(
        _spec,
        _onSpringAnimationStatusChanged,
      );
    }
  }

  /// The current flight specification.
  _FlightSpec _spec;

  /// The current target location, updated on each frame when
  /// [_FlightSpec.shouldContinuouslyTrackTarget] is true.
  ///
  /// This allows the flight to smoothly redirect if the target widget moves
  /// during the animation (e.g., keyboard appears/disappears).
  HeroineLocation? _currentTargetLocation;

  Rect? _routeFlightFrom;
  Rect? _lastRouteFlightRect;
  double _routeFlightStart = 0;

  /// Called when the flight ends (both animations complete).
  final VoidCallback onEnd;

  /// The overlay entry displaying the flying hero.
  OverlayEntry? overlayEntry;
  Widget? _shuttle;

  // ---------------------------------------------------------------------------
  // Animation Completion Tracking
  // ---------------------------------------------------------------------------

  /// Whether the spring animation has completed.
  bool _springAnimationComplete = false;

  /// Whether the route animation has completed.
  bool _routeAnimationComplete = false;
  bool _disposed = false;

  /// Starts the flight animation.
  ///
  /// If [resetBoundingBox] is true, the controllers will restart from the
  /// current hero position/size instead of continuing from their previous
  /// animation state.
  /// This is useful when diverting a flight in certain cases, see
  /// [_FlightController.divert].
  void startFlight({bool resetBoundingBox = false}) {
    _spec.fromHero._abortFlight = onEnd;
    _spec.toHero._abortFlight = onEnd;
    _spec.toHero._startFlight(_spec);

    // For user gesture transitions, we don't show the overlay yet
    // (the hero is still being dragged by the user)
    if (_spec.isUserGestureTransition) {
      return;
    }

    _spec.fromHero._startFlight(_spec);
    if (overlayEntry == null) {
      _spec.overlay.insert(
        overlayEntry = OverlayEntry(builder: _buildOverlay),
      );
    } else {
      // Redirection can change both the shuttle and the controlling endpoint.
      overlayEntry!.markNeedsBuild();
    }

    // Get any velocity from a preceding gesture (e.g., drag-to-dismiss)
    final fromHeroVelocity = HeroineVelocity.of(_spec.fromHero.context);
    _spec.routeAnimation.addStatusListener(_onRouteAnimationStatusChanged);

    // Initialize the current target location
    _currentTargetLocation = _spec.toHeroLocation;

    if (_spec.routeFlightCurve != null) {
      _routeFlightFrom ??= _spec.fromHeroLocation.boundingBox;
      _lastRouteFlightRect = _routeFlightFrom;
      _routeFlightStart = _spec.rawRouteAnimation.value;
      if (!_spec.rawRouteAnimation.status.isAnimating) {
        _onRouteAnimationStatusChanged(_spec.rawRouteAnimation.status);
      }
      return;
    }

    // Set up continuous target tracking if enabled
    if (_spec.shouldContinuouslyTrackTarget) {
      _spec.controllingHero._motionController
          ?.addListener(_onMotionControllerUpdate);
    }

    // Animate position and size to the destination
    _spec.controllingHero._motionController
      ?..motion = _spec.motion
      ..animateTo(
        _spec.toHeroLocation,
        from: resetBoundingBox ? _spec.fromHeroLocation : null,
        withVelocity: switch (fromHeroVelocity) {
          final v? => HeroineLocation._velocity(v),
          null => null,
        },
      );
  }

  /// Called on every frame when continuous target tracking is enabled.
  ///
  /// Checks if the target widget has moved and redirects the animation
  /// to the new position if needed.
  void _onMotionControllerUpdate() {
    if (_disposed || _routeAnimationComplete) return;
    if (!_spec.toHero.mounted) {
      onEnd();
      return;
    }

    final newTargetLocation = _FlightSpec._locationFor(
      _spec.toHero,
      _spec.toRoute.subtreeContext,
      direction: _spec.direction,
      isDestination: true,
    );

    // Only redirect if the target has actually moved
    if (newTargetLocation != _currentTargetLocation &&
        newTargetLocation.isValid) {
      _currentTargetLocation = newTargetLocation;
      _spec.controllingHero._motionController?.animateTo(newTargetLocation);
    }
  }

  /// Diverts this flight to a new destination.
  ///
  /// This happens when navigation direction changes mid-flight
  /// (e.g., user swipes back during a push transition).
  void divert(_FlightSpec toSpec) {
    final fromSpec = _spec;
    // Reverse from the last painted rectangle, not the hidden placeholder's
    // full bounds. The remaining route interval becomes the new flight clock.
    final currentRect = _lastRouteFlightRect ??
        fromSpec.controllingHero._motionController?.value.boundingBox;
    _clearAbortCallbacks(fromSpec);
    _spec = toSpec;
    _shuttle = null;

    // Clean up continuous target tracking from the previous spec
    if (fromSpec.shouldContinuouslyTrackTarget) {
      fromSpec.controllingHero._motionController
          ?.removeListener(_onMotionControllerUpdate);
    }

    // Reset the tracked target location for the new flight
    _currentTargetLocation = null;

    fromSpec.dispose();
    fromSpec.routeAnimation
        .removeStatusListener(_onRouteAnimationStatusChanged);

    if (toSpec.routeFlightCurve != null) {
      fromSpec.controllingHero._disposeMotionController();
      _routeFlightFrom = currentRect ?? toSpec.fromHeroLocation.boundingBox;
    } else {
      _routeFlightFrom = null;
      _lastRouteFlightRect = null;
      _transferMotionControllers(
        from: fromSpec.controllingHero,
        to: toSpec.controllingHero,
      );
    }

    // Reset completion flags for the new flight
    _springAnimationComplete = false;
    _routeAnimationComplete = false;

    final fromChanged = toSpec.fromHero == fromSpec.toHero &&
        toSpec.fromHeroLocation != fromSpec.toHeroLocation;

    /// If the position of the new source hero is different from when it was
    /// the toHero in the previous flight, we need to reset the bounding box
    /// of the motion controllers to avoid visual glitches.
    startFlight(
      // A tracked target can move after the original spec was captured. Its
      // live spring already has the right position and velocity for reversal.
      resetBoundingBox: fromChanged && !fromSpec.shouldContinuouslyTrackTarget,
    );
  }

  /// Transfers motion controller ownership between hero states.
  void _transferMotionControllers({
    required _HeroineState from,
    required _HeroineState to,
  }) {
    if (from == to) return;
    final controller = from._motionController;
    if (controller == null) {
      to._createMotionController(_spec, _onSpringAnimationStatusChanged);
      return;
    }
    to._linkRedirectedMotionController(
      controller,
    );
    from._unlinkMotionControllers();
  }

  // ---------------------------------------------------------------------------
  // Flight Handoff
  // ---------------------------------------------------------------------------

  /// Hands off the flight to the destination hero.
  ///
  /// This is called when the route animation completes. The overlay is removed,
  /// but the destination hero continues animating from the current spring
  /// position to its final resting position. This creates a smooth "landing"
  /// effect where the hero settles into place.
  void _performHandoff() {
    _removeOverlay();

    // Stop listening for target updates
    if (_spec.shouldContinuouslyTrackTarget) {
      _spec.controllingHero._motionController
          ?.removeListener(_onMotionControllerUpdate);
    }

    final controller = _spec.controllingHero._motionController;

    if (controller == null) return;

    // Use the tracked target location (which may have been updated during
    // the flight) to ensure the handoff animates to the correct final position.
    final targetLocation = _currentTargetLocation ?? _spec.toHeroLocation;

    _spec.fromHero._completeRouteTransition(
      controller: controller,
      target: targetLocation,
    );
    _spec.toHero._completeRouteTransition(
      controller: controller,
      target: targetLocation,
    );
  }

  // ---------------------------------------------------------------------------
  // Animation Status Handlers
  // ---------------------------------------------------------------------------

  void _onRouteAnimationStatusChanged(AnimationStatus status) {
    if (_disposed || _spec.isUserGestureTransition) return;

    if (status.isAnimating) return;

    _spec.routeAnimation.removeStatusListener(_onRouteAnimationStatusChanged);
    _routeAnimationComplete = true;
    if (_spec.routeFlightCurve != null) {
      // Geometry is already at its endpoint. Restore the card and remove the
      // overlay in this same completion, before the list becomes interactive.
      onEnd();
      return;
    }
    _performHandoff();
    _endFlightIfBothAnimationsComplete();
  }

  void _onSpringAnimationStatusChanged(AnimationStatus status) {
    if (_disposed || _spec.isUserGestureTransition) return;

    _springAnimationComplete = !status.isAnimating;
    if (status.isAnimating) return;

    _endFlightIfBothAnimationsComplete();
  }

  void _endFlightIfBothAnimationsComplete() {
    if (_springAnimationComplete && _routeAnimationComplete) {
      onEnd();
    }
  }

  // ---------------------------------------------------------------------------
  // Overlay Building
  // ---------------------------------------------------------------------------

  /// Builds the overlay widget showing the flying hero.
  Widget _buildOverlay(BuildContext context) {
    // Snapshot the shuttle while both endpoint contexts are still mounted.
    if (_shuttle == null &&
        (!_spec.fromHero.mounted || !_spec.toHero.mounted)) {
      return const SizedBox.shrink();
    }
    final shuttle = _shuttle ??= _spec.shuttleBuilder(
      context,
      _spec.routeAnimation,
      _spec.direction,
      _spec.fromHero.context,
      _spec.toHero.context,
    );

    if (_spec.routeFlightCurve != null) {
      return AnimatedBuilder(
        animation: _spec.rawRouteAnimation,
        builder: (context, child) {
          final target =
              _spec.shouldContinuouslyTrackTarget && _spec.toHero.mounted
                  ? _FlightSpec._locationFor(
                      _spec.toHero,
                      _spec.toRoute.subtreeContext,
                      direction: _spec.direction,
                      isDestination: true,
                    )
                  : _spec.toHeroLocation;
          if (target.isValid) _currentTargetLocation = target;
          final push = _spec.direction == HeroFlightDirection.push;
          final remaining = push ? 1 - _routeFlightStart : _routeFlightStart;
          final elapsed = push
              ? _spec.rawRouteAnimation.value - _routeFlightStart
              : _routeFlightStart - _spec.rawRouteAnimation.value;
          final progress =
              remaining <= 0 ? 1.0 : (elapsed / remaining).clamp(0.0, 1.0);
          final rect = Rect.lerp(
            _routeFlightFrom,
            _currentTargetLocation!.boundingBox,
            _spec.routeFlightCurve!.transform(progress),
          )!;
          _lastRouteFlightRect = rect;
          return Positioned.fromRect(rect: rect, child: child!);
        },
        child: IgnorePointer(child: shuttle),
      );
    }

    final controller = _spec.controllingHero._motionController;

    if (controller == null) return shuttle;

    return AnimatedBuilder(
      animation: Listenable.merge([_spec.routeAnimation, controller]),
      builder: (context, child) => Positioned(
        top: controller.value.boundingBox.center.dy -
            controller.value.boundingBox.size.height / 2,
        left: controller.value.boundingBox.center.dx -
            controller.value.boundingBox.size.width / 2,
        width: controller.value.boundingBox.size.width,
        height: controller.value.boundingBox.size.height,
        // TODO(timcreatedit): rotate here
        child: child!,
      ),
      child: IgnorePointer(
        // TODO(timcreatedit): allow configuring this
        child: shuttle,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Disposal
  // ---------------------------------------------------------------------------

  /// Disposes of this flight controller and cleans up resources.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _clearAbortCallbacks(_spec);
    _spec.routeAnimation.removeStatusListener(_onRouteAnimationStatusChanged);
    // Clean up continuous target tracking
    if (_spec.shouldContinuouslyTrackTarget) {
      _spec.controllingHero._motionController
          ?.removeListener(_onMotionControllerUpdate);
    }

    _spec.fromHero._endFlight();
    _spec.toHero._endFlight();
    _spec.controllingHero._disposeMotionController();

    _spec.dispose();

    if (overlayEntry != null) {
      _removeOverlay();
    }
  }

  void _clearAbortCallbacks(_FlightSpec spec) {
    if (identical(spec.fromHero._abortFlight, onEnd)) {
      spec.fromHero._abortFlight = null;
    }
    if (identical(spec.toHero._abortFlight, onEnd)) {
      spec.toHero._abortFlight = null;
    }
  }

  void _removeOverlay() {
    overlayEntry?.remove();
    overlayEntry?.dispose();
    overlayEntry = null;
  }
}
