import 'dart:io';

import 'package:cy_shine_music/core/music_sources/music_source_controller.dart';
import 'package:cy_shine_music/core/music_sources/music_source_store.dart';
import 'package:cy_shine_music/core/services/storage_browser_service.dart';
import 'package:cy_shine_music/core/storage/settings_store.dart';
import 'package:cy_shine_music/features/music_sources/music_source_page.dart';
import 'package:cy_shine_music/features/settings/widgets/storage_folder_picker_sheet.dart';
import 'package:cy_shine_music/features/shell/shell_toolbar_visibility.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _browserChannel = MethodChannel('test/source_file_browser');
const _runtimeChannel = MethodChannel('cy_shine_music/music_source_runtime');
final _systemPickerChannel = MethodChannel(
  'miguelruivo.flutter.plugins.filepicker',
  Platform.isAndroid || Platform.isIOS
      ? const StandardMethodCodec()
      : const JSONMethodCodec(),
);
const _script = '// @name 车机导入测试\n// @author Test\n// @version 1\n';

class _TestBrowser extends StorageBrowserService {
  const _TestBrowser() : super(channel: _browserChannel);
  @override
  bool get isSupported => true;
}

class _TestStore extends MusicSourceStore {
  _TestStore(super.preferences, this.directory);
  final Directory directory;

  @override
  Future<File> scriptFile(String id) async =>
      File('${directory.path}/saved/$id.js');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory directory;
  late File source;
  late ProviderContainer container;
  late _TestStore store;
  var systemPickerCalls = 0;
  final loadedScripts = <String>[];

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'use_built_in_source_file_picker': true,
    });
    final prefs = await SharedPreferences.getInstance();
    directory = Directory.systemTemp.createTempSync('source-import-test-');
    source = File('${directory.path}/音源.JS')..writeAsStringSync(_script);
    store = _TestStore(prefs, directory);
    loadedScripts.clear();
    systemPickerCalls = 0;
    FilePicker.platform = FilePickerIO();
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        storageBrowserServiceProvider.overrideWithValue(const _TestBrowser()),
        musicSourceStoreProvider.overrideWithValue(store),
      ],
    );
    messenger.setMockMethodCallHandler(_browserChannel, (call) async {
      final root = call.method == 'listRoots';
      return [
        {
          'path': root ? directory.path : source.path,
          'name': root ? 'U盘' : '音源.JS',
          'isDirectory': root,
          'isRoot': root,
          'canRead': true,
          'canWrite': false,
        },
      ];
    });
    messenger.setMockMethodCallHandler(_runtimeChannel, (call) async {
      if (call.method == 'load') {
        loadedScripts.add(call.arguments['script'] as String);
        return {
          'sources': {
            'kw': {
              'actions': ['musicUrl'],
              'qualitys': ['128k'],
            },
          },
        };
      }
      return null;
    });
    messenger.setMockMethodCallHandler(_systemPickerChannel, (call) async {
      systemPickerCalls++;
      throw PlatformException(code: 'unavailable', message: '系统文件选择器不可用');
    });
    await container.read(musicSourceControllerProvider.future);
  });

  tearDown(() {
    container.dispose();
    for (final channel in [
      _browserChannel,
      _runtimeChannel,
      _systemPickerChannel,
    ]) {
      messenger.setMockMethodCallHandler(channel, null);
    }
    directory.deleteSync(recursive: true);
  });

  Future<void> openLocalImport(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: MusicSourcePage())),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('本地导入'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('继续导入'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'built-in selection reads, saves and enables the selected script',
    (tester) async {
      await openLocalImport(tester);
      expect(find.byType(StorageFolderPickerSheet), findsOneWidget);
      expect(container.read(shellToolbarVisibleProvider), isFalse);
      await tester.tap(find.text('U盘'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('音源.JS'));
      // Let real filesystem I/O and the widget test's fake event loop both run.
      for (var attempt = 0; attempt < 100; attempt++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
        if (container
            .read(musicSourceControllerProvider)
            .requireValue
            .enabledIds
            .isNotEmpty) {
          break;
        }
      }
      await tester.pumpAndSettle();
      final state = container.read(musicSourceControllerProvider).requireValue;
      expect(state.records.single.name, '车机导入测试');
      expect(state.records.single.origin, source.path);
      expect(state.enabledIds, [state.records.single.id]);
      expect(loadedScripts, [_script]);
      expect(systemPickerCalls, 0);
      expect(container.read(shellToolbarVisibleProvider), isTrue);
      await tester.runAsync(() async {
        expect(await store.readScript(state.records.single.id), _script);
        expect((await store.load()).enabledIds, state.enabledIds);
      });
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'cancelling built-in selection leaves sources and toolbar intact',
    (tester) async {
      await openLocalImport(tester);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(
        container.read(musicSourceControllerProvider).requireValue.records,
        isEmpty,
      );
      expect(loadedScripts, isEmpty);
      expect(systemPickerCalls, 0);
      expect(container.read(shellToolbarVisibleProvider), isTrue);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '本地导入'))
            .onPressed,
        isNotNull,
      );
    },
  );

  testWidgets(
    'system picker failure is caught and switching to built-in allows retry',
    (tester) async {
      await container
          .read(settingsProvider.notifier)
          .setUseBuiltInSourceFilePicker(false);
      await openLocalImport(tester);
      expect(systemPickerCalls, 1);
      expect(find.byType(StorageFolderPickerSheet), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      await container
          .read(settingsProvider.notifier)
          .setUseBuiltInSourceFilePicker(true);
      await tester.tap(find.text('本地导入'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('继续导入'));
      await tester.pumpAndSettle();
      expect(find.byType(StorageFolderPickerSheet), findsOneWidget);
      expect(systemPickerCalls, 1);
      await tester.tap(find.text('取消'));
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(find.byType(StorageFolderPickerSheet), findsNothing);
    },
  );
}
