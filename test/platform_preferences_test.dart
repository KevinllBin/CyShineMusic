import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cy_shine_music/core/models/enums.dart';
import 'package:cy_shine_music/core/storage/settings_store.dart';
import 'package:cy_shine_music/features/discovery/discovery_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  ProviderContainer createContainer(SharedPreferences prefs) {
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('concrete platform survives a new provider container', () async {
    final prefs = await SharedPreferences.getInstance();
    final container = createContainer(prefs);
    container.read(selectedDiscoverySourceProvider.notifier).state =
        MusicSource.tx;
    container.read(selectedDiscoverySourceProvider.notifier).state =
        MusicSource.kg;
    await container.pump();

    final restored = createContainer(prefs);
    expect(restored.read(selectedDiscoverySourceProvider), MusicSource.kg);
    expect(prefs.getString('selected_discovery_source_v1'), 'kg');
  });

  test(
    'platform stays selected after reordering and changing settings',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final container = createContainer(prefs);
      container.read(selectedDiscoverySourceProvider.notifier).state =
          MusicSource.tx;
      final settings = container.read(settingsProvider.notifier);
      await settings.setDiscoverySourceOrder([MusicSource.kg, MusicSource.mg]);
      expect(container.read(discoverySourcesProvider).first, MusicSource.kg);
      expect(container.read(selectedDiscoverySourceProvider), MusicSource.tx);
      await settings.setSkipStartupScreen(true);
      expect(container.read(selectedDiscoverySourceProvider), MusicSource.tx);
      final restored = createContainer(prefs);
      expect(restored.read(selectedDiscoverySourceProvider), MusicSource.tx);
    },
  );

  for (final invalid in ['unknown', 'all']) {
    test(
      'invalid stored platform $invalid falls back to the configured first',
      () async {
        SharedPreferences.setMockInitialValues({
          'selected_discovery_source_v1': invalid,
          'discovery_source_order': ['mg', 'tx', 'wy', 'kg', 'kw'],
        });
        final prefs = await SharedPreferences.getInstance();
        final container = createContainer(prefs);
        expect(container.read(selectedDiscoverySourceProvider), MusicSource.mg);
        expect(prefs.getString('selected_discovery_source_v1'), 'mg');
      },
    );
  }
}
