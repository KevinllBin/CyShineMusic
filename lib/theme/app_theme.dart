import 'package:flutter/material.dart';

import 'app_motion.dart';
import 'color_style.dart';
import 'custom_theme.dart';

class AppTheme {
  const AppTheme._();

  static const Color designSeed = Colors.blue;

  /// Same CJK stack the player lyrics render with, so body text across the
  /// app matches the lyric typography.
  static const List<String> fontFallback = [
    'Noto Sans CJK SC',
    'Source Han Sans SC',
    'HarmonyOS Sans SC',
    'PingFang SC',
    'Microsoft YaHei',
  ];

  static ThemeData light([
    Color seed = designSeed,
    AppColorStyle style = AppColorStyle.fallback,
  ]) => _build(Brightness.light, seed, style);

  static ThemeData dark([
    Color seed = designSeed,
    AppColorStyle style = AppColorStyle.fallback,
  ]) => _build(Brightness.dark, seed, style);

  static ThemeData fromScheme(
    ColorScheme scheme, {
    CustomThemeColors? colors,
    AppColorStyle style = AppColorStyle.fallback,
  }) => _buildFromScheme(scheme, colors: colors, style: style);

  /// 用给定风格展开种子色。设置页的风格预览也走这里，保证预览与实际一致。
  static ColorScheme schemeFor(
    Color seed,
    Brightness brightness,
    AppColorStyle style,
  ) => ColorScheme.fromSeed(
    seedColor: seed,
    brightness: brightness,
    dynamicSchemeVariant: style.variant,
  );

  static ThemeData _build(
    Brightness brightness,
    Color seed,
    AppColorStyle style,
  ) {
    return _buildFromScheme(schemeFor(seed, brightness, style));
  }

  static ThemeData _buildFromScheme(
    ColorScheme base, {
    CustomThemeColors? colors,
    AppColorStyle style = AppColorStyle.fallback,
  }) {
    final scheme = colors?.applyTo(base, style) ?? base;
    final theme = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      extensions: [AppThemeBase(base)],
      // NavigationBar 会把 32dp 的指示胶囊和标签在这个高度里垂直居中，
      // 内容本身约 52dp；再往下压会被 loose 约束挤扁并溢出到背景之外。
      navigationBarTheme: const NavigationBarThemeData(height: 64),
      fontFamilyFallback: fontFallback,
      scaffoldBackgroundColor: colors?.background ?? base.appSurface,
      visualDensity: VisualDensity.standard,
      splashFactory: InkRipple.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        scrolledUnderElevation: 2,
        surfaceTintColor: scheme.surfaceTint,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 22,
          fontWeight: FontWeight.w500,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.appContainerLow,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(20)),
        ),
      ),
      chipTheme: ChipThemeData(
        labelStyle: TextStyle(color: scheme.onSurfaceVariant),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurfaceVariant,
        textColor: scheme.onSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: colors?.container ?? base.appInputFill,
        hoverColor: scheme.onSurface.withValues(alpha: 0.04),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: scheme.error, width: 1.6),
        ),
        labelStyle: TextStyle(color: scheme.onSurfaceVariant),
        hintStyle: TextStyle(color: scheme.onSurfaceVariant),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        backgroundColor: scheme.appContainerHigh,
        contentTextStyle: TextStyle(color: scheme.onSurface),
        actionTextColor: scheme.primary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.appContainerHigh,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(28)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(72, 48),
          shape: const StadiumBorder(),
        ).copyWith(animationDuration: AppMotion.medium),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(72, 48),
          shape: const StadiumBorder(),
          side: BorderSide(color: scheme.outline),
        ).copyWith(animationDuration: AppMotion.medium),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: const CircleBorder(),
        ).copyWith(animationDuration: AppMotion.medium),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: scheme.outline),
            ),
          ),
        ),
      ),
      searchBarTheme: SearchBarThemeData(
        elevation: const WidgetStatePropertyAll(0),
        backgroundColor: WidgetStatePropertyAll(
          colors?.container ?? base.appInputFill,
        ),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        side: WidgetStatePropertyAll(BorderSide(color: scheme.outlineVariant)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        ),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 16),
        ),
      ),
      searchViewTheme: SearchViewThemeData(
        backgroundColor: scheme.appContainerHigh,
        surfaceTintColor: Colors.transparent,
        side: BorderSide(color: scheme.outlineVariant),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),
    );
    if (colors == null ||
        (colors.text == null &&
            colors.background == null &&
            colors.container == null)) {
      return theme;
    }
    return theme.copyWith(
      textTheme: theme.textTheme.apply(
        bodyColor: scheme.onSurface,
        displayColor: scheme.onSurface,
      ),
    );
  }
}

/// Keep the original scheme so resetting a field in the editor also works
/// when the system's dynamic colors form the base of a custom theme.
class AppThemeBase extends ThemeExtension<AppThemeBase> {
  const AppThemeBase(this.scheme);

  final ColorScheme scheme;

  @override
  bool operator ==(Object other) =>
      other is AppThemeBase && scheme == other.scheme;

  @override
  int get hashCode => scheme.hashCode;

  @override
  AppThemeBase copyWith({ColorScheme? scheme}) =>
      AppThemeBase(scheme ?? this.scheme);

  @override
  AppThemeBase lerp(covariant AppThemeBase? other, double t) => other == null
      ? this
      : AppThemeBase(ColorScheme.lerp(scheme, other.scheme, t));
}

extension AppColorScheme on ColorScheme {
  Color get appSurface => surfaceContainerLow.withValues(alpha: 1);

  Color get appContainerLow => surfaceContainerLow;

  Color get appContainerHigh => surfaceContainerHigh;

  Color get appContainerHighest => surfaceContainerHighest;

  Color get appInputFill =>
      _blendPrimary(brightness == Brightness.dark ? 0.14 : 0.07);

  Color _blendPrimary(double alpha) {
    return Color.alphaBlend(
      primary.withValues(alpha: alpha),
      appSurface,
    ).withValues(alpha: 1);
  }
}
