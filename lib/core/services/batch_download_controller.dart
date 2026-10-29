import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/downloads/download_progress.dart';
import '../models/batch_download_task.dart';
import '../models/enums.dart';
import '../models/music_info.dart';
import '../storage/settings_store.dart';
import 'app_logger.dart';
import 'download_service.dart';

export '../models/batch_download_task.dart';

const batchDownloadStorageKey = 'batch_download_tasks_v1';

class BatchDownloadController extends Notifier<List<BatchDownloadTask>> {
  final Map<(String, int), CancelToken> _active = {};
  Future<void> _saveQueue = Future.value();
  var _sequence = 0;
  var _disposed = false;

  @override
  List<BatchDownloadTask> build() {
    _disposed = false;
    ref.onDispose(() {
      _disposed = true;
      for (final token in _active.values) {
        if (!token.isCancelled) token.cancel('任务管理器已关闭');
      }
    });
    final raw =
        ref
            .read(sharedPreferencesProvider)
            .getStringList(batchDownloadStorageKey) ??
        const [];
    final tasks = <BatchDownloadTask>[];
    for (final row in raw) {
      try {
        final task = BatchDownloadTask.fromJson(
          Map<String, dynamic>.from(jsonDecode(row) as Map),
        );
        if (task.id.isNotEmpty) tasks.add(task);
      } catch (_) {
        // A damaged task must not hide other saved tasks.
      }
    }
    return tasks;
  }

  BatchDownloadTask create({
    required List<MusicInfo> musics,
    String title = '批量下载',
    OnlinePlaybackQuality quality = OnlinePlaybackQuality.highest,
    int skippedCount = 0,
  }) {
    final reserved = {
      for (final task in state)
        for (final item in task.items)
          if (item.isPending) item.musicKey,
    };
    final progress = ref.read(downloadProgressProvider);
    final items = <BatchDownloadItem>[];
    for (final music in musics) {
      final item = BatchDownloadItem(music: music);
      if (!reserved.add(item.musicKey) || progress.isMusicBusy(music.id)) {
        skippedCount += 1;
        continue;
      }
      items.add(item);
    }
    final now = DateTime.now();
    final task = BatchDownloadTask(
      id: 'BD-${now.microsecondsSinceEpoch.toRadixString(36)}-${_sequence++}',
      title: title,
      createdAt: now,
      items: items,
      quality: quality,
      skippedCount: skippedCount,
      status: items.isEmpty
          ? BatchDownloadStatus.completed
          : BatchDownloadStatus.running,
    );
    state = [task, ...state];
    _persist();
    _pump();
    return task;
  }

  void pause(String id) {
    final task = _find(id);
    if (task == null || !task.isRunning) return;
    _replace(task.copyWith(status: BatchDownloadStatus.paused));
    for (final entry in _active.entries) {
      if (entry.key.$1 == id && !entry.value.isCancelled) {
        entry.value.cancel('批量任务已暂停');
      }
    }
  }

  void resume(String id) {
    final task = _find(id);
    if (task == null || task.isRunning || !task.hasPending) return;
    _replace(task.copyWith(status: BatchDownloadStatus.running));
    _pump();
  }

  void retryFailed(String id) {
    final task = _find(id);
    if (task == null || task.isRunning || task.failedCount == 0) return;
    _replace(
      task.copyWith(
        status: BatchDownloadStatus.running,
        items: [
          for (final item in task.items)
            if (item.error != null)
              BatchDownloadItem(music: item.music)
            else
              item,
        ],
      ),
    );
    _pump();
  }

  void remove(String id) {
    state = state.where((task) => task.id != id).toList(growable: false);
    _persist();
    for (final entry in _active.entries) {
      if (entry.key.$1 == id && !entry.value.isCancelled) {
        entry.value.cancel('批量任务已删除');
      }
    }
    _pump();
  }

  BatchDownloadTask? _find(String id) {
    for (final task in state) {
      if (task.id == id) return task;
    }
    return null;
  }

  void _replace(BatchDownloadTask task) {
    state = [
      for (final current in state) current.id == task.id ? task : current,
    ];
    _persist();
  }

  void _persist() {
    final prefs = ref.read(sharedPreferencesProvider);
    final rows = [for (final task in state) jsonEncode(task.toJson())];
    _saveQueue = _saveQueue
        .then((_) async {
          await prefs.setStringList(batchDownloadStorageKey, rows);
        })
        .catchError((Object error) {
          AppLogger.write('batch-download', 'save FAIL: $error');
        });
  }

  /// One scheduler caps concurrency across every managed batch.
  void _pump() {
    if (_disposed) return;
    for (final task in state.reversed) {
      if (!task.isRunning) continue;
      for (var i = 0; i < task.items.length; i++) {
        if (_active.length >= DownloadService.batchConcurrency) return;
        final key = (task.id, i);
        if (!task.items[i].isPending || _active.containsKey(key)) continue;
        final token = CancelToken();
        _active[key] = token;
        unawaited(_download(task, i, token));
      }
    }
  }

  Future<void> _download(
    BatchDownloadTask task,
    int index,
    CancelToken token,
  ) async {
    final item = task.items[index];
    try {
      final result = await ref
          .read(downloadServiceProvider)
          .downloadOne(
            music: item.music,
            quality: task.quality.preferredQuality == null
                ? null
                : item.music.playbackQualityFor(task.quality),
            embed: const EmbedRequest.richest(),
            cancelToken: token,
            batchTaskId: task.id,
          );
      _finishItem(
        task.id,
        index,
        BatchDownloadItem(music: item.music, savedPath: result.path),
      );
    } catch (error) {
      if (!token.isCancelled) {
        _finishItem(
          task.id,
          index,
          BatchDownloadItem(music: item.music, error: error.toString()),
        );
      }
    } finally {
      _active.remove((task.id, index));
      _pump();
    }
  }

  void _finishItem(String id, int index, BatchDownloadItem item) {
    if (_disposed) return;
    final task = _find(id);
    if (task == null) return; // Deleted tasks must never reappear.
    final items = [...task.items]..[index] = item;
    _replace(
      task.copyWith(
        items: items,
        status: items.any((item) => item.isPending)
            ? task.status
            : BatchDownloadStatus.completed,
      ),
    );
  }
}

final batchDownloadProvider =
    NotifierProvider<BatchDownloadController, List<BatchDownloadTask>>(
      BatchDownloadController.new,
    );
