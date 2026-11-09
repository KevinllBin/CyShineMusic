import 'dart:math' as math;

import 'package:flutter/foundation.dart' show defaultTargetPlatform, immutable;
import 'package:flutter/widgets.dart';
import 'package:prism_ui/color.dart';
import 'package:prism_ui/color_scheme.dart';
import 'package:prism_ui/surface.dart';

export 'package:prism_ui/color_scheme.dart';

const kMinInteractiveDimension = 48.0;
const kThemeAnimationDuration = Duration(milliseconds: 200);

enum ThemeMode { system, light, dark }

enum TapTargetSize { padded, shrinkWrap }

abstract final class Colors {
  static const transparent = Color(0x00000000);
  static const black = Color(0xFF000000);
  static const black54 = Color(0x8A000000);
  static const white = Color(0xFFFFFFFF);
}

/// Material 3's easing curves, the ones the components move on.
abstract final class Easing {
  static const emphasizedDecelerate = Cubic(0.05, 0.7, 0.1, 1);
  static const legacyDecelerate = Cubic(0, 0, 0.2, 1);
  static const standard = Cubic(0.2, 0, 0, 1);
  static const standardAccelerate = Cubic(0.3, 0, 1, 1);
  static const standardDecelerate = Cubic(0, 0, 0, 1);
}

@immutable
class VisualDensity {
  const VisualDensity({this.horizontal = 0, this.vertical = 0});

  final double horizontal;
  final double vertical;

  static const standard = VisualDensity();
  static const compact = VisualDensity(horizontal: -2, vertical: -2);

  static const _baseUnit = 4.0;

  Offset get baseSizeAdjustment => Offset(horizontal, vertical) * _baseUnit;

  BoxConstraints effectiveConstraints(BoxConstraints constraints) {
    assert(constraints.debugAssertIsValid());
    return constraints.copyWith(
      minWidth: clampMin(
        constraints.minWidth + baseSizeAdjustment.dx,
        constraints.maxWidth,
      ),
      minHeight: clampMin(
        constraints.minHeight + baseSizeAdjustment.dy,
        constraints.maxHeight,
      ),
    );
  }

  static double clampMin(double value, double max) =>
      math.max(0, math.min(value, max));

  @override
  bool operator ==(Object other) =>
      other is VisualDensity &&
      other.horizontal == horizontal &&
      other.vertical == vertical;

  @override
  int get hashCode => Object.hash(horizontal, vertical);
}

const _baselineSeed = Color(0xFF6750A4);
const _linuxFallback = [
  'Ubuntu',
  'Cantarell',
  'DejaVu Sans',
  'Liberation Sans',
  'Arial',
];

final _defaultSchemes = <Brightness, ColorScheme>{};

ColorScheme _defaultScheme(Brightness brightness) =>
    _defaultSchemes[brightness] ??= seededColorScheme(
      seedColor: _baselineSeed,
      brightness: brightness,
      style: ColorStyle.soft,
    );

/// The system font a platform draws text at a size in, before the app's own.
({String family, List<String>? fallback}) systemFontOf(
  TargetPlatform platform, {
  bool display = false,
}) => switch (platform) {
  TargetPlatform.android ||
  TargetPlatform.fuchsia => (family: 'Roboto', fallback: null),
  // Apple switches between SF Pro Display and Text at 20 pt.
  TargetPlatform.iOS => (
    family: display ? 'CupertinoSystemDisplay' : 'CupertinoSystemText',
    fallback: null,
  ),
  TargetPlatform.macOS => (family: '.AppleSystemUIFont', fallback: null),
  TargetPlatform.windows => (family: 'Segoe UI', fallback: null),
  TargetPlatform.linux => (family: 'Roboto', fallback: _linuxFallback),
};

class ThemeData {
  factory ThemeData({
    ColorScheme? colorScheme,
    Brightness? brightness,
    TargetPlatform? platform,
    String? fontFamily,
    List<String>? fontFamilyFallback,
    VisualDensity? visualDensity,
    TapTargetSize? tapTargetSize,
    Color? scaffoldBackgroundColor,
    ColorScheme? elevatedColorScheme,
  }) {
    final scheme =
        colorScheme ?? _defaultScheme(brightness ?? Brightness.light);
    final effectivePlatform = platform ?? defaultTargetPlatform;
    final desktop = switch (effectivePlatform) {
      TargetPlatform.macOS ||
      TargetPlatform.windows ||
      TargetPlatform.linux => true,
      _ => false,
    };
    return ThemeData._(
      colorScheme: scheme,
      platform: effectivePlatform,
      fontFamily: fontFamily,
      fontFamilyFallback: fontFamilyFallback,
      visualDensity:
          visualDensity ??
          (desktop ? VisualDensity.compact : VisualDensity.standard),
      tapTargetSize:
          tapTargetSize ??
          (desktop ? TapTargetSize.shrinkWrap : TapTargetSize.padded),
      scaffoldBackgroundColor:
          scaffoldBackgroundColor ?? SurfaceLevel.page.colorOf(scheme),
      elevatedColorScheme: elevatedColorScheme,
    );
  }

  ThemeData._({
    required this.colorScheme,
    required this.platform,
    required this.fontFamily,
    required this.fontFamilyFallback,
    required this.visualDensity,
    required this.tapTargetSize,
    required this.scaffoldBackgroundColor,
    required this.elevatedColorScheme,
  });

  static final _fallbacks = <TargetPlatform, ThemeData>{};

  final ColorScheme colorScheme;
  final TargetPlatform platform;
  final String? fontFamily;
  final List<String>? fontFamilyFallback;
  final VisualDensity visualDensity;
  final TapTargetSize tapTargetSize;
  final Color scaffoldBackgroundColor;

  /// What sheets present with, where it differs: `.agents/surfaces.md`.
  final ColorScheme? elevatedColorScheme;

  Brightness get brightness => colorScheme.brightness;

  IconThemeData get iconTheme => IconThemeData(
    color: brightness == Brightness.dark
        ? Colors.white
        : const Color(0xDD000000),
  );

  late final TextStyle displayTextStyle = _textStyle(display: true);
  late final TextStyle bodyTextStyle = _textStyle(display: false);

  TextStyle _textStyle({required bool display}) {
    final system = systemFontOf(platform, display: display);
    return TextStyle(
      inherit: false,
      color: colorScheme.onSurface,
      decoration: TextDecoration.none,
      decorationColor: colorScheme.onSurface,
      fontFamily: fontFamily ?? system.family,
      fontFamilyFallback: fontFamilyFallback ?? system.fallback,
      textBaseline: TextBaseline.alphabetic,
      leadingDistribution: TextLeadingDistribution.even,
    );
  }

  /// Black or white, whichever reads against [color].
  static Brightness estimateBrightnessForColor(Color color) {
    final relativeLuminance = color.computeLuminance();
    const kThreshold = 0.15;
    return (relativeLuminance + 0.05) * (relativeLuminance + 0.05) > kThreshold
        ? Brightness.light
        : Brightness.dark;
  }

  ThemeData copyWith({
    ColorScheme? colorScheme,
    Brightness? brightness,
    TargetPlatform? platform,
    String? fontFamily,
    List<String>? fontFamilyFallback,
    VisualDensity? visualDensity,
    TapTargetSize? tapTargetSize,
    Color? scaffoldBackgroundColor,
    ColorScheme? elevatedColorScheme,
  }) {
    final scheme = colorScheme ?? this.colorScheme;
    return ThemeData(
      colorScheme: scheme,
      platform: platform ?? this.platform,
      fontFamily: fontFamily ?? this.fontFamily,
      fontFamilyFallback: fontFamilyFallback ?? this.fontFamilyFallback,
      visualDensity: visualDensity ?? this.visualDensity,
      tapTargetSize: tapTargetSize ?? this.tapTargetSize,
      scaffoldBackgroundColor:
          scaffoldBackgroundColor ??
          (colorScheme == null ? this.scaffoldBackgroundColor : null),
      elevatedColorScheme: elevatedColorScheme ?? this.elevatedColorScheme,
    );
  }
}

class Theme extends StatelessWidget {
  const Theme({super.key, required this.data, required this.child});

  final ThemeData data;
  final Widget child;

  static ThemeData of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_InheritedTheme>()?.data ??
      ThemeData._fallbacks.putIfAbsent(defaultTargetPlatform, ThemeData.new);

  static Brightness brightnessOf(BuildContext context) =>
      of(context).brightness;

  @override
  Widget build(BuildContext context) {
    return _InheritedTheme(
      data: data,
      child: IconTheme(data: data.iconTheme, child: child),
    );
  }
}

class _InheritedTheme extends InheritedTheme {
  const _InheritedTheme({required this.data, required super.child});

  final ThemeData data;

  @override
  Widget wrap(BuildContext context, Widget child) =>
      Theme(data: data, child: child);

  @override
  bool updateShouldNotify(_InheritedTheme oldWidget) => data != oldWidget.data;
}
