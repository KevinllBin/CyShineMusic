import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cy_shine_music/features/player/artwork_colors.dart';

const _channel = MethodChannel('cy_shine_music/artwork_colors');
const _reply = <String, Object?>{
  'baseArgb': -16711936,
  'paletteBaseArgb': -16711936,
  'accentsArgb': [-65536, -16711936, -16776961, -256],
  'lyricInkArgb': -16777216,
  'hasPalette': true,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(_channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test('shares native work and reuses the completed cover colors', () async {
    final pending = Completer<Map<String, Object?>>();
    final bytes = Uint8List.fromList([1, 2, 3]);
    final provider = ResizeImage(MemoryImage(bytes), width: 192, height: 192);
    var calls = 0;
    messenger.setMockMethodCallHandler(_channel, (call) async {
      calls++;
      expect(call.method, 'extract');
      final arguments = call.arguments as Map;
      expect(arguments['bytes'], bytes);
      expect(arguments.containsKey('rgba'), isFalse);
      return pending.future;
    });

    final first = loadArtworkColors(provider);
    final second = loadArtworkColors(provider);
    expect(identical(first, second), isTrue);
    pending.complete(_reply);
    final colors = await first;
    expect(colors?.baseColor.toARGB32(), 0xff00ff00);
    expect(colors?.accent?.toARGB32(), 0xffff0000);
    expect(colors?.lyricInk?.toARGB32(), 0xff000000);
    expect(await second, same(colors));
    expect(await loadArtworkColors(provider), same(colors));
    expect(calls, 1);
  });

  test(
    'restarts cancelled work when its cover becomes current again',
    () async {
      final provider = MemoryImage(Uint8List.fromList([4, 5, 6]));
      final other = MemoryImage(Uint8List.fromList([10, 11, 12]));
      final cancellation = Completer<Map<String, Object?>>();
      var calls = 0;
      messenger.setMockMethodCallHandler(_channel, (call) async {
        final bytes = (call.arguments as Map)['bytes'] as Uint8List;
        if (bytes.first != 4) return _reply;
        calls++;
        return calls == 1 ? cancellation.future : _reply;
      });
      final first = loadArtworkColors(provider);
      final next = loadArtworkColors(other);
      final returned = loadArtworkColors(provider);
      expect(returned, same(first));
      cancellation.complete({'cancelled': true});
      expect(await returned, isNotNull);
      expect(await next, isNotNull);
      expect(calls, 2);
    },
  );

  test(
    'passes a file path and invalidates colors when the file changes',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'artwork-colors-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/cover.png');
      await file.writeAsBytes([7, 8, 9]);
      final provider = FileImage(file);
      var calls = 0;
      messenger.setMockMethodCallHandler(_channel, (call) async {
        calls++;
        final arguments = call.arguments as Map;
        expect(arguments, {'path': file.path});
        return _reply;
      });
      await loadArtworkColors(provider);
      await loadArtworkColors(provider);
      expect(calls, 1);
      await file.writeAsBytes([7, 8, 9, 10]);
      await loadArtworkColors(provider);
      expect(calls, 2);
    },
  );
}
