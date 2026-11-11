import 'package:flutter/material.dart';

import 'color_style.dart';

enum ThemeColorRole {
  accent('accent', '强调色'),
  background('background', '页面背景'),
  container('container', '卡片与弹窗'),
  text('text', '主文字'),
  secondaryText('secondaryText', '次要文字');

  const ThemeColorRole(this.code, this.label);

  final String code;
  final String label;
}

@immutable
class CustomThemeColors {
  const CustomThemeColors({
    this.accent,
    this.background,
    this.container,
    this.text,
    this.secondaryText,
  });

  final Color? accent;
  final Color? background;
  final Color? container;
  final Color? text;
  final Color? secondaryText;

  Color? colorFor(ThemeColorRole role) => switch (role) {
    ThemeColorRole.accent => accent,
    ThemeColorRole.background => background,
    ThemeColorRole.container => container,
    ThemeColorRole.text => text,
    ThemeColorRole.secondaryText => secondaryText,
  };

  CustomThemeColors withColor(ThemeColorRole role, Color? color) {
    final opaque = color?.withValues(alpha: 1);
    return CustomThemeColors(
      accent: role == ThemeColorRole.accent ? opaque : accent,
      background: role == ThemeColorRole.background ? opaque : background,
      container: role == ThemeColorRole.container ? opaque : container,
      text: role == ThemeColorRole.text ? opaque : text,
      secondaryText: role == ThemeColorRole.secondaryText
          ? opaque
          : secondaryText,
    );
  }

  Map<String, dynamic> toJson() => {
    for (final role in ThemeColorRole.values)
      if (colorFor(role) case final color?) role.code: color.toARGB32(),
  };

  factory CustomThemeColors.fromJson(Object? value) {
    if (value is! Map) throw const FormatException('自定义配色格式无效');
    var colors = const CustomThemeColors();
    for (final role in ThemeColorRole.values) {
      final raw = value[role.code];
      if (raw == null) continue;
      if (raw is! int || raw < 0xFF000000 || raw > 0xFFFFFFFF) {
        throw FormatException('${role.label}必须是不透明的 ARGB 颜色');
      }
      colors = colors.withColor(role, Color(raw));
    }
    return colors;
  }

  ColorScheme applyTo(ColorScheme base, AppColorStyle style) {
    var scheme = base;
    if (accent case final accent?) {
      final accents = ColorScheme.fromSeed(
        seedColor: accent,
        brightness: base.brightness,
        dynamicSchemeVariant: style.variant,
      );
      // Change the whole accent family: chips use secondaryContainer,
      // capsule navigation uses primary, and highlighted cards use
      // primaryContainer.
      // None of the generated surface colors are copied into the base theme.
      scheme = scheme.copyWith(
        primary: accent,
        onPrimary: _accentForeground(accent),
        primaryContainer: accents.primaryContainer,
        onPrimaryContainer: _accentForeground(accents.primaryContainer),
        primaryFixed: accents.primaryFixed,
        primaryFixedDim: accents.primaryFixedDim,
        onPrimaryFixed: accents.onPrimaryFixed,
        onPrimaryFixedVariant: accents.onPrimaryFixedVariant,
        secondary: accents.secondary,
        onSecondary: accents.onSecondary,
        secondaryContainer: accents.secondaryContainer,
        onSecondaryContainer: accents.onSecondaryContainer,
        secondaryFixed: accents.secondaryFixed,
        secondaryFixedDim: accents.secondaryFixedDim,
        onSecondaryFixed: accents.onSecondaryFixed,
        onSecondaryFixedVariant: accents.onSecondaryFixedVariant,
        tertiary: accents.tertiary,
        onTertiary: accents.onTertiary,
        tertiaryContainer: accents.tertiaryContainer,
        onTertiaryContainer: accents.onTertiaryContainer,
        tertiaryFixed: accents.tertiaryFixed,
        tertiaryFixedDim: accents.tertiaryFixedDim,
        onTertiaryFixed: accents.onTertiaryFixed,
        onTertiaryFixedVariant: accents.onTertiaryFixedVariant,
        // Elevation must not recolor a custom background with the accent.
        surfaceTint: Colors.transparent,
      );
    }
    scheme = scheme.copyWith(
      surface: background,
      surfaceDim: background,
      surfaceBright: background,
      surfaceContainerLowest: container,
      surfaceContainerLow: container,
      surfaceContainer: container,
      surfaceContainerHigh: container,
      surfaceContainerHighest: container,
    );
    if (background != null || container != null || text != null) {
      final ink =
          text ??
          readableForeground([
            background ?? base.surface,
            background ?? base.surfaceContainerLow,
            scheme.surfaceContainerLowest,
            scheme.surfaceContainerLow,
            scheme.surfaceContainerHigh,
            scheme.surfaceContainerHighest,
          ]);
      final muted = secondaryText ?? ink.withValues(alpha: 0.72);
      scheme = scheme.copyWith(
        onSurface: ink,
        onSurfaceVariant: muted,
        outline: muted,
        outlineVariant: ink.withValues(alpha: 0.22),
        surfaceTint: Colors.transparent,
      );
    } else if (secondaryText != null) {
      scheme = scheme.copyWith(
        onSurfaceVariant: secondaryText,
        outline: secondaryText,
      );
    }
    return scheme;
  }
}

/// Keep medium accents visually consistent instead of switching to black
/// as soon as it narrowly wins the contrast comparison. Light accents still
/// use dark ink once white falls below 3:1 contrast (luminance above 0.30).
/// This policy only applies to primary controls; page text keeps its own rule.
Color _accentForeground(Color background) =>
    colorContrast(Colors.white, background) >= 3 ? Colors.white : Colors.black;

@immutable
class CustomTheme {
  const CustomTheme({
    this.enabled = false,
    this.light = const CustomThemeColors(),
    this.dark = const CustomThemeColors(),
  });

  final bool enabled;
  final CustomThemeColors light;
  final CustomThemeColors dark;

  CustomThemeColors colorsFor(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  CustomTheme copyWith({
    bool? enabled,
    CustomThemeColors? light,
    CustomThemeColors? dark,
  }) => CustomTheme(
    enabled: enabled ?? this.enabled,
    light: light ?? this.light,
    dark: dark ?? this.dark,
  );

  Map<String, dynamic> toJson() => {
    'version': 1,
    'enabled': enabled,
    'light': light.toJson(),
    'dark': dark.toJson(),
  };

  factory CustomTheme.fromJson(Object? value) {
    if (value is! Map || value['version'] != 1 || value['enabled'] is! bool) {
      throw const FormatException('自定义主题格式或版本无效');
    }
    return CustomTheme(
      enabled: value['enabled'] as bool,
      light: CustomThemeColors.fromJson(value['light']),
      dark: CustomThemeColors.fromJson(value['dark']),
    );
  }
}

double colorContrast(Color foreground, Color background) {
  final visible = Color.alphaBlend(foreground, background);
  final first = visible.computeLuminance();
  final second = background.computeLuminance();
  return first > second
      ? (first + 0.05) / (second + 0.05)
      : (second + 0.05) / (first + 0.05);
}

/// Pick the foreground with the best worst-case contrast across the page
/// and containers. The editor warns when those surfaces are too far apart.
Color readableForeground(List<Color> backgrounds) {
  double minimumContrast(Color ink) => backgrounds
      .map((background) => colorContrast(ink, background))
      .reduce((a, b) => a < b ? a : b);
  return minimumContrast(Colors.black) >= minimumContrast(Colors.white)
      ? Colors.black
      : Colors.white;
}
