import 'package:flutter/material.dart';
import 'package:heroine/heroine.dart';

import '../container_transform.dart';
import '../../../theme/app_motion.dart';

/// Heroine 演示的 Standard Flutter Hero：单层封面、与路由同步的 Smooth 曲线，
/// 不叠加翻转或两张图片的透明混合。
class SpringArtworkHero extends StatefulWidget {
  const SpringArtworkHero({super.key, required this.tag, required this.child});

  final Object tag;
  final Widget child;

  static const flightKey = ValueKey('spring-artwork-flight');

  @override
  State<SpringArtworkHero> createState() => _SpringArtworkHeroState();
}

class _SpringArtworkHeroState extends State<SpringArtworkHero> {
  late final _StandardArtworkShuttle _shuttle = _StandardArtworkShuttle(this);
  Rect? _restingBounds;
  Size _flightSize = Size.zero;
  EdgeInsets _flightCrop = EdgeInsets.zero;
  bool _returnFromHidden = false;

  Rect _flightBounds(
    BuildContext heroContext,
    Rect bounds,
    HeroFlightDirection direction,
    bool isDestination,
  ) {
    final detail = ContainerTransformTransition.usesSpringHeroOf(context);
    final geometry = ContainerTransformOrigin.capture(heroContext);
    _returnFromHidden = false;
    _flightCrop = EdgeInsets.zero;

    if (detail && direction == HeroFlightDirection.push && isDestination) {
      _restingBounds = bounds;
    }
    if (detail &&
        direction == HeroFlightDirection.pop &&
        !isDestination &&
        geometry == null) {
      // The actual header stays scrolled away. Only the flying copy uses its
      // remembered on-screen position, so the song list never jumps to the top.
      final resting =
          _restingBounds ??
          Rect.fromLTWH(bounds.left, 0, bounds.width, bounds.height);
      _returnFromHidden = true;
      _flightSize = resting.size;
      return resting;
    }

    if (geometry?.visibleRect case final visible?) {
      final full = geometry!.rect;
      _flightCrop = EdgeInsets.fromLTRB(
        ((visible.left - full.left) / full.width).clamp(0, 1),
        ((visible.top - full.top) / full.height).clamp(0, 1),
        ((full.right - visible.right) / full.width).clamp(0, 1),
        ((full.bottom - visible.bottom) / full.height).clamp(0, 1),
      );
      final clipped = Rect.fromLTRB(
        bounds.left + bounds.width * _flightCrop.left,
        bounds.top + bounds.height * _flightCrop.top,
        bounds.right - bounds.width * _flightCrop.right,
        bounds.bottom - bounds.height * _flightCrop.bottom,
      );
      _flightSize = clipped.size;
      return clipped;
    }
    _flightSize = bounds.size;
    return bounds;
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return widget.child;
    return Heroine(
      tag: widget.tag,
      motion: const CupertinoMotion.smooth(),
      routeFlightCurve: AppMotion.artworkFlight,
      flightShuttleBuilder: _shuttle,
      flightBoundsBuilder: _flightBounds,
      // Track automatic card reveal only during the route transition. Both
      // page and cover finish together; no overlay survives into list scrolling.
      continuouslyTrackTarget: !ContainerTransformTransition.usesSpringHeroOf(
        context,
      ),
      pauseTickersDuringFlight: true,
      child: widget.child,
    );
  }
}

/// Standard's single destination image, with a viewport crop that opens out
/// along the actual spring geometry. No second image or flip is introduced.
class _StandardArtworkShuttle extends HeroineShuttleBuilder {
  const _StandardArtworkShuttle(this.owner);

  final _SpringArtworkHeroState owner;

  @override
  List<Object?> get props => [owner];

  @override
  Widget call(
    BuildContext flightContext,
    Animation<double> animation,
    HeroFlightDirection direction,
    BuildContext fromHeroContext,
    BuildContext toHeroContext,
  ) {
    final fromHero = fromHeroContext.widget as Heroine;
    final toHero = toHeroContext.widget as Heroine;
    final fromState =
        (fromHero.flightShuttleBuilder as _StandardArtworkShuttle).owner;
    final toState =
        (toHero.flightShuttleBuilder as _StandardArtworkShuttle).owner;
    final fromSize = fromState._flightSize;
    final fromCrop = fromState._flightCrop;
    final from = HeroArtworkShape.resolve(fromHeroContext);
    final to = HeroArtworkShape.resolve(toHeroContext);
    final hiddenReturn = fromState._returnFromHidden;
    // Snapshot endpoint widgets and theme before either route can unmount.
    final image = InheritedTheme.captureAll(toHeroContext, to.child);

    Widget flight = LayoutBuilder(
      builder: (context, constraints) {
        final toSize = toState._flightSize;
        final toCrop = toState._flightCrop;
        final widthDelta = toSize.width - fromSize.width;
        final heightDelta = toSize.height - fromSize.height;
        final progress =
            (widthDelta.abs() > 1
                    ? (constraints.maxWidth - fromSize.width) / widthDelta
                    : heightDelta.abs() > 1
                    ? (constraints.maxHeight - fromSize.height) / heightDelta
                    : direction == HeroFlightDirection.push
                    ? animation.value
                    : 1 - animation.value)
                .clamp(0.0, 1.0);
        final crop = EdgeInsets.lerp(fromCrop, toCrop, progress)!;
        final width =
            constraints.maxWidth / (1 - crop.left - crop.right).clamp(0.001, 1);
        final height =
            constraints.maxHeight /
            (1 - crop.top - crop.bottom).clamp(0.001, 1);
        return ClipRect(
          key: SpringArtworkHero.flightKey,
          child: OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: width,
            maxWidth: width,
            minHeight: height,
            maxHeight: height,
            child: Transform.translate(
              offset: Offset(-width * crop.left, -height * crop.top),
              child: ClipRRect(
                borderRadius: BorderRadius.lerp(
                  from.borderRadius,
                  to.borderRadius,
                  progress,
                )!,
                child: image,
              ),
            ),
          ),
        );
      },
    );
    if (hiddenReturn) {
      // A cover that was not on screen must appear gradually over the current
      // content, rather than replacing the scrolled list in the first frame.
      flight = FadeTransition(
        opacity: animation.drive(
          Tween(
            begin: 1.0,
            end: 0.0,
          ).chain(CurveTween(curve: const Interval(0.75, 1))),
        ),
        child: flight,
      );
    }
    return flight;
  }
}
