import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/saf_storage.dart';
import '../../../core/storage/settings_store.dart';
import '../../../core/ui/app_toast.dart';

class DirectoryPickerTile extends ConsumerWidget {
  const DirectoryPickerTile({super.key, required this.currentPath});

  final String currentPath;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          leading: const Icon(Icons.folder_outlined),
          title: const Text('下载位置'),
          subtitle: Text(
            SafStorage.label(currentPath),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _pick(context, ref),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(72, 0, 16, 12),
          child: Wrap(
            spacing: 8,
            children: [
              ActionChip(
                avatar: const Icon(Icons.refresh, size: 16),
                label: const Text('恢复默认'),
                onPressed: () async {
                  await ref
                      .read(settingsProvider.notifier)
                      .setDownloadDir(kDefaultDownloadDir);
                  if (!context.mounted) return;
                  showAppToast(
                    context,
                    '已恢复默认下载位置',
                    type: AppToastType.success,
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _pick(BuildContext context, WidgetRef ref) async {
    String? path;
    try {
      path = await SafStorage.pickDirectory(
        writable: true,
        initialLocation: currentPath,
      );
      if (!context.mounted || path == null) return;
      await SafStorage.validateDirectory(path, writable: true);
    } catch (error) {
      if (!context.mounted) return;
      showAppToast(
        context,
        error is PlatformException
            ? error.message ?? '无法选择文件夹'
            : '所选文件夹不可写，请重新选择',
        type: AppToastType.error,
      );
      return;
    }

    await ref.read(settingsProvider.notifier).setDownloadDir(path);
    if (!context.mounted) return;
    showAppToast(
      context,
      '下载目录已切换到 ${SafStorage.label(path)}',
      type: AppToastType.success,
    );
  }
}
