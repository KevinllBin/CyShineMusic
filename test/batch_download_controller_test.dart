import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cy_shine_music/core/models/enums.dart';
import 'package:cy_shine_music/core/models/music_info.dart';
import 'package:cy_shine_music/core/services/batch_download_controller.dart';
import 'package:cy_shine_music/core/services/download_service.dart';
import 'package:cy_shine_music/core/storage/settings_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'pause and immediate resume keep the concurrency cap and successful files',
    () async {
      final fixture = await _fixture();
      final task = fixture.controller.create(musics: _songs(6));
      expect(fixture.service.active, 3);
      fixture.service.calls.first.complete();
      await _flush();
      expect(
        fixture.container.read(batchDownloadProvider).single.successCount,
        1,
      );

      fixture.controller.pause(task.id);
      expect(
        fixture.service.calls
            .where((call) => !call.ended)
            .every((call) => call.token.isCancelled),
        isTrue,
      );
      fixture.controller.resume(task.id);
      await _flush();
      expect(fixture.service.active, 3);
      expect(
        fixture.service.calls.where((call) => call.music.id == 'song-0'),
        hasLength(1),
      );
      await fixture.service.completeAll();

      final finished = fixture.container.read(batchDownloadProvider).single;
      expect(finished.status, BatchDownloadStatus.completed);
      expect(finished.successCount, 6);
      expect(finished.failedCount, 0);
      expect(fixture.service.maxActive, 3);
    },
  );

  test(
    'all batches share three slots and deleting a running task never resurrects it',
    () async {
      final fixture = await _fixture();
      final first = fixture.controller.create(musics: _songs(5));
      final second = fixture.controller.create(
        musics: _songs(4, prefix: 'other'),
      );
      expect(first.id, isNot(second.id));
      expect(fixture.service.calls, hasLength(3));

      fixture.controller.pause(first.id);
      await _flush();
      expect(
        fixture.service.calls
            .where((call) => !call.ended)
            .map((call) => call.batchId),
        everyElement(second.id),
      );
      fixture.controller.remove(second.id);
      await _flush();
      expect(fixture.service.active, 0);
      expect(fixture.container.read(batchDownloadProvider).map((t) => t.id), [
        first.id,
      ]);
      fixture.controller.resume(first.id);
      await fixture.service.completeAll();
      expect(
        fixture.container.read(batchDownloadProvider).single.successCount,
        5,
      );
      expect(fixture.service.maxActive, 3);
    },
  );

  test(
    'saved tasks restore paused with the same ID and only unfinished songs resume',
    () async {
      final fixture = await _fixture();
      final task = fixture.controller.create(
        musics: _songs(4),
        quality: OnlinePlaybackQuality.high,
      );
      fixture.service.calls.first.complete();
      await _flush();
      fixture.controller.pause(task.id);
      await _flush();
      fixture.container.dispose();
      await _flush();

      final restored = await _fixture();
      final saved = restored.container.read(batchDownloadProvider).single;
      expect(saved.id, task.id);
      expect(saved.status, BatchDownloadStatus.paused);
      expect(saved.successCount, 1);
      expect(saved.pendingCount, 3);
      expect(restored.service.calls, isEmpty);

      restored.controller.resume(task.id);
      await restored.service.completeAll();
      expect(
        restored.service.calls.map((call) => call.music.id),
        unorderedEquals(['song-1', 'song-2', 'song-3']),
      );
      expect(
        restored.service.calls.map((call) => call.quality),
        everyElement(Quality.k320),
      );
      expect(
        restored.container.read(batchDownloadProvider).single.successCount,
        4,
      );
    },
  );

  test(
    'retry only restarts failures and paused tasks reserve their songs',
    () async {
      final fixture = await _fixture();
      final task = fixture.controller.create(musics: _songs(3));
      fixture.service.calls.first.completer.completeError(
        StateError('source failed'),
      );
      fixture.service.calls[1].complete();
      fixture.service.calls[2].complete();
      await _flush();
      expect(
        fixture.container.read(batchDownloadProvider).single.failedCount,
        1,
      );

      fixture.controller.retryFailed(task.id);
      expect(fixture.service.calls.last.music.id, 'song-0');
      fixture.controller.pause(task.id);
      await _flush();
      final duplicate = fixture.controller.create(musics: [_music('song-0')]);
      expect(duplicate.items, isEmpty);
      expect(duplicate.skippedCount, 1);
      fixture.controller.resume(task.id);
      await fixture.service.completeAll();
      final completed = fixture.container
          .read(batchDownloadProvider)
          .singleWhere((current) => current.id == task.id);
      expect(completed.successCount, 3);
      expect(completed.failedCount, 0);
      expect(
        fixture.service.calls.where((call) => call.music.id == 'song-1'),
        hasLength(1),
      );
    },
  );

  test('a file committed just before pause is counted once', () async {
    final fixture = await _fixture(finishAfterCancel: true);
    final task = fixture.controller.create(musics: _songs(1));
    fixture.controller.pause(task.id);
    fixture.service.calls.single.complete();
    await _flush();
    fixture.controller.resume(task.id);
    expect(
      fixture.container.read(batchDownloadProvider).single.successCount,
      1,
    );
    expect(fixture.service.calls, hasLength(1));
  });
}

Future<
  ({
    ProviderContainer container,
    BatchDownloadController controller,
    _ControlledDownloadService service,
  })
>
_fixture({bool finishAfterCancel = false}) async {
  final preferences = await SharedPreferences.getInstance();
  late _ControlledDownloadService service;
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(preferences),
      downloadServiceProvider.overrideWith(
        (ref) => service = _ControlledDownloadService(
          ref,
          finishAfterCancel: finishAfterCancel,
        ),
      ),
    ],
  );
  final controller = container.read(batchDownloadProvider.notifier);
  container.read(downloadServiceProvider);
  addTearDown(container.dispose);
  return (container: container, controller: controller, service: service);
}

class _ControlledDownloadService extends DownloadService {
  _ControlledDownloadService(super.ref, {required this.finishAfterCancel});

  final bool finishAfterCancel;
  final List<_Call> calls = [];
  int active = 0;
  int maxActive = 0;

  @override
  Future<DownloadResult> downloadOne({
    required MusicInfo music,
    Quality? quality,
    required EmbedRequest embed,
    CancelToken? cancelToken,
    String? batchTaskId,
  }) async {
    final call = _Call(music, quality, cancelToken!, batchTaskId!);
    calls.add(call);
    active += 1;
    if (active > maxActive) maxActive = active;
    try {
      return await Future.any([
        call.completer.future,
        if (!finishAfterCancel)
          cancelToken.whenCancel.then<DownloadResult>((error) => throw error),
      ]);
    } finally {
      call.ended = true;
      active -= 1;
    }
  }

  Future<void> completeAll() async {
    for (var round = 0; round < 10; round++) {
      for (final call in List.of(calls)) {
        if (!call.ended && !call.completer.isCompleted) call.complete();
      }
      await _flush();
      if (active == 0) return;
    }
    fail('downloads did not settle');
  }
}

class _Call {
  _Call(this.music, this.quality, this.token, this.batchId);

  final MusicInfo music;
  final Quality? quality;
  final CancelToken token;
  final String batchId;
  final Completer<DownloadResult> completer = Completer();
  bool ended = false;

  void complete() =>
      completer.complete(DownloadResult(path: 'D:/Music/${music.id}.mp3'));
}

Future<void> _flush() async {
  for (var i = 0; i < 4; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

List<MusicInfo> _songs(int count, {String prefix = 'song'}) => [
  for (var i = 0; i < count; i++) _music('$prefix-$i'),
];

MusicInfo _music(String id) => MusicInfo.fromJson({
  'id': id,
  'name': id,
  'singer': 'test',
  'source': 'wy',
  'meta': {
    'songId': id,
    'qualitys': [
      {'type': 'flac', 'size': '100'},
      {'type': '320k', 'size': '50'},
    ],
  },
});
