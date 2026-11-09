import 'package:flutter/widgets.dart';
import 'package:prism_ui/color.dart';
import 'package:prism_ui/theme_data.dart';

/// The color roles every component draws with.
@immutable
class ColorScheme {
  factory ColorScheme.fromSeed({
    required Color seedColor,
    Brightness brightness = Brightness.light,
    ColorStyle style = ColorStyle.soft,
  }) => seededColorScheme(
    seedColor: seedColor,
    brightness: brightness,
    style: style,
  );

  static ColorScheme of(BuildContext context) => Theme.of(context).colorScheme;

  const ColorScheme({
    required this.brightness,
    required this.primary,
    required this.onPrimary,
    Color? primaryContainer,
    Color? onPrimaryContainer,
    Color? primaryFixed,
    Color? primaryFixedDim,
    Color? onPrimaryFixed,
    Color? onPrimaryFixedVariant,
    required this.secondary,
    required this.onSecondary,
    Color? secondaryContainer,
    Color? onSecondaryContainer,
    Color? secondaryFixed,
    Color? secondaryFixedDim,
    Color? onSecondaryFixed,
    Color? onSecondaryFixedVariant,
    Color? tertiary,
    Color? onTertiary,
    Color? tertiaryContainer,
    Color? onTertiaryContainer,
    Color? tertiaryFixed,
    Color? tertiaryFixedDim,
    Color? onTertiaryFixed,
    Color? onTertiaryFixedVariant,
    required this.error,
    required this.onError,
    Color? errorContainer,
    Color? onErrorContainer,
    required this.surface,
    required this.onSurface,
    Color? surfaceDim,
    Color? surfaceBright,
    Color? surfaceContainerLowest,
    Color? surfaceContainerLow,
    Color? surfaceContainer,
    Color? surfaceContainerHigh,
    Color? surfaceContainerHighest,
    Color? onSurfaceVariant,
    Color? outline,
    Color? outlineVariant,
    Color? shadow,
    Color? scrim,
    Color? inverseSurface,
    Color? onInverseSurface,
    Color? inversePrimary,
    Color? surfaceTint,
  }) : _primaryContainer = primaryContainer,
       _onPrimaryContainer = onPrimaryContainer,
       _primaryFixed = primaryFixed,
       _primaryFixedDim = primaryFixedDim,
       _onPrimaryFixed = onPrimaryFixed,
       _onPrimaryFixedVariant = onPrimaryFixedVariant,
       _secondaryContainer = secondaryContainer,
       _onSecondaryContainer = onSecondaryContainer,
       _secondaryFixed = secondaryFixed,
       _secondaryFixedDim = secondaryFixedDim,
       _onSecondaryFixed = onSecondaryFixed,
       _onSecondaryFixedVariant = onSecondaryFixedVariant,
       _tertiary = tertiary,
       _onTertiary = onTertiary,
       _tertiaryContainer = tertiaryContainer,
       _onTertiaryContainer = onTertiaryContainer,
       _tertiaryFixed = tertiaryFixed,
       _tertiaryFixedDim = tertiaryFixedDim,
       _onTertiaryFixed = onTertiaryFixed,
       _onTertiaryFixedVariant = onTertiaryFixedVariant,
       _errorContainer = errorContainer,
       _onErrorContainer = onErrorContainer,
       _surfaceDim = surfaceDim,
       _surfaceBright = surfaceBright,
       _surfaceContainerLowest = surfaceContainerLowest,
       _surfaceContainerLow = surfaceContainerLow,
       _surfaceContainer = surfaceContainer,
       _surfaceContainerHigh = surfaceContainerHigh,
       _surfaceContainerHighest = surfaceContainerHighest,
       _onSurfaceVariant = onSurfaceVariant,
       _outline = outline,
       _outlineVariant = outlineVariant,
       _shadow = shadow,
       _scrim = scrim,
       _inverseSurface = inverseSurface,
       _onInverseSurface = onInverseSurface,
       _inversePrimary = inversePrimary,
       _surfaceTint = surfaceTint;

  const ColorScheme.light({
    this.brightness = Brightness.light,
    this.primary = const Color(0xff6200ee),
    this.onPrimary = const Color(0xFFFFFFFF),
    Color? primaryContainer,
    Color? onPrimaryContainer,
    Color? primaryFixed,
    Color? primaryFixedDim,
    Color? onPrimaryFixed,
    Color? onPrimaryFixedVariant,
    this.secondary = const Color(0xff03dac6),
    this.onSecondary = const Color(0xFF000000),
    Color? secondaryContainer,
    Color? onSecondaryContainer,
    Color? secondaryFixed,
    Color? secondaryFixedDim,
    Color? onSecondaryFixed,
    Color? onSecondaryFixedVariant,
    Color? tertiary,
    Color? onTertiary,
    Color? tertiaryContainer,
    Color? onTertiaryContainer,
    Color? tertiaryFixed,
    Color? tertiaryFixedDim,
    Color? onTertiaryFixed,
    Color? onTertiaryFixedVariant,
    this.error = const Color(0xffb00020),
    this.onError = const Color(0xFFFFFFFF),
    Color? errorContainer,
    Color? onErrorContainer,
    this.surface = const Color(0xFFFFFFFF),
    this.onSurface = const Color(0xFF000000),
    Color? surfaceDim,
    Color? surfaceBright,
    Color? surfaceContainerLowest,
    Color? surfaceContainerLow,
    Color? surfaceContainer,
    Color? surfaceContainerHigh,
    Color? surfaceContainerHighest,
    Color? onSurfaceVariant,
    Color? outline,
    Color? outlineVariant,
    Color? shadow,
    Color? scrim,
    Color? inverseSurface,
    Color? onInverseSurface,
    Color? inversePrimary,
    Color? surfaceTint,
  }) : _primaryContainer = primaryContainer,
       _onPrimaryContainer = onPrimaryContainer,
       _primaryFixed = primaryFixed,
       _primaryFixedDim = primaryFixedDim,
       _onPrimaryFixed = onPrimaryFixed,
       _onPrimaryFixedVariant = onPrimaryFixedVariant,
       _secondaryContainer = secondaryContainer,
       _onSecondaryContainer = onSecondaryContainer,
       _secondaryFixed = secondaryFixed,
       _secondaryFixedDim = secondaryFixedDim,
       _onSecondaryFixed = onSecondaryFixed,
       _onSecondaryFixedVariant = onSecondaryFixedVariant,
       _tertiary = tertiary,
       _onTertiary = onTertiary,
       _tertiaryContainer = tertiaryContainer,
       _onTertiaryContainer = onTertiaryContainer,
       _tertiaryFixed = tertiaryFixed,
       _tertiaryFixedDim = tertiaryFixedDim,
       _onTertiaryFixed = onTertiaryFixed,
       _onTertiaryFixedVariant = onTertiaryFixedVariant,
       _errorContainer = errorContainer,
       _onErrorContainer = onErrorContainer,
       _surfaceDim = surfaceDim,
       _surfaceBright = surfaceBright,
       _surfaceContainerLowest = surfaceContainerLowest,
       _surfaceContainerLow = surfaceContainerLow,
       _surfaceContainer = surfaceContainer,
       _surfaceContainerHigh = surfaceContainerHigh,
       _surfaceContainerHighest = surfaceContainerHighest,
       _onSurfaceVariant = onSurfaceVariant,
       _outline = outline,
       _outlineVariant = outlineVariant,
       _shadow = shadow,
       _scrim = scrim,
       _inverseSurface = inverseSurface,
       _onInverseSurface = onInverseSurface,
       _inversePrimary = inversePrimary,
       _surfaceTint = surfaceTint;

  const ColorScheme.dark({
    this.brightness = Brightness.dark,
    this.primary = const Color(0xffbb86fc),
    this.onPrimary = const Color(0xFF000000),
    Color? primaryContainer,
    Color? onPrimaryContainer,
    Color? primaryFixed,
    Color? primaryFixedDim,
    Color? onPrimaryFixed,
    Color? onPrimaryFixedVariant,
    this.secondary = const Color(0xff03dac6),
    this.onSecondary = const Color(0xFF000000),
    Color? secondaryContainer,
    Color? onSecondaryContainer,
    Color? secondaryFixed,
    Color? secondaryFixedDim,
    Color? onSecondaryFixed,
    Color? onSecondaryFixedVariant,
    Color? tertiary,
    Color? onTertiary,
    Color? tertiaryContainer,
    Color? onTertiaryContainer,
    Color? tertiaryFixed,
    Color? tertiaryFixedDim,
    Color? onTertiaryFixed,
    Color? onTertiaryFixedVariant,
    this.error = const Color(0xffcf6679),
    this.onError = const Color(0xFF000000),
    Color? errorContainer,
    Color? onErrorContainer,
    this.surface = const Color(0xff121212),
    this.onSurface = const Color(0xFFFFFFFF),
    Color? surfaceDim,
    Color? surfaceBright,
    Color? surfaceContainerLowest,
    Color? surfaceContainerLow,
    Color? surfaceContainer,
    Color? surfaceContainerHigh,
    Color? surfaceContainerHighest,
    Color? onSurfaceVariant,
    Color? outline,
    Color? outlineVariant,
    Color? shadow,
    Color? scrim,
    Color? inverseSurface,
    Color? onInverseSurface,
    Color? inversePrimary,
    Color? surfaceTint,
  }) : _primaryContainer = primaryContainer,
       _onPrimaryContainer = onPrimaryContainer,
       _primaryFixed = primaryFixed,
       _primaryFixedDim = primaryFixedDim,
       _onPrimaryFixed = onPrimaryFixed,
       _onPrimaryFixedVariant = onPrimaryFixedVariant,
       _secondaryContainer = secondaryContainer,
       _onSecondaryContainer = onSecondaryContainer,
       _secondaryFixed = secondaryFixed,
       _secondaryFixedDim = secondaryFixedDim,
       _onSecondaryFixed = onSecondaryFixed,
       _onSecondaryFixedVariant = onSecondaryFixedVariant,
       _tertiary = tertiary,
       _onTertiary = onTertiary,
       _tertiaryContainer = tertiaryContainer,
       _onTertiaryContainer = onTertiaryContainer,
       _tertiaryFixed = tertiaryFixed,
       _tertiaryFixedDim = tertiaryFixedDim,
       _onTertiaryFixed = onTertiaryFixed,
       _onTertiaryFixedVariant = onTertiaryFixedVariant,
       _errorContainer = errorContainer,
       _onErrorContainer = onErrorContainer,
       _surfaceDim = surfaceDim,
       _surfaceBright = surfaceBright,
       _surfaceContainerLowest = surfaceContainerLowest,
       _surfaceContainerLow = surfaceContainerLow,
       _surfaceContainer = surfaceContainer,
       _surfaceContainerHigh = surfaceContainerHigh,
       _surfaceContainerHighest = surfaceContainerHighest,
       _onSurfaceVariant = onSurfaceVariant,
       _outline = outline,
       _outlineVariant = outlineVariant,
       _shadow = shadow,
       _scrim = scrim,
       _inverseSurface = inverseSurface,
       _onInverseSurface = onInverseSurface,
       _inversePrimary = inversePrimary,
       _surfaceTint = surfaceTint;

  final Brightness brightness;
  final Color primary;
  final Color onPrimary;

  final Color? _primaryContainer;
  Color get primaryContainer => _primaryContainer ?? primary;

  final Color? _onPrimaryContainer;
  Color get onPrimaryContainer => _onPrimaryContainer ?? onPrimary;

  final Color? _primaryFixed;
  Color get primaryFixed => _primaryFixed ?? primary;

  final Color? _primaryFixedDim;
  Color get primaryFixedDim => _primaryFixedDim ?? primary;

  final Color? _onPrimaryFixed;
  Color get onPrimaryFixed => _onPrimaryFixed ?? onPrimary;

  final Color? _onPrimaryFixedVariant;
  Color get onPrimaryFixedVariant => _onPrimaryFixedVariant ?? onPrimary;
  final Color secondary;
  final Color onSecondary;

  final Color? _secondaryContainer;
  Color get secondaryContainer => _secondaryContainer ?? secondary;

  final Color? _onSecondaryContainer;
  Color get onSecondaryContainer => _onSecondaryContainer ?? onSecondary;

  final Color? _secondaryFixed;
  Color get secondaryFixed => _secondaryFixed ?? secondary;

  final Color? _secondaryFixedDim;
  Color get secondaryFixedDim => _secondaryFixedDim ?? secondary;

  final Color? _onSecondaryFixed;
  Color get onSecondaryFixed => _onSecondaryFixed ?? onSecondary;

  final Color? _onSecondaryFixedVariant;
  Color get onSecondaryFixedVariant => _onSecondaryFixedVariant ?? onSecondary;

  final Color? _tertiary;
  Color get tertiary => _tertiary ?? secondary;

  final Color? _onTertiary;
  Color get onTertiary => _onTertiary ?? onSecondary;

  final Color? _tertiaryContainer;
  Color get tertiaryContainer => _tertiaryContainer ?? tertiary;

  final Color? _onTertiaryContainer;
  Color get onTertiaryContainer => _onTertiaryContainer ?? onTertiary;

  final Color? _tertiaryFixed;
  Color get tertiaryFixed => _tertiaryFixed ?? tertiary;

  final Color? _tertiaryFixedDim;
  Color get tertiaryFixedDim => _tertiaryFixedDim ?? tertiary;

  final Color? _onTertiaryFixed;
  Color get onTertiaryFixed => _onTertiaryFixed ?? onTertiary;

  final Color? _onTertiaryFixedVariant;
  Color get onTertiaryFixedVariant => _onTertiaryFixedVariant ?? onTertiary;
  final Color error;
  final Color onError;

  final Color? _errorContainer;
  Color get errorContainer => _errorContainer ?? error;

  final Color? _onErrorContainer;
  Color get onErrorContainer => _onErrorContainer ?? onError;
  final Color surface;
  final Color onSurface;

  final Color? _surfaceDim;
  Color get surfaceDim => _surfaceDim ?? surface;

  final Color? _surfaceBright;
  Color get surfaceBright => _surfaceBright ?? surface;

  final Color? _surfaceContainerLowest;
  Color get surfaceContainerLowest => _surfaceContainerLowest ?? surface;

  final Color? _surfaceContainerLow;
  Color get surfaceContainerLow => _surfaceContainerLow ?? surface;

  final Color? _surfaceContainer;
  Color get surfaceContainer => _surfaceContainer ?? surface;

  final Color? _surfaceContainerHigh;
  Color get surfaceContainerHigh => _surfaceContainerHigh ?? surface;

  final Color? _surfaceContainerHighest;
  Color get surfaceContainerHighest => _surfaceContainerHighest ?? surface;

  final Color? _onSurfaceVariant;
  Color get onSurfaceVariant => _onSurfaceVariant ?? onSurface;

  final Color? _outline;
  Color get outline => _outline ?? onSurface;

  final Color? _outlineVariant;
  Color get outlineVariant => _outlineVariant ?? onSurface;

  final Color? _shadow;
  Color get shadow => _shadow ?? const Color(0xff000000);

  final Color? _scrim;
  Color get scrim => _scrim ?? const Color(0xff000000);

  final Color? _inverseSurface;
  Color get inverseSurface => _inverseSurface ?? onSurface;

  final Color? _onInverseSurface;
  Color get onInverseSurface => _onInverseSurface ?? surface;

  final Color? _inversePrimary;
  Color get inversePrimary => _inversePrimary ?? onPrimary;

  final Color? _surfaceTint;
  Color get surfaceTint => _surfaceTint ?? primary;

  ColorScheme copyWith({
    Brightness? brightness,
    Color? primary,
    Color? onPrimary,
    Color? primaryContainer,
    Color? onPrimaryContainer,
    Color? primaryFixed,
    Color? primaryFixedDim,
    Color? onPrimaryFixed,
    Color? onPrimaryFixedVariant,
    Color? secondary,
    Color? onSecondary,
    Color? secondaryContainer,
    Color? onSecondaryContainer,
    Color? secondaryFixed,
    Color? secondaryFixedDim,
    Color? onSecondaryFixed,
    Color? onSecondaryFixedVariant,
    Color? tertiary,
    Color? onTertiary,
    Color? tertiaryContainer,
    Color? onTertiaryContainer,
    Color? tertiaryFixed,
    Color? tertiaryFixedDim,
    Color? onTertiaryFixed,
    Color? onTertiaryFixedVariant,
    Color? error,
    Color? onError,
    Color? errorContainer,
    Color? onErrorContainer,
    Color? surface,
    Color? onSurface,
    Color? surfaceDim,
    Color? surfaceBright,
    Color? surfaceContainerLowest,
    Color? surfaceContainerLow,
    Color? surfaceContainer,
    Color? surfaceContainerHigh,
    Color? surfaceContainerHighest,
    Color? onSurfaceVariant,
    Color? outline,
    Color? outlineVariant,
    Color? shadow,
    Color? scrim,
    Color? inverseSurface,
    Color? onInverseSurface,
    Color? inversePrimary,
    Color? surfaceTint,
  }) {
    return ColorScheme(
      brightness: brightness ?? this.brightness,
      primary: primary ?? this.primary,
      onPrimary: onPrimary ?? this.onPrimary,
      primaryContainer: primaryContainer ?? this.primaryContainer,
      onPrimaryContainer: onPrimaryContainer ?? this.onPrimaryContainer,
      primaryFixed: primaryFixed ?? this.primaryFixed,
      primaryFixedDim: primaryFixedDim ?? this.primaryFixedDim,
      onPrimaryFixed: onPrimaryFixed ?? this.onPrimaryFixed,
      onPrimaryFixedVariant:
          onPrimaryFixedVariant ?? this.onPrimaryFixedVariant,
      secondary: secondary ?? this.secondary,
      onSecondary: onSecondary ?? this.onSecondary,
      secondaryContainer: secondaryContainer ?? this.secondaryContainer,
      onSecondaryContainer: onSecondaryContainer ?? this.onSecondaryContainer,
      secondaryFixed: secondaryFixed ?? this.secondaryFixed,
      secondaryFixedDim: secondaryFixedDim ?? this.secondaryFixedDim,
      onSecondaryFixed: onSecondaryFixed ?? this.onSecondaryFixed,
      onSecondaryFixedVariant:
          onSecondaryFixedVariant ?? this.onSecondaryFixedVariant,
      tertiary: tertiary ?? this.tertiary,
      onTertiary: onTertiary ?? this.onTertiary,
      tertiaryContainer: tertiaryContainer ?? this.tertiaryContainer,
      onTertiaryContainer: onTertiaryContainer ?? this.onTertiaryContainer,
      tertiaryFixed: tertiaryFixed ?? this.tertiaryFixed,
      tertiaryFixedDim: tertiaryFixedDim ?? this.tertiaryFixedDim,
      onTertiaryFixed: onTertiaryFixed ?? this.onTertiaryFixed,
      onTertiaryFixedVariant:
          onTertiaryFixedVariant ?? this.onTertiaryFixedVariant,
      error: error ?? this.error,
      onError: onError ?? this.onError,
      errorContainer: errorContainer ?? this.errorContainer,
      onErrorContainer: onErrorContainer ?? this.onErrorContainer,
      surface: surface ?? this.surface,
      onSurface: onSurface ?? this.onSurface,
      surfaceDim: surfaceDim ?? this.surfaceDim,
      surfaceBright: surfaceBright ?? this.surfaceBright,
      surfaceContainerLowest:
          surfaceContainerLowest ?? this.surfaceContainerLowest,
      surfaceContainerLow: surfaceContainerLow ?? this.surfaceContainerLow,
      surfaceContainer: surfaceContainer ?? this.surfaceContainer,
      surfaceContainerHigh: surfaceContainerHigh ?? this.surfaceContainerHigh,
      surfaceContainerHighest:
          surfaceContainerHighest ?? this.surfaceContainerHighest,
      onSurfaceVariant: onSurfaceVariant ?? this.onSurfaceVariant,
      outline: outline ?? this.outline,
      outlineVariant: outlineVariant ?? this.outlineVariant,
      shadow: shadow ?? this.shadow,
      scrim: scrim ?? this.scrim,
      inverseSurface: inverseSurface ?? this.inverseSurface,
      onInverseSurface: onInverseSurface ?? this.onInverseSurface,
      inversePrimary: inversePrimary ?? this.inversePrimary,
      surfaceTint: surfaceTint ?? this.surfaceTint,
    );
  }

  static ColorScheme lerp(ColorScheme a, ColorScheme b, double t) {
    if (identical(a, b)) {
      return a;
    }
    return ColorScheme(
      brightness: t < 0.5 ? a.brightness : b.brightness,
      primary: Color.lerp(a.primary, b.primary, t)!,
      onPrimary: Color.lerp(a.onPrimary, b.onPrimary, t)!,
      primaryContainer: Color.lerp(a.primaryContainer, b.primaryContainer, t),
      onPrimaryContainer: Color.lerp(
        a.onPrimaryContainer,
        b.onPrimaryContainer,
        t,
      ),
      primaryFixed: Color.lerp(a.primaryFixed, b.primaryFixed, t),
      primaryFixedDim: Color.lerp(a.primaryFixedDim, b.primaryFixedDim, t),
      onPrimaryFixed: Color.lerp(a.onPrimaryFixed, b.onPrimaryFixed, t),
      onPrimaryFixedVariant: Color.lerp(
        a.onPrimaryFixedVariant,
        b.onPrimaryFixedVariant,
        t,
      ),
      secondary: Color.lerp(a.secondary, b.secondary, t)!,
      onSecondary: Color.lerp(a.onSecondary, b.onSecondary, t)!,
      secondaryContainer: Color.lerp(
        a.secondaryContainer,
        b.secondaryContainer,
        t,
      ),
      onSecondaryContainer: Color.lerp(
        a.onSecondaryContainer,
        b.onSecondaryContainer,
        t,
      ),
      secondaryFixed: Color.lerp(a.secondaryFixed, b.secondaryFixed, t),
      secondaryFixedDim: Color.lerp(
        a.secondaryFixedDim,
        b.secondaryFixedDim,
        t,
      ),
      onSecondaryFixed: Color.lerp(a.onSecondaryFixed, b.onSecondaryFixed, t),
      onSecondaryFixedVariant: Color.lerp(
        a.onSecondaryFixedVariant,
        b.onSecondaryFixedVariant,
        t,
      ),
      tertiary: Color.lerp(a.tertiary, b.tertiary, t),
      onTertiary: Color.lerp(a.onTertiary, b.onTertiary, t),
      tertiaryContainer: Color.lerp(
        a.tertiaryContainer,
        b.tertiaryContainer,
        t,
      ),
      onTertiaryContainer: Color.lerp(
        a.onTertiaryContainer,
        b.onTertiaryContainer,
        t,
      ),
      tertiaryFixed: Color.lerp(a.tertiaryFixed, b.tertiaryFixed, t),
      tertiaryFixedDim: Color.lerp(a.tertiaryFixedDim, b.tertiaryFixedDim, t),
      onTertiaryFixed: Color.lerp(a.onTertiaryFixed, b.onTertiaryFixed, t),
      onTertiaryFixedVariant: Color.lerp(
        a.onTertiaryFixedVariant,
        b.onTertiaryFixedVariant,
        t,
      ),
      error: Color.lerp(a.error, b.error, t)!,
      onError: Color.lerp(a.onError, b.onError, t)!,
      errorContainer: Color.lerp(a.errorContainer, b.errorContainer, t),
      onErrorContainer: Color.lerp(a.onErrorContainer, b.onErrorContainer, t),
      surface: Color.lerp(a.surface, b.surface, t)!,
      onSurface: Color.lerp(a.onSurface, b.onSurface, t)!,
      surfaceDim: Color.lerp(a.surfaceDim, b.surfaceDim, t),
      surfaceBright: Color.lerp(a.surfaceBright, b.surfaceBright, t),
      surfaceContainerLowest: Color.lerp(
        a.surfaceContainerLowest,
        b.surfaceContainerLowest,
        t,
      ),
      surfaceContainerLow: Color.lerp(
        a.surfaceContainerLow,
        b.surfaceContainerLow,
        t,
      ),
      surfaceContainer: Color.lerp(a.surfaceContainer, b.surfaceContainer, t),
      surfaceContainerHigh: Color.lerp(
        a.surfaceContainerHigh,
        b.surfaceContainerHigh,
        t,
      ),
      surfaceContainerHighest: Color.lerp(
        a.surfaceContainerHighest,
        b.surfaceContainerHighest,
        t,
      ),
      onSurfaceVariant: Color.lerp(a.onSurfaceVariant, b.onSurfaceVariant, t),
      outline: Color.lerp(a.outline, b.outline, t),
      outlineVariant: Color.lerp(a.outlineVariant, b.outlineVariant, t),
      shadow: Color.lerp(a.shadow, b.shadow, t),
      scrim: Color.lerp(a.scrim, b.scrim, t),
      inverseSurface: Color.lerp(a.inverseSurface, b.inverseSurface, t),
      onInverseSurface: Color.lerp(a.onInverseSurface, b.onInverseSurface, t),
      inversePrimary: Color.lerp(a.inversePrimary, b.inversePrimary, t),
      surfaceTint: Color.lerp(a.surfaceTint, b.surfaceTint, t),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other.runtimeType != runtimeType) {
      return false;
    }
    return other is ColorScheme &&
        other.brightness == brightness &&
        other.primary == primary &&
        other.onPrimary == onPrimary &&
        other.primaryContainer == primaryContainer &&
        other.onPrimaryContainer == onPrimaryContainer &&
        other.primaryFixed == primaryFixed &&
        other.primaryFixedDim == primaryFixedDim &&
        other.onPrimaryFixed == onPrimaryFixed &&
        other.onPrimaryFixedVariant == onPrimaryFixedVariant &&
        other.secondary == secondary &&
        other.onSecondary == onSecondary &&
        other.secondaryContainer == secondaryContainer &&
        other.onSecondaryContainer == onSecondaryContainer &&
        other.secondaryFixed == secondaryFixed &&
        other.secondaryFixedDim == secondaryFixedDim &&
        other.onSecondaryFixed == onSecondaryFixed &&
        other.onSecondaryFixedVariant == onSecondaryFixedVariant &&
        other.tertiary == tertiary &&
        other.onTertiary == onTertiary &&
        other.tertiaryContainer == tertiaryContainer &&
        other.onTertiaryContainer == onTertiaryContainer &&
        other.tertiaryFixed == tertiaryFixed &&
        other.tertiaryFixedDim == tertiaryFixedDim &&
        other.onTertiaryFixed == onTertiaryFixed &&
        other.onTertiaryFixedVariant == onTertiaryFixedVariant &&
        other.error == error &&
        other.onError == onError &&
        other.errorContainer == errorContainer &&
        other.onErrorContainer == onErrorContainer &&
        other.surface == surface &&
        other.onSurface == onSurface &&
        other.surfaceDim == surfaceDim &&
        other.surfaceBright == surfaceBright &&
        other.surfaceContainerLowest == surfaceContainerLowest &&
        other.surfaceContainerLow == surfaceContainerLow &&
        other.surfaceContainer == surfaceContainer &&
        other.surfaceContainerHigh == surfaceContainerHigh &&
        other.surfaceContainerHighest == surfaceContainerHighest &&
        other.onSurfaceVariant == onSurfaceVariant &&
        other.outline == outline &&
        other.outlineVariant == outlineVariant &&
        other.shadow == shadow &&
        other.scrim == scrim &&
        other.inverseSurface == inverseSurface &&
        other.onInverseSurface == onInverseSurface &&
        other.inversePrimary == inversePrimary &&
        other.surfaceTint == surfaceTint;
  }

  @override
  int get hashCode => Object.hash(
    brightness,
    primary,
    onPrimary,
    primaryContainer,
    onPrimaryContainer,
    secondary,
    onSecondary,
    secondaryContainer,
    onSecondaryContainer,
    tertiary,
    onTertiary,
    tertiaryContainer,
    onTertiaryContainer,
    error,
    onError,
    errorContainer,
    onErrorContainer,
    Object.hash(
      surface,
      onSurface,
      surfaceDim,
      surfaceBright,
      surfaceContainerLowest,
      surfaceContainerLow,
      surfaceContainer,
      surfaceContainerHigh,
      surfaceContainerHighest,
      onSurfaceVariant,
      outline,
      outlineVariant,
      shadow,
      scrim,
      inverseSurface,
      onInverseSurface,
      inversePrimary,
      surfaceTint,
      Object.hash(
        primaryFixed,
        primaryFixedDim,
        onPrimaryFixed,
        onPrimaryFixedVariant,
        secondaryFixed,
        secondaryFixedDim,
        onSecondaryFixed,
        onSecondaryFixedVariant,
        tertiaryFixed,
        tertiaryFixedDim,
        onTertiaryFixed,
        onTertiaryFixedVariant,
      ),
    ),
  );
}
