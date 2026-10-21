import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/settings_store.dart';
import '../../../core/ui/cover_image_source.dart';
import '../../shell/player_transition.dart';
import '../player_controller.dart';

const kSquareCoverRadiusFactor = 0.06;

/// Album artwork that spins during playback unless square covers are enabled.
///
/// Extracted from the player's album page so the shell's mini player bar can
/// reuse the same rotation and image pipeline. [placeholder] is supplied by
/// the caller because the player page styles it with its immersive palette
/// while the toolbar uses the ambient color scheme.
class SpinningCoverArt extends ConsumerStatefulWidget {
  const SpinningCoverArt({
    super.key,
    required this.track,
    required this.size,
    required this.placeholder,
    this.boxShadow,
  });

  final PlayerTrack track;
  final double size;
  final Widget placeholder;
  final List<BoxShadow>? boxShadow;

  @override
  ConsumerState<SpinningCoverArt> createState() => _SpinningCoverArtState();
}

class _SpinningCoverArtState extends ConsumerState<SpinningCoverArt>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rotationController;
  bool _sharedRotation = false;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 24),
    );
    _syncRotation();
    ref.listenManual(
      playerControllerProvider.select((s) => s.playing),
      (_, _) => _syncRotation(),
    );
    ref.listenManual(
      settingsProvider.select((s) => s.squareAlbumCoverEnabled),
      (_, _) => _syncRotation(),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sharedRotation = PlayerTransitionScope.maybeOf(context) != null;
    _syncRotation();
  }

  void _syncRotation() {
    final rotate =
        !_sharedRotation &&
        !ref.read(settingsProvider).squareAlbumCoverEnabled &&
        ref.read(playerControllerProvider).playing;
    if (rotate) {
      if (!_rotationController.isAnimating) _rotationController.repeat();
    } else {
      _rotationController.stop(canceled: false);
    }
  }

  @override
  void dispose() {
    _rotationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final square = ref.watch(
      settingsProvider.select((settings) => settings.squareAlbumCoverEnabled),
    );
    final normalized = CoverImageSource.normalizeUrl(
      widget.track.coverUrl,
      size: 700,
    );
    return RepaintBoundary(
      child: RotationTransition(
        turns: square
            ? const AlwaysStoppedAnimation<double>(0)
            : PlayerTransitionScope.maybeOf(context)?.rotation ??
                  _rotationController,
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: square ? BoxShape.rectangle : BoxShape.circle,
            borderRadius: square
                ? BorderRadius.circular(widget.size * kSquareCoverRadiusFactor)
                : null,
            boxShadow: widget.boxShadow,
          ),
          clipBehavior: Clip.antiAlias,
          child: RepaintBoundary(
            child: PlayerArtworkImage(
              url: normalized,
              bytes: widget.track.coverBytes,
              placeholder: widget.placeholder,
            ),
          ),
        ),
      ),
    );
  }
}

class PlayerArtworkImage extends StatefulWidget {
  const PlayerArtworkImage({
    super.key,
    required this.url,
    required this.bytes,
    required this.placeholder,
    this.animate = true,
  });

  final String? url;
  final Uint8List? bytes;
  final Widget placeholder;
  final bool animate;

  @override
  State<PlayerArtworkImage> createState() => _PlayerArtworkImageState();
}

class _PlayerArtworkImageState extends State<PlayerArtworkImage>
    with SingleTickerProviderStateMixin {
  static const _curve = Cubic(0.4, 0, 0.2, 1);
  late final AnimationController _change;
  ImageStream? _stream;
  ImageStreamListener? _listener;
  Object? _resolvedKey;
  ImageInfo? _current;
  ImageInfo? _outgoing;
  double _outgoingOpacity = 1;
  double _outgoingScale = 1;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _change = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
      value: 1,
    )..addStatusListener(_onStatus);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _subscribe();
    if (MediaQuery.disableAnimationsOf(context)) _finishChange();
  }

  @override
  void didUpdateWidget(covariant PlayerArtworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url || oldWidget.bytes != widget.bytes) {
      _subscribe();
    }
    if (!widget.animate) _finishChange();
  }

  void _subscribe() {
    final bytes = widget.bytes;
    final url = widget.url;
    final ImageProvider<Object>? source;
    if (bytes != null && bytes.isNotEmpty) {
      source = MemoryImage(bytes);
    } else if (url != null && url.isNotEmpty) {
      source = CachedNetworkImageProvider(
        url,
        headers: CoverImageSource.headersFor(url),
      );
    } else {
      source = null;
    }

    if (source == null) {
      _generation++;
      _resolvedKey = null;
      _unsubscribe();
      _clearImages();
      return;
    }
    // The main cover, mini player and shared cover resolve the same 480px key.
    final stream = ResizeImage(
      source,
      width: 480,
      height: 480,
    ).resolve(createLocalImageConfiguration(context));
    if (_resolvedKey == stream.key) return;
    _unsubscribe();
    _resolvedKey = stream.key;
    final generation = ++_generation;
    var receivedImage = false;
    final listener = ImageStreamListener(
      (info, _) {
        if (!mounted || generation != _generation) {
          info.dispose();
          return;
        }
        final animateChange = !receivedImage;
        receivedImage = true;
        _adoptImage(info, animateChange: animateChange);
      },
      onError: (Object error, StackTrace? stackTrace) {
        if (!mounted || generation != _generation) return;
        _unsubscribe();
        _clearImages();
      },
    );
    _stream = stream;
    _listener = listener;
    stream.addListener(listener);
  }

  void _unsubscribe() {
    final listener = _listener;
    if (listener != null) _stream?.removeListener(listener);
    _listener = null;
    _stream = null;
  }

  void _adoptImage(ImageInfo image, {required bool animateChange}) {
    final current = _current;
    if (current != null && image.image.isCloneOf(current.image)) {
      image.dispose();
      return;
    }
    // Animated frames and refreshed cache entries belong to the same source.
    // Replace their pixels without restarting an in-flight cover transition.
    if (!animateChange) {
      setState(() => _current = image);
      _disposeAfterFrame(current);
      return;
    }
    final outgoing = _outgoing;
    final progress = _curve.transform(_change.value);
    final animate =
        widget.animate &&
        current != null &&
        !MediaQuery.disableAnimationsOf(context);
    _change.stop(canceled: false);

    // A rapid skip keeps only the more visible old image, at its current scale
    // and opacity. No earlier artwork trees or rotation controllers accumulate.
    final keepOutgoing =
        outgoing != null && _outgoingOpacity * (1 - progress) > progress;
    final previous = keepOutgoing ? outgoing : current;
    final previousOpacity = keepOutgoing
        ? _outgoingOpacity * (1 - progress)
        : outgoing == null
        ? 1.0
        : progress;
    final previousScale = keepOutgoing
        ? _outgoingScale + (1.5 - _outgoingScale) * progress
        : outgoing == null
        ? 1.0
        : 1.5 - 0.5 * progress;
    setState(() {
      _current = image;
      _outgoing = animate ? previous : null;
      _outgoingOpacity = previousOpacity;
      _outgoingScale = previousScale;
    });
    if (current != previous || !animate) _disposeAfterFrame(current);
    if (outgoing != previous || !animate) _disposeAfterFrame(outgoing);
    if (animate) {
      _change.forward(from: 0);
    } else {
      _change.value = 1;
    }
  }

  void _finishChange() {
    if (_outgoing != null) _change.value = 1;
  }

  void _onStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || _outgoing == null) return;
    final previous = _outgoing;
    setState(() => _outgoing = null);
    _disposeAfterFrame(previous);
  }

  void _clearImages() {
    _change.stop(canceled: false);
    final current = _current;
    final outgoing = _outgoing;
    setState(() {
      _current = null;
      _outgoing = null;
    });
    _change.value = 1;
    _disposeAfterFrame(current);
    _disposeAfterFrame(outgoing);
  }

  void _disposeAfterFrame(ImageInfo? image) {
    if (image == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => image.dispose());
  }

  @override
  void dispose() {
    _generation++;
    _unsubscribe();
    _change.removeStatusListener(_onStatus);
    _change.dispose();
    _current?.dispose();
    _outgoing?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current = _current;
    if (current == null) return widget.placeholder;
    final incoming = RawImage(image: current.image, fit: BoxFit.cover);
    final outgoingInfo = _outgoing;
    if (outgoingInfo == null || !widget.animate) return incoming;
    final outgoing = RawImage(image: outgoingInfo.image, fit: BoxFit.cover);
    return AnimatedBuilder(
      animation: _change,
      builder: (context, _) {
        final progress = _curve.transform(_change.value);
        return Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.hardEdge,
          children: [
            Opacity(
              opacity: _outgoingOpacity * (1 - progress),
              child: Transform.scale(
                scale: _outgoingScale + (1.5 - _outgoingScale) * progress,
                child: outgoing,
              ),
            ),
            Opacity(
              opacity: progress,
              child: Transform.scale(
                scale: 1.5 - 0.5 * progress,
                child: incoming,
              ),
            ),
          ],
        );
      },
    );
  }
}
