import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Window metadata stays in physical pixels until matched to the Flutter view.
class ScreenCorners extends ChangeNotifier with WidgetsBindingObserver {
  ScreenCorners() {
    WidgetsBinding.instance.addObserver(this);
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'changed') _scheduleRefresh();
    });
    _scheduleRefresh();
  }

  static const _channel = MethodChannel('cy_shine_music/screen_corners');
  Size _window = Size.zero;
  List<double> _radii = const [0, 0, 0, 0];
  ScreenCornerCurve? curve;
  double _scale = 1;
  int _generation = 0;
  bool _scheduled = false;
  bool _disposed = false;

  List<double> radiiFor(Size viewport, double pixelRatio) {
    if ((viewport.width * pixelRatio - _window.width).abs() > 1 ||
        (viewport.height * pixelRatio - _window.height).abs() > 1) {
      return const [0, 0, 0, 0];
    }
    return _radii.map((r) => r * _scale / pixelRatio).toList();
  }

  @override
  void didChangeMetrics() => _scheduleRefresh();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _scheduleRefresh();
  }

  void _scheduleRefresh() {
    if (_disposed) return;
    _generation++;
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!_disposed) unawaited(_refresh(_generation));
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _refresh(int generation) async {
    try {
      final data = await _channel.invokeMapMethod<String, dynamic>('get');
      if (_disposed || generation != _generation || data == null) return;
      final radii = (data['radii'] as List).cast<num>();
      final points = (data['curve'] as List).cast<num>();
      if (radii.length != 4 || points.length.isOdd) return;
      _window = Size(
        (data['width'] as num).toDouble(),
        (data['height'] as num).toDouble(),
      );
      _radii = radii.map((r) => r.toDouble()).toList();
      _scale = (data['scale'] as num).toDouble();
      curve = points.isEmpty
          ? null
          : ScreenCornerCurve(
              List.generate(
                points.length ~/ 2,
                (i) => Offset(
                  points[i * 2].toDouble(),
                  points[i * 2 + 1].toDouble(),
                ),
              ),
            );
      notifyListeners();
    } on MissingPluginException {
      // Desktop previews and tests have no Android window metadata.
    } on PlatformException {
      if (_disposed || generation != _generation) return;
      _window = Size.zero;
      curve = null;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _channel.setMethodCallHandler(null);
    super.dispose();
  }
}

/// Precompute the circular counterpart once, keeping trigonometry off the frame loop.
class ScreenCornerCurve {
  ScreenCornerCurve(this.points)
    : circle = points.map((point) {
        final angle = math.atan2(point.dy, point.dx);
        return Offset(1 - math.sin(angle), 1 - math.cos(angle));
      }).toList(),
      extent = math.max(points.first.dx, points.last.dy);

  final List<Offset> points;
  final List<Offset> circle;
  final double extent;
}
