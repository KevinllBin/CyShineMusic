import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/batch_download_controller.dart';
import '../../../core/ui/configurable_m3e_progress.dart';
import '../download_progress.dart';

Future<void> showBatchDownloadTasksSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => const _BatchDownloadTasksSheet(),
  );
}

class BatchDownloadTasksButton extends ConsumerWidget {
  const BatchDownloadTasksButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(
      batchDownloadProvider.select((tasks) => tasks.length),
    );
    return FilledButton.tonalIcon(
      onPressed: () => showBatchDownloadTasksSheet(context),
      icon: const Icon(Icons.playlist_add_check_rounded, size: 20),
      label: Text(count == 0 ? '全部任务' : '全部任务 · $count'),
    );
  }
}

class _BatchDownloadTasksSheet extends ConsumerWidget {
  const _BatchDownloadTasksSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(batchDownloadProvider);
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.76,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('批量下载任务', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 6),
              Text(
                '共 ${tasks.length} 个任务 · 已下载的歌曲会保留',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: tasks.isEmpty
                    ? const Center(child: Text('暂无批量下载任务'))
                    : ListView.separated(
                        itemCount: tasks.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (_, index) => _BatchTaskCard(
                          key: ValueKey(tasks[index].id),
                          task: tasks[index],
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BatchTaskCard extends ConsumerWidget {
  const _BatchTaskCard({super.key, required this.task});

  final BatchDownloadTask task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(
      downloadProgressProvider.select(
        (progress) => progress.tasks
            .where((song) => song.batchTaskId == task.id && song.isBusy)
            .toList(growable: false),
      ),
    );
    final controller = ref.read(batchDownloadProvider.notifier);
    final scheme = Theme.of(context).colorScheme;
    final tone = task.failedCount > 0 && !task.hasPending
        ? scheme.error
        : scheme.primary;
    final status = !task.isRunning && task.hasPending && active.isNotEmpty
        ? '正在暂停'
        : task.statusLabel;
    final date = task.createdAt;
    final created =
        '${date.month}/${date.day} '
        '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';
    final lastError = task.items.where((item) => item.error != null).lastOrNull;
    final transferred = active.fold<double>(
      0,
      (sum, song) => sum + (song.fraction ?? 0),
    );
    final fraction = task.totalCount == 0
        ? 1.0
        : ((task.totalCount - task.pendingCount + transferred) /
                  task.totalCount)
              .clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  task.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const SizedBox(width: 12),
              Text(status, style: TextStyle(color: tone, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 6),
          SelectableText(
            'ID: ${task.id}',
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(
            '$created · ${task.quality.label} · 共 ${task.totalCount} 首',
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
          ),
          const SizedBox(height: 16),
          ConfigurableLinearProgressIndicatorM3E(
            value: fraction,
            trackThickness: 3,
            activeColor: tone,
            trackColor: scheme.surfaceContainerHighest,
            waveAmplitude: 1.3,
            trailingMargin: 8,
          ),
          const SizedBox(height: 10),
          Text(
            [
              '成功 ${task.successCount}',
              if (task.failedCount > 0) '失败 ${task.failedCount}',
              '待下 ${task.pendingCount}',
              if (task.skippedCount > 0) '跳过 ${task.skippedCount}',
            ].join(' · '),
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
          ),
          if (active.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              active.map((song) => song.name).join('、'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
            ),
          ],
          if (lastError != null) ...[
            const SizedBox(height: 6),
            Text(
              '${lastError.music.name}：${lastError.error}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: scheme.error, fontSize: 12),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            alignment: WrapAlignment.end,
            children: [
              TextButton.icon(
                onPressed: () => _remove(context, controller),
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                label: const Text('删除任务'),
              ),
              if (!task.isRunning && task.failedCount > 0)
                TextButton.icon(
                  onPressed: () => controller.retryFailed(task.id),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('重试失败'),
                ),
              if (task.hasPending)
                FilledButton.tonalIcon(
                  onPressed: () => task.isRunning
                      ? controller.pause(task.id)
                      : controller.resume(task.id),
                  icon: Icon(
                    task.isRunning
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    size: 18,
                  ),
                  label: Text(task.isRunning ? '暂停' : '继续下载'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _remove(
    BuildContext context,
    BatchDownloadController controller,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除下载任务？'),
        content: const Text('未完成的下载会取消，已下载的音乐和下载记录会保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除任务'),
          ),
        ],
      ),
    );
    if (confirmed == true) controller.remove(task.id);
  }
}
