import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cy_shine_music/core/storage/settings_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'legacy scan folder migrates into a normalized persistent folder list',
    () async {
      SharedPreferences.setMockInitialValues({
        'download_dir': '/downloads',
        'local_music_dir': '/music/legacy',
      });
      final prefs = await SharedPreferences.getInstance();
      ProviderContainer createContainer() => ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      final container = createContainer();
      addTearDown(container.dispose);
      expect(container.read(settingsProvider).localMusicDirs, [
        '/music/legacy',
      ]);

      final notifier = container.read(settingsProvider.notifier);
      await notifier.setLocalMusicDirs([
        '/music/a/',
        ' ',
        '/music/a',
        ' /music/./b ',
      ]);
      expect(container.read(settingsProvider).localMusicDirs, [
        '/music/a',
        '/music/b',
      ]);
      expect(prefs.getStringList('local_music_dirs'), ['/music/a', '/music/b']);
      expect(prefs.getString('local_music_dir'), '/music/a');
      await notifier.setDownloadDir('/new-downloads');
      expect(container.read(settingsProvider).localMusicDirs, [
        '/music/a',
        '/music/b',
      ]);

      final restored = createContainer();
      addTearDown(restored.dispose);
      expect(restored.read(settingsProvider).localMusicDirs, [
        '/music/a',
        '/music/b',
      ]);
      await notifier.setLocalMusicDirs([]);
      expect(container.read(settingsProvider).localMusicDirs, [
        '/new-downloads',
      ]);
      await notifier.setLocalMusicDir('/single');
      expect(container.read(settingsProvider).localMusicDirs, ['/single']);
    },
  );

  test(
    'default scan folder follows the download folder until multiple roots are configured',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);
      final notifier = container.read(settingsProvider.notifier);
      expect(container.read(settingsProvider).localMusicDirs, [
        container.read(settingsProvider).downloadDir,
      ]);
      await notifier.setDownloadDir('/downloads');
      expect(container.read(settingsProvider).localMusicDirs, ['/downloads']);
      await notifier.setLocalMusicDirs(['/downloads', '/other']);
      await notifier.setDownloadDir('/new-downloads');
      expect(container.read(settingsProvider).localMusicDirs, [
        '/downloads',
        '/other',
      ]);
    },
  );
}
