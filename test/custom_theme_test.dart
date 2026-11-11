import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cy_shine_music/core/storage/settings_store.dart';
import 'package:cy_shine_music/theme/app_theme.dart';
import 'package:cy_shine_music/theme/color_style.dart';
import 'package:cy_shine_music/theme/custom_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final light = AppTheme.schemeFor(
    Colors.blue,
    Brightness.light,
    AppColorStyle.soft,
  );
  const custom = CustomTheme(
    enabled: true,
    light: CustomThemeColors(
      accent: Color(0xFFFF9800),
      background: Color(0xFFFFFAF0),
      container: Colors.white,
    ),
    dark: CustomThemeColors(
      accent: Color(0xFFBB86FC),
      background: Color(0xFF121212),
      container: Color(0xFF202020),
    ),
  );

  test('changing accents preserves page, container and input backgrounds', () {
    final original = AppTheme.fromScheme(light);
    final changed = AppTheme.fromScheme(
      light,
      colors: const CustomThemeColors(accent: Colors.yellow),
    );
    expect(changed.colorScheme.primary, Colors.yellow);
    expect(
      changed.colorScheme.secondaryContainer,
      isNot(original.colorScheme.secondaryContainer),
    );
    expect(changed.scaffoldBackgroundColor, original.scaffoldBackgroundColor);
    expect(changed.colorScheme.surface, original.colorScheme.surface);
    expect(changed.cardTheme.color, original.cardTheme.color);
    expect(
      changed.inputDecorationTheme.fillColor,
      original.inputDecorationTheme.fillColor,
    );
    expect(
      changed.searchBarTheme.backgroundColor,
      original.searchBarTheme.backgroundColor,
    );
    expect(
      colorContrast(changed.colorScheme.onPrimary, Colors.yellow),
      greaterThanOrEqualTo(4.5),
    );
  });

  test('medium blue keeps white foregrounds in both theme modes', () {
    // Sampled from the reported screenshot. Black narrowly wins the maximum
    // contrast comparison, but white is still readable on this blue.
    const blue = Color(0xFF3D73DD);
    expect(
      colorContrast(Colors.black, blue),
      greaterThan(colorContrast(Colors.white, blue)),
    );
    for (final brightness in Brightness.values) {
      final base = AppTheme.schemeFor(
        Colors.blue,
        brightness,
        AppColorStyle.faithful,
      );
      final changed = AppTheme.fromScheme(
        base,
        colors: const CustomThemeColors(accent: blue),
        style: AppColorStyle.faithful,
      );
      expect(changed.colorScheme.primary, blue);
      expect(changed.colorScheme.onPrimary, Colors.white);
      expect(changed.colorScheme.onPrimaryContainer, Colors.white);
      expect(
        changed.colorScheme.primaryContainer,
        AppTheme.schemeFor(
          blue,
          brightness,
          AppColorStyle.faithful,
        ).primaryContainer,
      );
      expect(changed.scaffoldBackgroundColor, base.appSurface);
      expect(changed.colorScheme.onSurface, base.onSurface);
    }
  });

  test('white changes to dark ink only when the accent becomes very light', () {
    for (final accent in [
      const Color(0xFF737373),
      const Color(0xFF777777),
      const Color(0xFF949494),
      Colors.blue,
    ]) {
      final scheme = CustomThemeColors(
        accent: accent,
      ).applyTo(light, AppColorStyle.soft);
      expect(scheme.onPrimary, Colors.white);
    }
    for (final accent in [
      const Color(0xFF959595),
      const Color(0xFFFFF59D),
      Colors.white,
    ]) {
      final scheme = CustomThemeColors(
        accent: accent,
      ).applyTo(light, AppColorStyle.soft);
      expect(scheme.onPrimary, Colors.black);
      expect(
        colorContrast(scheme.onPrimary, accent),
        greaterThanOrEqualTo(4.5),
      );
    }
  });

  test('page and container colors are independently applied', () {
    const page = Color(0xFFFFFAF0);
    const card = Colors.white;
    final backgroundOnly = AppTheme.fromScheme(
      light,
      colors: const CustomThemeColors(background: page),
    );
    expect(backgroundOnly.scaffoldBackgroundColor, page);
    expect(backgroundOnly.colorScheme.surface, page);
    expect(backgroundOnly.cardTheme.color, light.surfaceContainerLow);
    expect(backgroundOnly.colorScheme.primary, light.primary);

    final containerOnly = AppTheme.fromScheme(
      light,
      colors: const CustomThemeColors(container: card),
    );
    expect(containerOnly.scaffoldBackgroundColor, light.appSurface);
    expect(containerOnly.colorScheme.surface, light.surface);
    expect(containerOnly.cardTheme.color, card);
    expect(containerOnly.dialogTheme.backgroundColor, card);
    expect(containerOnly.bottomSheetTheme.backgroundColor, card);
    expect(containerOnly.inputDecorationTheme.fillColor, card);
    expect(containerOnly.colorScheme.primary, light.primary);
  });

  test('automatic text works on matching light and dark custom surfaces', () {
    for (final brightness in Brightness.values) {
      final base = AppTheme.schemeFor(
        Colors.blue,
        brightness,
        AppColorStyle.soft,
      );
      final theme = AppTheme.fromScheme(
        base,
        colors: custom.colorsFor(brightness),
      );
      for (final background in [
        theme.scaffoldBackgroundColor,
        theme.colorScheme.surfaceContainerLow,
      ]) {
        expect(
          colorContrast(theme.colorScheme.onSurface, background),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          colorContrast(theme.colorScheme.onSurfaceVariant, background),
          greaterThanOrEqualTo(4.5),
        );
      }
      expect(theme.textTheme.bodyMedium?.color, theme.colorScheme.onSurface);
    }
  });

  test('explicit text wins and resetting a field restores its base', () {
    const colors = CustomThemeColors(
      background: Color(0xFFFFFAF0),
      container: Colors.white,
      text: Color(0xFF123456),
      secondaryText: Color(0xFF456789),
    );
    final theme = AppTheme.fromScheme(light, colors: colors);
    expect(theme.colorScheme.onSurface, colors.text);
    expect(theme.colorScheme.onSurfaceVariant, colors.secondaryText);
    expect(theme.colorScheme.outline, colors.secondaryText);
    expect(theme.textTheme.bodyMedium?.color, colors.text);
    final reset = AppTheme.fromScheme(
      light,
      colors: colors.withColor(ThemeColorRole.background, null),
    );
    expect(reset.scaffoldBackgroundColor, light.appSurface);
    expect(reset.cardTheme.color, colors.container);
    expect(reset.colorScheme.onSurface, colors.text);
    expect(reset.extension<AppThemeBase>()?.scheme, light);
  });

  test(
    'theme serialization preserves both modes and rejects invalid colors',
    () {
      expect(CustomTheme.fromJson(custom.toJson()).toJson(), custom.toJson());
      expect(
        () => CustomThemeColors.fromJson({'accent': 0x00123456}),
        throwsFormatException,
      );
      expect(
        () => CustomThemeColors.fromJson({'text': 'FF123456'}),
        throwsFormatException,
      );
      expect(
        () => CustomTheme.fromJson({...custom.toJson(), 'version': 2}),
        throwsFormatException,
      );
    },
  );

  test(
    'defaults preserve old themes and enabling custom disables playlist colors',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final container = _container(prefs);
      final notifier = container.read(settingsProvider.notifier);
      expect(container.read(settingsProvider).customTheme.enabled, isFalse);
      expect(
        container.read(settingsProvider).playlistArtworkColorsEnabled,
        isTrue,
      );
      await notifier.setCustomTheme(custom);
      expect(
        container.read(settingsProvider).playlistArtworkColorsEnabled,
        isFalse,
      );
      await notifier.setPlaylistArtworkColorsEnabled(true);
      await notifier.setCustomTheme(custom.copyWith(light: custom.dark));
      expect(
        container.read(settingsProvider).playlistArtworkColorsEnabled,
        isTrue,
      );
      container.dispose();

      final restored = _container(prefs);
      addTearDown(restored.dispose);
      expect(
        restored.read(settingsProvider).customTheme.light.toJson(),
        custom.dark.toJson(),
      );
      expect(
        restored.read(settingsProvider).customTheme.dark.toJson(),
        custom.dark.toJson(),
      );
      expect(
        restored.read(settingsProvider).playlistArtworkColorsEnabled,
        isTrue,
      );
      expect(restored.read(settingsProvider).flowingLightEnabled, isTrue);
    },
  );

  test(
    'appearance sync restores custom themes, explicit opt-in and resets',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final container = _container(prefs);
      addTearDown(container.dispose);
      final notifier = container.read(settingsProvider.notifier);
      await notifier.setCustomTheme(custom);
      final exported = notifier.exportAppearanceForSync();
      await notifier.setCustomTheme(const CustomTheme());
      await notifier.applyAppearanceFromSync({
        ...exported,
        'playlistArtworkColorsEnabled': true,
      });
      expect(
        container.read(settingsProvider).customTheme.toJson(),
        custom.toJson(),
      );
      expect(
        container.read(settingsProvider).playlistArtworkColorsEnabled,
        isTrue,
      );
      await notifier.applyAppearanceFromSync({
        ...exported,
        'customTheme': const CustomTheme().toJson(),
      });
      expect(
        container.read(settingsProvider).customTheme.toJson(),
        const CustomTheme().toJson(),
      );
    },
  );

  test(
    'old appearance payloads preserve local custom theme and playlist toggle',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final container = _container(prefs);
      addTearDown(container.dispose);
      final notifier = container.read(settingsProvider.notifier);
      await notifier.setCustomTheme(custom);
      await notifier.applyAppearanceFromSync({
        'themeMode': 'dark',
        'themeSeedArgb': Colors.red.toARGB32(),
        'useDynamicColor': true,
      });
      expect(
        container.read(settingsProvider).customTheme.toJson(),
        custom.toJson(),
      );
      expect(
        container.read(settingsProvider).playlistArtworkColorsEnabled,
        isFalse,
      );
    },
  );

  test(
    'invalid synced theme is rejected before any appearance writes',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final container = _container(prefs);
      addTearDown(container.dispose);
      final notifier = container.read(settingsProvider.notifier);
      await notifier.setCustomTheme(custom);
      final before = notifier.exportAppearanceForSync();
      await expectLater(
        notifier.applyAppearanceFromSync({
          ...before,
          'themeMode': 'dark',
          'customTheme': {
            ...custom.toJson(),
            'light': {'background': -1},
          },
        }),
        throwsFormatException,
      );
      expect(notifier.exportAppearanceForSync(), before);
      expect(prefs.getString('theme_mode'), isNull);
    },
  );
}

ProviderContainer _container(SharedPreferences prefs) => ProviderContainer(
  overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
);
