import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cy_shine_music/core/services/app_logger.dart';
import 'package:cy_shine_music/core/services/log_category.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late SharedPreferences preferences;
  const paths = MethodChannel('plugins.flutter.io/path_provider');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUpAll(() async {
    temp = await Directory.systemTemp.createTemp('cyshine-log-test-');
    messenger.setMockMethodCallHandler(paths, (_) async => temp.path);
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
    AppLogger.configureRecording(preferences);
    await AppLogger.clear();
  });

  tearDownAll(() async {
    await AppLogger.setRecordingCategories({});
    await AppLogger.flush();
    messenger.setMockMethodCallHandler(paths, null);
    await temp.delete(recursive: true);
  });

  test(
    'only selected categories reach live output and exported files',
    () async {
      final live = <String>[];
      final subscription = AppLogger.liveLines.listen(live.add);
      addTearDown(subscription.cancel);
      expect(AppLogger.recordingCategories.value, isEmpty);
      await AppLogger.write('player', 'default-off-marker');

      await AppLogger.setRecordingCategories({AppLogCategory.smartTransition});
      await AppLogger.write('groove-shift-ui', 'transition-marker');
      await AppLogger.write('groove-shift-ui', 'transition-marker');
      await AppLogger.write('player-control', 'playback-off-marker');
      await AppLogger.write('music-source', 'source-off-marker');

      await AppLogger.setRecordingCategories({
        AppLogCategory.playback,
        AppLogCategory.download,
      });
      await AppLogger.write('groove-shift-trace', 'transition-off-marker');
      await AppLogger.write('player-control', 'playback-marker');
      await AppLogger.write('audio-session', 'focus-marker');
      await AppLogger.write('batch-download', 'download-marker');
      await AppLogger.write('tagger', 'tags-marker');
      await AppLogger.setRecordingCategories({});
      await AppLogger.write('download', 'disabled-marker');

      final text = await File(await AppLogger.exportFile()).readAsString();
      for (final output in [text, live.join('\n')]) {
        expect(output, contains('transition-marker'));
        expect(output, contains('repeated=1'));
        expect(output, contains('playback-marker'));
        expect(output, contains('focus-marker'));
        expect(output, contains('download-marker'));
        expect(output, contains('tags-marker'));
        expect(output, isNot(contains('off-marker')));
        expect(output, isNot(contains('disabled-marker')));
      }
    },
  );

  test(
    'recording choices persist and unknown categories are ignored',
    () async {
      await AppLogger.setRecordingCategories({
        AppLogCategory.musicSource,
        AppLogCategory.search,
      });
      final saved = preferences.getStringList(
        AppLogger.recordingPreferenceKey,
      )!;
      expect(saved, unorderedEquals(['musicSource', 'search']));

      SharedPreferences.setMockInitialValues({
        AppLogger.recordingPreferenceKey: [...saved, 'future-category'],
      });
      AppLogger.configureRecording(await SharedPreferences.getInstance());
      expect(AppLogger.recordingCategories.value, {
        AppLogCategory.musicSource,
        AppLogCategory.search,
      });
      await AppLogger.write('music-source-update', 'source-marker');
      await AppLogger.write('search', 'search-marker');
      await AppLogger.write('app-lifecycle', 'app-off-marker');
      await AppLogger.flush();
      final text = (await AppLogger.readRecentLines()).join('\n');
      expect(text, contains('source-marker'));
      expect(text, contains('search-marker'));
      expect(text, isNot(contains('app-off-marker')));
    },
  );

  test(
    'file export flushes, rotates in-session, and includes both log files',
    () async {
      await AppLogger.setRecordingCategories({
        AppLogCategory.smartTransition,
        AppLogCategory.application,
      });
      await AppLogger.clear();
      await AppLogger.write('export-test', 'old-marker');
      for (var i = 0; i < 400; i++) {
        await AppLogger.write('groove-shift-trace', 'frame=$i ${'x' * 3100}');
      }
      await AppLogger.write('export-test', 'new-marker');
      final exported = File(await AppLogger.exportFile());
      final text = await exported.readAsString();
      expect(text, contains('old-marker'));
      expect(text, contains('new-marker'));
      expect(text, contains('[log-export]'));
      final log = await AppLogger.currentLogFile();
      expect(await log!.length(), lessThan(1024 * 1024));
      expect(
        await File('${log.parent.path}/cyshine.prev.log').exists(),
        isTrue,
      );
      await AppLogger.clear();
      expect(await log.length(), 0);
      expect(
        await File('${log.parent.path}/cyshine.prev.log').exists(),
        isFalse,
      );
    },
  );
}
