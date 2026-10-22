import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cy_shine_music/core/models/enums.dart';
import 'package:cy_shine_music/core/models/music_info.dart';
import 'package:cy_shine_music/core/music_sources/music_source_models.dart';
import 'package:cy_shine_music/core/music_sources/music_source_runtime.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'a two-second resolve timeout releases the next source request',
    () async {
      const channel = MethodChannel('test/music-source-timeout');
      final calls = <String>[];
      final stalledResolve = Completer<Map<String, Object>>();
      final runtime = MusicSourceRuntime(Dio(), channel: channel);
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        switch (call.method) {
          case 'load':
            return {
              'sources': {
                'kw': {
                  'actions': ['musicUrl'],
                  'qualitys': ['128k'],
                },
              },
            };
          case 'resolve':
            if (calls.where((method) => method == 'resolve').length == 1) {
              return stalledResolve.future;
            }
            return {'url': 'https://audio.test/recovered.mp3'};
          case 'dispose':
            if (!stalledResolve.isCompleted) {
              stalledResolve.completeError(
                PlatformException(code: 'RUNTIME_DISPOSED'),
              );
            }
            return null;
        }
        throw StateError('Unexpected method: ${call.method}');
      });
      addTearDown(() async {
        await runtime.disposeRuntime();
        messenger.setMockMethodCallHandler(channel, null);
      });

      final record = MusicSourceRecord(
        id: 'timeout-test',
        name: 'Timeout Test',
        description: '',
        author: 'test',
        homepage: '',
        version: '1',
        origin: 'test',
        importedAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        capabilities: const {},
      );
      final music = MusicInfo(
        id: 'song-1',
        name: 'Test Song',
        singer: 'Test Singer',
        source: MusicSource.kw,
        interval: '03:00',
        meta: const MusicMeta(
          songId: 'song-1',
          albumName: 'Test Album',
          qualitys: [],
          raw: {},
        ),
        raw: const {},
      );
      resolve() => runtime.resolveWithSource(
        record: record,
        script: 'test script',
        music: music,
        quality: Quality.k128,
      );

      await expectLater(
        resolve().timeout(const Duration(seconds: 5)),
        throwsA(
          isA<MusicSourceRuntimeException>().having(
            (error) => error.message,
            'message',
            '音源解析超时',
          ),
        ),
      );
      final recovered = await resolve();
      expect(recovered.url, 'https://audio.test/recovered.mp3');
      expect(calls, ['load', 'resolve', 'dispose', 'load', 'resolve']);
    },
  );
}
