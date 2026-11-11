import 'package:flutter/material.dart';

import '../../../core/services/app_logger.dart';
import '../../../core/services/log_category.dart';
import '../../../core/ui/app_toast.dart';
import '../../settings/widgets/settings_menu.dart';

class LogRecordingMenu extends StatefulWidget {
  const LogRecordingMenu({super.key, this.menuId = 'log-recording-menu'});

  final String menuId;

  @override
  State<LogRecordingMenu> createState() => _LogRecordingMenuState();
}

class _LogRecordingMenuState extends State<LogRecordingMenu> {
  bool _saving = false;

  Future<void> _save(Set<AppLogCategory> categories) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await AppLogger.setRecordingCategories(categories);
    } catch (_) {
      if (mounted) {
        showAppToast(context, '日志设置保存失败，请重试', type: AppToastType.error);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Set<AppLogCategory>>(
      valueListenable: AppLogger.recordingCategories,
      builder: (context, enabled, _) => SettingsMenuAction(
        key: ValueKey(widget.menuId),
        menuId: widget.menuId,
        icon: Icons.receipt_long_outlined,
        title: '记录分类',
        subtitle: enabled.isEmpty
            ? '未开启日志记录，点击选择（可多选）'
            : '正在记录：${AppLogCategory.values.where(enabled.contains).map((item) => item.label).join('、')}',
        multiSelect: true,
        options: [
          for (final category in AppLogCategory.values)
            SettingsMenuOption(
              id: category.name,
              label: category.label,
              selected: enabled.contains(category),
              enabled: !_saving,
              onSelected: () => _save({
                ...enabled.where((item) => item != category),
                if (!enabled.contains(category)) category,
              }),
            ),
          SettingsMenuOption(
            id: 'disable-all',
            label: '全部关闭',
            selected: enabled.isEmpty,
            enabled: !_saving && enabled.isNotEmpty,
            onSelected: () => _save({}),
          ),
        ],
      ),
    );
  }
}
