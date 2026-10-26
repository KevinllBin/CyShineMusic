import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cy_shine_music/core/ui/artwork_colors.dart';

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
      expect(arguments.containsKey('requestGroup'), isFalse);
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
      final first = loadArtworkColors(provider, requestGroup: 'player');
      final next = loadArtworkColors(other, requestGroup: 'player');
      final returned = loadArtworkColors(provider, requestGroup: 'player');
      expect(returned, same(first));
      cancellation.complete({'cancelled': true});
      expect(await returned, isNotNull);
      expect(await next, isNotNull);
      expect(calls, 2);
    },
  );

  test('shares source work across display sizes and request groups', () async {
    final pending = Completer<Map<String, Object?>>();
    final source = MemoryImage(Uint8List.fromList([20, 21, 22]));
    final player = ResizeImage(source, width: 192, height: 192);
    final detail = ResizeImage(source, width: 1200, height: 1200);
    var calls = 0;
    messenger.setMockMethodCallHandler(_channel, (call) async {
      calls++;
      expect((call.arguments as Map)['requestGroup'], 'player');
      return pending.future;
    });

    final first = loadArtworkColors(player, requestGroup: 'player');
    final sameGroup = loadArtworkColors(source, requestGroup: 'player');
    final independent = loadArtworkColors(detail);
    expect(sameGroup, same(first));
    pending.complete(_reply);
    final colors = await first;
    expect(await independent, same(colors));
    expect(await loadArtworkColors(detail), same(colors));
    expect(calls, 1);
  });

  test('independent detail requests do not supersede each other', () async {
    final firstReply = Completer<Map<String, Object?>>();
    final firstCover = MemoryImage(Uint8List.fromList([30, 31, 32]));
    final secondCover = MemoryImage(Uint8List.fromList([40, 41, 42]));
    final playerCover = MemoryImage(Uint8List.fromList([50, 51, 52]));
    final groups = <Object?>[];
    messenger.setMockMethodCallHandler(_channel, (call) async {
      final arguments = call.arguments as Map;
      groups.add(arguments['requestGroup']);
      final bytes = arguments['bytes'] as Uint8List;
      return bytes.first == 30 ? firstReply.future : _reply;
    });

    final first = loadArtworkColors(firstCover);
    final second = loadArtworkColors(secondCover);
    final player = loadArtworkColors(playerCover, requestGroup: 'player');
    firstReply.complete(_reply);
    expect(await first, isNotNull);
    expect(await second, isNotNull);
    expect(await player, isNotNull);
    expect(groups, [null, null, 'player']);
  });

  test(
    'detail retries shared work cancelled by the next player cover',
    () async {
      final cancellation = Completer<Map<String, Object?>>();
      final source = MemoryImage(Uint8List.fromList([60, 61, 62]));
      final nextCover = MemoryImage(Uint8List.fromList([70, 71, 72]));
      final sourceGroups = <Object?>[];
      messenger.setMockMethodCallHandler(_channel, (call) async {
        final arguments = call.arguments as Map;
        final bytes = arguments['bytes'] as Uint8List;
        if (bytes.first != 60) return _reply;
        sourceGroups.add(arguments['requestGroup']);
        return sourceGroups.length == 1 ? cancellation.future : _reply;
      });

      final oldPlayer = loadArtworkColors(source, requestGroup: 'player');
      final detail = loadArtworkColors(source);
      final nextPlayer = loadArtworkColors(nextCover, requestGroup: 'player');
      cancellation.complete({'cancelled': true});
      expect(await oldPlayer, isNull);
      final colors = await detail;
      expect(colors, isNotNull);
      expect(await nextPlayer, isNotNull);
      expect(sourceGroups, ['player', null]);
      expect(await loadArtworkColors(source), same(colors));
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
