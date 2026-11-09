import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cy_shine_music/core/storage/settings_store.dart';
import 'package:cy_shine_music/theme/app_theme.dart';
import 'package:cy_shine_music/theme/liquid_glass_mode.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('theme mode updates immediately and persists for restart', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);
    final pending = container
        .read(settingsProvider.notifier)
        .setThemeMode(ThemeMode.dark);
    expect(container.read(settingsProvider).themeMode, ThemeMode.dark);
    await pending;
    final restored = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(restored.dispose);
    expect(restored.read(settingsProvider).themeMode, ThemeMode.dark);
  });

  test('dark settings cards remain distinct from their page background', () {
    final scheme = AppTheme.dark().colorScheme;
    expect(scheme.appSettingsSurface, isNot(scheme.surfaceContainer));
    expect(
      scheme.surfaceContainer.computeLuminance() -
          scheme.appSettingsSurface.computeLuminance(),
      greaterThan(0.008),
    );
  });

  test(
    'lyrics default to 200 and 28 with immediate edits and persistent values',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);
      expect(container.read(settingsProvider).lyricFontWeight, 200);
      expect(container.read(settingsProvider).lyricFontSize, 28);
      final notifier = container.read(settingsProvider.notifier);
      final pending = notifier.setLyricFontStyle(weight: 300, size: 30);
      expect(container.read(settingsProvider).lyricFontWeight, 300);
      expect(container.read(settingsProvider).lyricFontSize, 30);
      await pending;
      final restored = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(restored.dispose);
      expect(restored.read(settingsProvider).lyricFontWeight, 300);
      expect(restored.read(settingsProvider).lyricFontSize, 30);
      await notifier.setLyricFontStyle(
        weight: kLyricFontWeightDefault,
        size: kLyricFontSizeDefault,
      );
      expect(container.read(settingsProvider).lyricFontWeight, 200);
      expect(container.read(settingsProvider).lyricFontSize, 28);
    },
  );

  test('glass mode persists and old theme data does not override it', () async {
    SharedPreferences.setMockInitialValues({
      'custom_theme': '{"enabled":true}',
    });
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);
    expect(
      container.read(settingsProvider).liquidGlassMode,
      LiquidGlassMode.standard,
    );
    await container
        .read(settingsProvider.notifier)
        .setLiquidGlassMode(LiquidGlassMode.ultra);
    final restored = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(restored.dispose);
    expect(
      restored.read(settingsProvider).liquidGlassMode,
      LiquidGlassMode.ultra,
    );
    expect(
      restored.read(settingsProvider.notifier).exportAppearanceForSync(),
      isNot(contains('customTheme')),
    );
  });

  test(
    'appearance sync preserves glass for old backups and rejects invalid modes atomically',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);
      final notifier = container.read(settingsProvider.notifier);
      await notifier.setLiquidGlassMode(LiquidGlassMode.ultra);
      final legacy = {
        'themeMode': 'light',
        'themeSeedArgb': Colors.blue.toARGB32(),
        'useDynamicColor': false,
        'customTheme': {'enabled': true},
      };
      await notifier.applyAppearanceFromSync(legacy);
      expect(
        container.read(settingsProvider).liquidGlassMode,
        LiquidGlassMode.ultra,
      );
      await expectLater(
        notifier.applyAppearanceFromSync({
          ...legacy,
          'liquidGlassMode': 'broken',
        }),
        throwsFormatException,
      );
      expect(
        container.read(settingsProvider).liquidGlassMode,
        LiquidGlassMode.ultra,
      );
      await notifier.applyAppearanceFromSync({
        ...legacy,
        'liquidGlassMode': 'none',
      });
      expect(
        container.read(settingsProvider).liquidGlassMode,
        LiquidGlassMode.none,
      );
    },
  );

  test('seed changes affect accents while backgrounds remain neutral', () {
    final blue = AppTheme.light(Colors.blue).colorScheme;
    final orange = AppTheme.light(Colors.orange).colorScheme;
    expect(blue.surface, Colors.white);
    expect(blue.surfaceBright, Colors.white);
    expect(blue.surfaceContainerLow, Colors.white);
    expect(blue.surface, orange.surface);
    expect(blue.surfaceContainerLow, orange.surfaceContainerLow);
    expect(blue.primary, isNot(orange.primary));
    final darkBlue = AppTheme.dark(Colors.blue).colorScheme;
    final darkOrange = AppTheme.dark(Colors.orange).colorScheme;
    expect(darkBlue.surface, darkOrange.surface);
    expect(darkBlue.surfaceContainerLow, darkOrange.surfaceContainerLow);
  });

  test(
    'color palette add edit delete persists without reviving a deleted selection',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);
      final notifier = container.read(settingsProvider.notifier);
      const first = Color(0xFF6750A4);
      const second = Color(0xFF127856);
      await notifier.selectThemeColor(null);
      expect(container.read(settingsProvider).useDynamicColor, isTrue);
      await notifier.saveThemeColor(first);
      expect(
        container.read(settingsProvider).themePalette,
        contains(first.toARGB32()),
      );
      expect(container.read(settingsProvider).useDynamicColor, isFalse);
      expect(container.read(settingsProvider).themeSeed, first);
      await notifier.saveThemeColor(second, replacing: first.toARGB32());
      expect(
        container.read(settingsProvider).themePalette,
        isNot(contains(first.toARGB32())),
      );
      expect(container.read(settingsProvider).themeSeed, second);
      await notifier.deleteThemeColor(second.toARGB32());
      final restored = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(restored.dispose);
      expect(
        restored.read(settingsProvider).themePalette,
        isNot(contains(second.toARGB32())),
      );
      expect(restored.read(settingsProvider).useDynamicColor, isTrue);
    },
  );

  test(
    'color palette sync rejects invalid lists before changing preferences',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);
      final notifier = container.read(settingsProvider.notifier);
      final backup = notifier.exportAppearanceForSync();
      await expectLater(
        notifier.applyAppearanceFromSync({
          ...backup,
          'themePalette': [-1],
        }),
        throwsFormatException,
      );
      expect(notifier.exportAppearanceForSync(), backup);
      final custom = Color(0xFF891234).toARGB32();
      await notifier.applyAppearanceFromSync({
        ...backup,
        'themeSeedArgb': custom,
        'themePalette': [custom, custom],
      });
      expect(container.read(settingsProvider).themePalette, [custom]);
    },
  );
}
