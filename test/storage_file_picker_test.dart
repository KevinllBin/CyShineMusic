import 'dart:async';

import 'package:cy_shine_music/core/services/storage_browser_service.dart';
import 'package:cy_shine_music/features/settings/widgets/storage_folder_picker_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _channel = MethodChannel('test/storage_browser');

class _TestBrowser extends StorageBrowserService {
  const _TestBrowser() : super(channel: _channel);

  @override
  bool get isSupported => true;
}

Map<String, Object> _entry(
  String name, {
  bool folder = false,
  bool root = false,
}) => {
  'path': '/storage/usb/$name',
  'name': name,
  'isDirectory': folder,
  'isRoot': root,
  'canRead': true,
  'canWrite': false,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const browser = _TestBrowser();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    messenger.setMockMethodCallHandler(_channel, (call) async {
      calls.add(call);
      if (call.method == 'listRoots') {
        return [_entry('U盘', folder: true, root: true)];
      }
      return [
        _entry('脚本目录', folder: true),
        _entry('音源.JS'),
        _entry('song.mp3'),
        _entry('script.js.bak'),
      ];
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(_channel, null));

  test('file mode accepts uppercase JS but rejects unrelated files', () async {
    final entries = await browser.listChildren(
      '/storage/usb',
      fileExtensions: {'js'},
    );
    expect(entries.map((entry) => entry.name), ['脚本目录', '音源.JS']);
    expect(calls.single.arguments, {
      'path': '/storage/usb',
      'includeFiles': true,
    });
  });

  test(
    'existing folder mode still requests and returns only directories',
    () async {
      final entries = await browser.listChildren('/storage/usb');
      expect(entries.map((entry) => entry.name), ['脚本目录']);
      expect(calls.single.arguments['includeFiles'], isFalse);
    },
  );

  testWidgets(
    'browse USB and select a read-only JS file on a short car screen',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 360));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      String? selected;
      await _openPicker(tester, onSelected: (path) => selected = path);
      await tester.tap(find.text('U盘'));
      await tester.pumpAndSettle();
      expect(find.text('音源.JS'), findsOneWidget);
      expect(find.text('song.mp3'), findsNothing);
      expect(find.text('选择此文件夹'), findsNothing);
      await tester.tap(find.text('音源.JS'));
      await tester.pumpAndSettle();
      expect(selected, '/storage/usb/音源.JS');
      expect(find.byType(StorageFolderPickerSheet), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'system back navigates to roots then cancels without a selection',
    (tester) async {
      String? selected = 'not closed';
      await _openPicker(tester, onSelected: (path) => selected = path);
      await tester.tap(find.text('U盘'));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('U盘'), findsOneWidget);
      expect(selected, 'not closed');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(selected, isNull);
    },
  );

  testWidgets('an unplugged drive can be retried or left without overflowing', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 360));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var fail = true;
    messenger.setMockMethodCallHandler(_channel, (call) async {
      if (call.method == 'listRoots') {
        return [_entry('U盘', folder: true, root: true)];
      }
      if (fail) {
        throw PlatformException(code: 'LIST_CHILDREN_FAILED', message: 'U盘已移除');
      }
      return <Object>[];
    });
    await _openPicker(tester);
    await tester.tap(find.text('U盘'));
    await tester.pumpAndSettle();
    expect(find.text('无法读取文件夹'), findsOneWidget);
    fail = false;
    await tester.ensureVisible(find.text('重试'));
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('没有可导入的脚本或子文件夹'), findsOneWidget);
    await tester.tap(find.byTooltip('返回上一级'));
    await tester.pumpAndSettle();
    expect(find.text('U盘'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('returning while a directory loads ignores its late result', (
    tester,
  ) async {
    final pending = Completer<List<Object>>();
    messenger.setMockMethodCallHandler(_channel, (call) async {
      if (call.method == 'listRoots') {
        return [_entry('U盘', folder: true, root: true)];
      }
      return pending.future;
    });
    await _openPicker(tester);
    await tester.tap(find.text('U盘'));
    await tester.pump();
    await tester.tap(find.byTooltip('返回上一级'));
    await tester.pumpAndSettle();
    pending.complete([_entry('音源.JS')]);
    await tester.pumpAndSettle();
    expect(find.text('U盘'), findsOneWidget);
    expect(find.text('音源.JS'), findsNothing);
  });

  testWidgets('folder mode can still select the current directory', (
    tester,
  ) async {
    String? selected;
    await _openPicker(
      tester,
      files: false,
      onSelected: (path) => selected = path,
    );
    await tester.tap(find.text('U盘'));
    await tester.pumpAndSettle();
    expect(find.text('音源.JS'), findsNothing);
    await tester.tap(find.text('选择此文件夹'));
    await tester.pumpAndSettle();
    expect(selected, '/storage/usb/U盘');
  });
}

Future<void> _openPicker(
  WidgetTester tester, {
  bool files = true,
  ValueChanged<String?>? onSelected,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              final selected = await showStorageFolderPickerSheet(
                context,
                title: files ? '选择音源脚本（.js）' : '选择文件夹',
                fileExtensions: files ? {'js'} : null,
                service: const _TestBrowser(),
              );
              onSelected?.call(selected);
            },
            child: const Text('打开'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开'));
  await tester.pumpAndSettle();
}
