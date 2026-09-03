import 'package:bass_player/bass_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cy_shine_music/core/storage/settings_store.dart';
import 'package:cy_shine_music/features/equalizer/equalizer_store.dart';
import 'package:cy_shine_music/features/equalizer/equalizer_page.dart';
import 'package:cy_shine_music/features/shell/shell_toolbar_visibility.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('ships Salt presets and an empty original default', () {
    expect(equalizerPresets, hasLength(30));
    final settings = EqualizerSettings.fallback;
    expect(settings.enabled, isFalse);
    expect(settings.bands, isEmpty);
  });

  test('preset and custom values persist as a speq document', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
    );
    final notifier = container.read(equalizerProvider.notifier);
    notifier.setEnabled(true);
    notifier.applyPreset(
      equalizerPresets.firstWhere((item) => item.id == 'builtin.rock'),
    );
    notifier.setInputGain(-2.5);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    container.dispose();

    final restored = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
    );
    addTearDown(restored.dispose);
    final settings = restored.read(equalizerProvider);
    expect(settings.enabled, isTrue);
    expect(settings.inputGainDb, -2.5);
    expect(settings.bands, hasLength(6));
    expect(settings.presetId, isNull);
  });

  test('maps the persisted model to the narrow native BASS FX contract', () {
    final settings = EqualizerSettings(
      enabled: true,
      inputGainDb: -1,
      outputGainDb: 2,
      bands: const [
        EqualizerBandSetting(
          id: 'voice',
          frequencyHz: 2400,
          gainDb: 3.5,
          q: 1.4,
          filter: EqualizerFilterType.peaking,
        ),
      ],
    );

    final native = settings.toBassConfiguration();
    expect(native.enabled, isTrue);
    expect(native.inputGainDb, -1);
    expect(native.outputGainDb, 2);
    expect(native.bands.single.id, 'voice');
    expect(native.bands.single.filter, BassBiquadFilter.peaking);
    expect(native.bands.single.frequencyHz, 2400);
    expect(native.bands.single.enabled, isTrue);
  });

  test('reads and writes Salt-compatible speq bundles', () {
    const settings = EqualizerSettings(
      enabled: true,
      inputGainDb: -3,
      outputGainDb: 1,
      bands: [
        EqualizerBandSetting(id: 'voice', frequencyHz: 2800, gainDb: 4, q: 1.2),
      ],
    );

    final encoded = settings.toSpeq();
    final decoded = EqualizerSettings.fromSpeq(encoded);
    expect(encoded, contains('speq.equalizer-presets'));
    expect(decoded.inputGainDb, -3);
    expect(decoded.outputGainDb, 1);
    expect(decoded.bands.single.frequencyHz, 2800);
  });

  test('legacy unsupported filters migrate to peaking and clamp ranges', () {
    final migrated = EqualizerSettings.fromSpeq('''
      {
        "enabled": true,
        "inputGainDb": 40,
        "outputGainDb": -40,
        "bands": [
          {
            "id": "legacy",
            "filter": "notch",
            "frequencyHz": 96000,
            "gainDb": 50,
            "q": 24,
            "bandwidth": 3,
            "slope": 2
          }
        ]
      }
    ''');

    expect(migrated.inputGainDb, equalizerMaxGainDb);
    expect(migrated.outputGainDb, equalizerMinGainDb);
    expect(migrated.bands.single.filter, EqualizerFilterType.peaking);
    expect(migrated.bands.single.frequencyHz, equalizerMaxFrequencyHz);
    expect(migrated.bands.single.q, equalizerMaxQ);
  });

  testWidgets('equalizer page fits a phone and enables without restarting', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
        child: const MaterialApp(home: Scaffold(body: EqualizerPage())),
      ),
    );

    expect(find.text('均衡器已关闭'), findsOneWidget);
    expect(find.byType(Switch), findsOneWidget);
    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(find.text('均衡器已开启'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'band editor sheet hides toolbar, has no checkbox in slider, and manages band state',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();

      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
      );
      addTearDown(container.dispose);

      container.read(equalizerProvider.notifier).setEnabled(true);
      container.read(equalizerProvider.notifier).applyPreset(
        equalizerPresets.firstWhere((p) => p.id == 'builtin.studio_reference'),
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: EqualizerPage())),
        ),
      );
      await tester.pumpAndSettle();

      // Verify no Checkbox is rendered on the page (relocated to modal)
      expect(find.byType(Checkbox), findsNothing);

      // Toolbar is initially visible
      expect(container.read(shellToolbarVisibleProvider), isTrue);

      // Scroll down to the bands section
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
      await tester.pumpAndSettle();

      final editButton = find.byTooltip('编辑频段').first;
      expect(editButton, findsOneWidget);
      await tester.tap(editButton);
      await tester.pumpAndSettle();

      // Bottom sheet is open: toolbar must be hidden
      expect(container.read(shellToolbarVisibleProvider), isFalse);

      // Verify modal has '启用此频段' switch, '编辑频段', '保存设置', and '删除此频段'
      expect(find.text('启用此频段'), findsOneWidget);
      expect(find.text('编辑频段'), findsOneWidget);
      expect(find.text('保存设置'), findsOneWidget);
      expect(find.text('删除此频段'), findsOneWidget);

      // Close the sheet
      await tester.tap(find.byTooltip('关闭'));
      await tester.pumpAndSettle();

      // Toolbar should be restored!
      expect(container.read(shellToolbarVisibleProvider), isTrue);
    },
  );
}
