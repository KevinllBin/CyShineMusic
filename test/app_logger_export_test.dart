import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
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
    'uncaught errors persist before returning with categories off',
    () async {
      final ordinaryLog = (await AppLogger.currentLogFile())!;
      final crashLog = File('${ordinaryLog.parent.path}/cyshine-crash.log');
      final stack = StackTrace.fromString(
        '#0 crashFrame ${'x' * 1600}\n#1 finalUsefulFrame',
      );

      final recording = AppLogger.recordUnhandledError(
        'platform',
        StateError(
          'crash-marker https://audio.test/a?token=secret password=hidden',
        ),
        stack,
      );
      // The engine can terminate immediately after the error callback returns.
      // Waiting for a queued normal log write would lose this record.
      final immediate = crashLog.readAsStringSync();
      expect(immediate, contains('crash-marker'));
      expect(immediate, contains('finalUsefulFrame'));
      expect(immediate, isNot(contains('secret')));
      expect(immediate, isNot(contains('hidden')));
      await recording;

      expect(AppLogger.recordingCategories.value, isEmpty);
      expect(await ordinaryLog.length(), 0);
      expect(
        (await AppLogger.readRecentLines()).join('\n'),
        contains('crash-marker'),
      );
      final exported = await File(await AppLogger.exportFile()).readAsString();
      expect(exported, contains('crash-marker'));
      await AppLogger.clear();
      expect(await crashLog.length(), 0);
      expect(await AppLogger.readRecentLines(), isEmpty);
    },
  );

  test(
    'Android crash and exit records are retained once and redacted',
    () async {
      final data = <String, dynamic>{
        'sdk': 30,
        'javaCrash':
            'timestampMs=1000\njava.lang.OutOfMemoryError: java-marker '
            'https://audio.test/a?token=secret',
        // A later user stop must not hide the preceding fatal crash.
        'recentProcessExits': [
          {'timestamp': 2000, 'reasonName': 'USER_REQUESTED'},
          {
            'timestamp': 1000,
            'reasonName': 'CRASH_NATIVE',
            'nativeTrace':
                'signal: SIGSEGV SEGV_MAPERR fault=0x0 tid=7\n'
                '${'#00 pc 0x1f2c libflutter.so (frame-filler)\n' * 120}'
                '#120 pc 0x2a libapp.so (trace-tail-marker)',
          },
        ],
      };
      await Future.wait([
        AppLogger.recordAndroidDiagnostics(data),
        AppLogger.recordAndroidDiagnostics(data),
      ]);
      AppLogger.configureRecording(preferences);
      await AppLogger.recordAndroidDiagnostics(data);
      final lines = AppLogger.recentMemoryLines;
      expect(
        lines.where((line) => line.contains('previous_java_crash')),
        hasLength(1),
      );
      expect(
        lines.where((line) => line.contains('previous_process_exit')),
        hasLength(2),
      );
      final exported = await File(await AppLogger.exportFile()).readAsString();
      expect(exported, contains('java-marker'));
      expect(exported, contains('CRASH_NATIVE'));
      expect(exported, contains('trace-tail-marker'));
      expect(exported, contains('USER_REQUESTED'));
      expect(exported, isNot(contains('secret')));
      expect(exported, isNot(contains('"javaCrash":')));
    },
  );

  test(
    'crash records stay bounded separately from normal log rotation',
    () async {
      await AppLogger.setRecordingCategories({AppLogCategory.application});
      for (var i = 0; i < 100; i++) {
        await AppLogger.recordUnhandledError(
          'flutter',
          StateError('bounded-marker-$i ${'x' * 3500}'),
          StackTrace.fromString('#0 crashFrame'),
        );
      }
      final normalLog = (await AppLogger.currentLogFile())!;
      final crashLog = File('${normalLog.parent.path}/cyshine-crash.log');
      expect(await crashLog.length(), lessThanOrEqualTo(256 * 1024));
      final exported = await File(await AppLogger.exportFile()).readAsString();
      expect(exported, contains('bounded-marker-99'));
      expect(await normalLog.length(), 0);
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

  test(
    'global error hooks persist before delegating to existing handlers',
    () async {
      final previousFlutter = FlutterError.onError;
      final previousPlatform = ui.PlatformDispatcher.instance.onError;
      addTearDown(() {
        FlutterError.onError = previousFlutter;
        ui.PlatformDispatcher.instance.onError = previousPlatform;
      });
      final ordinaryLog = (await AppLogger.currentLogFile())!;
      final crashLog = File('${ordinaryLog.parent.path}/cyshine-crash.log');
      var flutterDelegated = false;
      var platformDelegated = false;
      FlutterError.onError = (_) {
        expect(crashLog.readAsStringSync(), contains('framework-hook-marker'));
        flutterDelegated = true;
      };
      ui.PlatformDispatcher.instance.onError = (_, _) {
        expect(crashLog.readAsStringSync(), contains('platform-hook-marker'));
        platformDelegated = true;
        return true;
      };
      AppLogger.installErrorHandlers();
      FlutterError.onError!(
        FlutterErrorDetails(
          exception: StateError('framework-hook-marker'),
          stack: StackTrace.current,
        ),
      );
      final handled = ui.PlatformDispatcher.instance.onError!(
        StateError('platform-hook-marker'),
        StackTrace.current,
      );
      expect(flutterDelegated, isTrue);
      expect(platformDelegated, isTrue);
      expect(handled, isTrue);
    },
  );
}
