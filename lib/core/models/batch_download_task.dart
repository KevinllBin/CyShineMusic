import 'enums.dart';
import 'music_info.dart';

enum BatchDownloadStatus { running, paused, completed }

class BatchDownloadItem {
  const BatchDownloadItem({required this.music, this.savedPath, this.error});

  final MusicInfo music;
  final String? savedPath;
  final String? error;

  bool get isCompleted => savedPath != null;
  bool get isPending => savedPath == null && error == null;

  String get musicKey =>
      '${music.source.code}\u0000${music.id.trim().isEmpty ? '${music.name.trim()}\u0000${music.singer.trim()}' : music.id.trim()}';

  Map<String, dynamic> toJson() => {
    'music': music.toJson(),
    if (savedPath != null) 'savedPath': savedPath,
    if (error != null) 'error': error,
  };

  factory BatchDownloadItem.fromJson(Map<String, dynamic> json) {
    return BatchDownloadItem(
      music: MusicInfo.fromJson(
        Map<String, dynamic>.from(json['music'] as Map),
      ),
      savedPath: json['savedPath'] as String?,
      error: json['error'] as String?,
    );
  }
}

class BatchDownloadTask {
  const BatchDownloadTask({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.items,
    this.status = BatchDownloadStatus.running,
    this.quality = OnlinePlaybackQuality.highest,
    this.skippedCount = 0,
  });

  final String id;
  final String title;
  final DateTime createdAt;
  final List<BatchDownloadItem> items;
  final BatchDownloadStatus status;
  final OnlinePlaybackQuality quality;
  final int skippedCount;

  int get successCount => items.where((item) => item.isCompleted).length;
  int get failedCount => items.where((item) => item.error != null).length;
  int get pendingCount => items.where((item) => item.isPending).length;
  int get totalCount => items.length + skippedCount;
  bool get hasPending => items.any((item) => item.isPending);
  bool get isRunning => status == BatchDownloadStatus.running;

  double get fraction =>
      totalCount == 0 ? 1 : (totalCount - pendingCount) / totalCount;

  String get statusLabel => switch (status) {
    BatchDownloadStatus.running => '下载中',
    BatchDownloadStatus.paused => '已暂停',
    BatchDownloadStatus.completed => failedCount > 0 ? '已结束，有失败' : '已完成',
  };

  BatchDownloadTask copyWith({
    List<BatchDownloadItem>? items,
    BatchDownloadStatus? status,
  }) => BatchDownloadTask(
    id: id,
    title: title,
    createdAt: createdAt,
    items: items ?? this.items,
    status: status ?? this.status,
    quality: quality,
    skippedCount: skippedCount,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'createdAt': createdAt.toIso8601String(),
    'status': status.name,
    'quality': quality.code,
    'skippedCount': skippedCount,
    'items': [for (final item in items) item.toJson()],
  };

  factory BatchDownloadTask.fromJson(Map<String, dynamic> json) {
    final items = [
      for (final item in json['items'] as List)
        BatchDownloadItem.fromJson(Map<String, dynamic>.from(item as Map)),
    ];
    return BatchDownloadTask(
      id: json['id'] as String,
      title: json['title'] as String? ?? '批量下载',
      createdAt: DateTime.parse(json['createdAt'] as String),
      items: items,
      // An interrupted app session must never silently restart downloads.
      status: items.any((item) => item.isPending)
          ? BatchDownloadStatus.paused
          : BatchDownloadStatus.completed,
      quality: OnlinePlaybackQuality.fromCode(json['quality'] as String?),
      skippedCount: json['skippedCount'] as int? ?? 0,
    );
  }
}
