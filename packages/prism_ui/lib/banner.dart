import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';
import 'package:prism_ui/color.dart';
import 'package:prism_ui/context.dart';
import 'package:prism_ui/liquid_glass.dart';
import 'package:prism_ui/shape.dart';
import 'package:prism_ui/surface.dart';
import 'package:prism_ui/theme_data.dart';
import 'package:prism_ui/typography.dart';

// iOS 27's notification banner as the simulator showed it in the foreground.
const _actionMinDuration = Duration(seconds: 6);
const _queuedHold = Duration(milliseconds: 3150);
const _maxBuffered = 8;
const _stackedMaxVisible = 3;
const _bannerGap = 8.0;
const _bannerInset = 8.0;
const _bannerMaxWidth = 556.0;
const _bannerMinHeight = 52.0;
const _dropSpring = SpringDescription(mass: 1, stiffness: 256, damping: 27.2);
const _exitDuration = Duration(milliseconds: 170);
const _dismissVelocity = 700.0;
const _dismissFraction = 0.5;
const _pullExtent = 40.0;
const _pullCoefficient = 0.55;

enum BannerLevel {
  info,
  success,
  warning,
  error;

  Duration get duration => switch (this) {
    info || success => const Duration(seconds: 3),
    warning => const Duration(seconds: 5),
    error => const Duration(seconds: 6),
  };

  /// The banner's fill, or null for the plain surface or glass.
  Color? fillOf(ColorScheme colorScheme) => switch (this) {
    info => null,
    success => colorScheme.successContainer,
    warning => colorScheme.warningContainer,
    error => colorScheme.errorContainer,
  };

  Color contentOf(ColorScheme colorScheme) => switch (this) {
    info => colorScheme.onSurface,
    success => colorScheme.onSuccessContainer,
    warning => colorScheme.onWarningContainer,
    error => colorScheme.onErrorContainer,
  };
}

@immutable
class _BannerMessage {
  const _BannerMessage({
    required this.id,
    required this.text,
    required this.level,
    required this.onTap,
  });

  final int id;
  final String text;
  final BannerLevel level;
  final VoidCallback? onTap;

  Duration get duration {
    final duration = level.duration;
    if (onTap == null || duration >= _actionMinDuration) {
      return duration;
    }
    return _actionMinDuration;
  }

  bool repeats(_BannerMessage other) =>
      text == other.text && level == other.level;
}

/// Shows banners over [child]: one at a time when not [stacked], as iOS
/// does, else a column of up to [_stackedMaxVisible]. Once every slot is
/// taken, the oldest banner leaves when it has shown for [_queuedHold] and
/// the next drops in.
class BannerHost extends StatefulWidget {
  const BannerHost({
    super.key,
    required this.stacked,
    required this.topInset,
    required this.child,
  });

  final bool stacked;

  /// What the app keeps clear below the safe area at the top, such as a
  /// window's own header and the page's app bar.
  final double topInset;

  final Widget child;

  static BannerHostState? maybeOf(BuildContext context) =>
      context.findAncestorStateOfType<BannerHostState>();

  @override
  State<BannerHost> createState() => BannerHostState();
}

class BannerHostState extends State<BannerHost> {
  final _entriesNotifier = ValueNotifier<List<_BannerEntry>>([]);
  final _buffer = Queue<_BannerMessage>();
  final _hideTimers = <int, Timer>{};
  final _holdTimers = <int, Timer>{};
  final _held = <int>{};
  var _nextId = 0;
  int? _draggingId;

  @override
  void dispose() {
    _cancelTimers();
    _buffer.clear();
    _entriesNotifier.dispose();
    super.dispose();
  }

  List<_BannerEntry> get _entries => _entriesNotifier.value;

  Iterable<_BannerEntry> get _visibleEntries =>
      _entries.where((entry) => entry.visible);

  /// A banner with [onTap] runs it when tapped, as an iOS notification
  /// opens what it tells of.
  void show(
    String text, {
    BannerLevel level = BannerLevel.info,
    VoidCallback? onTap,
  }) {
    if (text.isEmpty) {
      return;
    }
    final message = _BannerMessage(
      id: _nextId++,
      text: text,
      level: level,
      onTap: onTap,
    );
    if (_merge(message)) {
      return;
    }
    _buffer.add(message);
    _trimBuffer();
    _processQueue();
  }

  bool _merge(_BannerMessage message) {
    final entries = _entries;
    final index = entries.indexWhere(
      (entry) => entry.visible && entry.message.repeats(message),
    );
    if (index != -1) {
      final shown = entries[index];
      final merged = _BannerMessage(
        id: shown.id,
        text: message.text,
        level: message.level,
        onTap: message.onTap,
      );
      _entriesNotifier.value = List<_BannerEntry>.from(entries)
        ..[index] = _BannerEntry(message: merged, visible: true);
      _startTimers(merged);
      return true;
    }
    return _buffer.any((buffered) => buffered.repeats(message));
  }

  void _trimBuffer() {
    while (_buffer.length > _maxBuffered) {
      final dropped =
          _buffer.firstWhereOrNull(
            (message) => message.level != BannerLevel.error,
          ) ??
          _buffer.first;
      _buffer.remove(dropped);
    }
  }

  void _processQueue() {
    if (_draggingId != null) {
      return;
    }
    final stacked = widget.stacked;
    final maxVisible = stacked ? _stackedMaxVisible : 1;
    while (_buffer.isNotEmpty) {
      final visible = _visibleEntries.toList();
      if (visible.length >= maxVisible) {
        final oldest = visible.last;
        if (_held.contains(oldest.id) && oldest.message.onTap == null) {
          _hide(oldest.id);
          continue;
        }
        return;
      }
      // A lone banner's successor waits until it has risen off the screen.
      if (!stacked && _entries.isNotEmpty) {
        return;
      }
      final next =
          _buffer.firstWhereOrNull(
            (message) => message.level == BannerLevel.error,
          ) ??
          _buffer.first;
      _buffer.remove(next);
      _entriesNotifier.value = [
        _BannerEntry(message: next, visible: true),
        ..._entries,
      ];
      _startTimers(next);
    }
  }

  void _startTimers(_BannerMessage message) {
    final id = message.id;
    _cancelTimersOf(id);
    if (_draggingId != null) {
      return;
    }
    _holdTimers[id] = Timer(_queuedHold, () {
      _holdTimers.remove(id);
      _held.add(id);
      _processQueue();
    });
    _hideTimers[id] = Timer(message.duration, () => _hide(id));
  }

  void _cancelTimersOf(int id) {
    _hideTimers.remove(id)?.cancel();
    _holdTimers.remove(id)?.cancel();
    _held.remove(id);
  }

  void _cancelTimers() {
    for (final timer in [..._hideTimers.values, ..._holdTimers.values]) {
      timer.cancel();
    }
    _hideTimers.clear();
    _holdTimers.clear();
    _held.clear();
  }

  void _hide(int id) {
    final entries = _entries;
    final index = entries.indexWhere((entry) => entry.id == id);
    if (index == -1 || !entries[index].visible) {
      return;
    }
    _cancelTimersOf(id);
    _entriesNotifier.value = List<_BannerEntry>.from(entries)
      ..[index] = _BannerEntry(message: entries[index].message, visible: false);
    _processQueue();
  }

  void _dismiss(int id) {
    if (_draggingId == id) {
      _draggingId = null;
      _resumeTimers();
    }
    _buffer.removeWhere((message) => message.id == id);
    _hide(id);
  }

  void _setDragging(int id, bool dragging) {
    if (dragging) {
      if (_draggingId == id) {
        return;
      }
      _draggingId = id;
      _cancelTimers();
      return;
    }
    if (_draggingId != id) {
      return;
    }
    _draggingId = null;
    _resumeTimers();
    _processQueue();
  }

  void _resumeTimers() {
    for (final entry in _visibleEntries) {
      _startTimers(entry.message);
    }
  }

  void _remove(int id) {
    if (!mounted) {
      return;
    }
    final entries = _entries;
    if (!entries.any((entry) => entry.id == id)) {
      return;
    }
    _entriesNotifier.value = entries
        .where((entry) => entry.id != id)
        .toList(growable: false);
    _processQueue();
  }

  Widget _buildBanner(
    _BannerEntry entry, {
    required double top,
    required double width,
    required double areaWidth,
  }) {
    final message = entry.message;
    final onTap = message.onTap;
    return _Banner(
      key: ValueKey(entry.id),
      visible: entry.visible,
      stacked: widget.stacked,
      level: message.level,
      top: top,
      width: width,
      areaWidth: areaWidth,
      onHidden: () => _remove(entry.id),
      onDismiss: () => _dismiss(entry.id),
      onTap: onTap == null
          ? null
          : () {
              _dismiss(entry.id);
              onTap();
            },
      onDragging: (dragging) => _setDragging(entry.id, dragging),
      child: _BannerContent(message: message),
    );
  }

  @override
  Widget build(BuildContext context) {
    final top = math.max(
      MediaQuery.viewPaddingOf(context).top + widget.topInset,
      _bannerInset,
    );
    return Stack(
      children: [
        widget.child,
        Positioned.fill(
          child: ValueListenableBuilder(
            valueListenable: _entriesNotifier,
            builder: (_, entries, _) => LayoutBuilder(
              builder: (_, constraints) {
                final areaWidth = constraints.maxWidth;
                final width = (areaWidth - _bannerInset * 2).clamp(
                  0.0,
                  _bannerMaxWidth,
                );
                final banners = [
                  for (final entry in entries)
                    _buildBanner(
                      entry,
                      top: top,
                      width: width,
                      areaWidth: areaWidth,
                    ),
                ];
                return Stack(
                  children: widget.stacked
                      ? [
                          Positioned(
                            top: top,
                            left: (areaWidth - width) / 2,
                            width: width,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: banners,
                            ),
                          ),
                        ]
                      : banners,
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

@immutable
class _BannerEntry {
  const _BannerEntry({required this.message, required this.visible});

  final _BannerMessage message;
  final bool visible;

  int get id => message.id;
}

/// Drops straight in from above the screen and rises straight back out, or
/// in a [stacked] column drops into a slot it opens and fades as it closes it.
class _Banner extends StatefulWidget {
  const _Banner({
    super.key,
    required this.visible,
    required this.stacked,
    required this.level,
    required this.top,
    required this.width,
    required this.areaWidth,
    required this.onHidden,
    required this.onDismiss,
    required this.onTap,
    required this.onDragging,
    required this.child,
  });

  final bool visible;
  final bool stacked;
  final BannerLevel level;
  final double top;
  final double width;
  final double areaWidth;
  final VoidCallback onHidden;
  final VoidCallback onDismiss;
  final VoidCallback? onTap;
  final ValueChanged<bool> onDragging;
  final Widget child;

  @override
  State<_Banner> createState() => _BannerState();
}

class _BannerState extends State<_Banner> with TickerProviderStateMixin {
  late final AnimationController _drop;
  late final AnimationController _drag;
  late final AnimationController _fade;
  late final Listenable _motion;
  double _pull = 0;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _drop = AnimationController.unbounded(vsync: this);
    _drag = AnimationController.unbounded(vsync: this);
    _fade = AnimationController(value: 1, duration: _exitDuration, vsync: this);
    _motion = Listenable.merge([_drop, _drag]);
    if (widget.visible) {
      _settle(_drop, from: 0, to: 1);
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !widget.visible) {
        widget.onHidden();
      }
    });
  }

  @override
  void didUpdateWidget(covariant _Banner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible != oldWidget.visible && !widget.visible) {
      unawaited(_exit());
    }
  }

  /// A spring stops within its tolerance of the end; this lands on the end.
  void _settle(
    AnimationController controller, {
    required double from,
    required double to,
    double velocity = 0,
  }) {
    controller
        .animateWith(SpringSimulation(_dropSpring, from, to, velocity))
        .then((_) {
          if (mounted) {
            controller.value = to;
          }
        });
  }

  Future<void> _exit() async {
    _drag.stop();
    if (widget.stacked) {
      _fade.animateBack(0, curve: Curves.easeIn);
    }
    await _drop
        .animateTo(0, duration: _exitDuration, curve: Curves.easeIn)
        .orCancel
        .catchError((_) {});
    if (mounted) {
      widget.onHidden();
    }
  }

  double get _height => context.size?.height ?? _bannerMinHeight;

  void _handleDragStart(DragStartDetails details) {
    if (!widget.visible) {
      return;
    }
    _dragging = true;
    _pull = _drag.value;
    _drag.stop();
    widget.onDragging(true);
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    if (!_dragging) {
      return;
    }
    _pull += details.primaryDelta ?? 0;
    _drag.value = _pull <= 0
        ? _pull
        : _pullExtent * (1 - 1 / (_pullCoefficient * _pull / _pullExtent + 1));
  }

  void _handleDragEnd(double velocity) {
    if (!_dragging) {
      return;
    }
    _dragging = false;
    final offset = _drag.value;
    if (velocity <= -_dismissVelocity ||
        offset <= -(widget.top + _height) * _dismissFraction) {
      widget.onDismiss();
      return;
    }
    widget.onDragging(false);
    _settle(_drag, from: offset, to: 0, velocity: velocity);
  }

  @override
  void dispose() {
    _drop.dispose();
    _drag.dispose();
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final child = IgnorePointer(
      ignoring: !widget.visible,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onVerticalDragStart: _handleDragStart,
        onVerticalDragUpdate: _handleDragUpdate,
        onVerticalDragEnd: (details) {
          _handleDragEnd(details.primaryVelocity ?? 0);
        },
        onVerticalDragCancel: () {
          _handleDragEnd(0);
        },
        child: _BannerSurface(level: widget.level, child: widget.child),
      ),
    );
    if (widget.stacked) {
      return AnimatedBuilder(
        animation: _motion,
        builder: (_, child) => Align(
          alignment: widget.visible
              ? Alignment.bottomCenter
              : Alignment.topCenter,
          heightFactor: math.max(0, _drop.value),
          child: Transform.translate(
            offset: Offset(0, _drag.value),
            child: child,
          ),
        ),
        child: LiquidGlassFade(
          opacity: _fade,
          child: Padding(
            padding: const EdgeInsets.only(bottom: _bannerGap),
            child: child,
          ),
        ),
      );
    }
    return AnimatedBuilder(
      animation: _motion,
      builder: (_, child) {
        final drop = _drop.value;
        // Lerps the top from a banner's height above the screen, which is
        // unknown until layout, to its rest.
        return Positioned(
          top: widget.top * drop + _drag.value,
          left: (widget.areaWidth - widget.width) / 2,
          width: widget.width,
          child: FractionalTranslation(
            translation: Offset(0, drop - 1),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

class _BannerSurface extends StatelessWidget {
  const _BannerSurface({required this.level, required this.child});

  final BannerLevel level;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final surface = SurfaceLevel.floatingOf(colorScheme);
    final fill = level.fillOf(colorScheme);
    final content = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: _bannerMinHeight),
      child: SurfaceScope(level: surface, child: child),
    );
    if (LiquidGlassScope.of(context)) {
      return LiquidGlass(
        style: LiquidGlassStyle.banner(colorScheme, fill: fill),
        borderRadius: AppRadius.xl,
        shadows: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
        child: content,
      );
    }
    return Surface(
      color: fill ?? surface.colorOf(colorScheme),
      shadowColor: colorScheme.shadow.withValues(alpha: 0.6),
      elevation: 3,
      shape: AppShape.xl,
      child: content,
    );
  }
}

class _BannerContent extends StatelessWidget {
  const _BannerContent({required this.message});

  final _BannerMessage message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Text(
          message.text,
          maxLines: 3,
          style: AppTextStyle.subheadline
              .of(context, emphasized: true)
              .copyWith(color: message.level.contentOf(context.colorScheme)),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
