import 'settings_sheet.dart';
import 'package:flutter/material.dart';
import 'package:prism_ui/prism_ui.dart' as prism;

import '../../../core/services/storage_browser_service.dart';
import '../../../core/ui/widgets/app_navigation_button.dart';
import '../../../theme/app_motion.dart';

Future<String?> showStorageFolderPickerSheet(
  BuildContext context, {
  String title = '选择文件夹',
  String? initialPath,
  Set<String>? fileExtensions,
  StorageBrowserService service = const StorageBrowserService(),
}) {
  return showSettingsSheet<String>(
    context: context,
    useRootNavigator: true,

    heightFraction: 0.76,
    maxHeight: 800,

    builder: (context) => StorageFolderPickerSheet(
      title: title,
      initialPath: initialPath,
      fileExtensions: fileExtensions,
      service: service,
    ),
  );
}

class StorageFolderPickerSheet extends StatefulWidget {
  const StorageFolderPickerSheet({
    super.key,
    required this.title,
    required this.service,
    this.initialPath,
    this.fileExtensions,
  });

  final String title;
  final String? initialPath;

  /// Null selects folders; otherwise tapping a matching file returns its path.
  final Set<String>? fileExtensions;
  final StorageBrowserService service;

  @override
  State<StorageFolderPickerSheet> createState() =>
      _StorageFolderPickerSheetState();
}

class _StorageFolderPickerSheetState extends State<StorageFolderPickerSheet> {
  final List<String?> _history = [];
  String? _currentPath;
  List<StorageBrowserEntry> _entries = const [];
  bool _loading = true;
  String? _error;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _currentPath = widget.initialPath?.trim().isEmpty == true
        ? null
        : widget.initialPath;
    _load();
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final path = _currentPath;
      final entries = path == null
          ? await widget.service.listRoots()
          : await widget.service.listChildren(
              path,
              fileExtensions: widget.fileExtensions,
            );
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _entries = entries;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _entries = const [];
        _loading = false;
        _error = '$error';
      });
    }
  }

  void _open(StorageBrowserEntry entry) {
    if (!entry.canRead) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法读取此项目')));
      return;
    }
    if (!entry.isDirectory) {
      if (widget.fileExtensions != null) Navigator.of(context).pop(entry.path);
      return;
    }
    _history.add(_currentPath);
    _currentPath = entry.path;
    _load();
  }

  void _back() {
    if (_history.isEmpty) {
      _currentPath = null;
    } else {
      _currentPath = _history.removeLast();
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final currentPath = _currentPath;
    return PopScope<String>(
      canPop: currentPath == null,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _back();
      },
      child: SettingsSheetLayout(
        title: widget.title,
        subtitle: currentPath ?? '存储位置',
        onClose: () => Navigator.of(context).pop(),
        leading: currentPath == null && _history.isEmpty
            ? null
            : AppNavigationButton.back(tooltip: '返回上一级', onPressed: _back),
        trailing: prism.IconButton(
          tooltip: '刷新',
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh_rounded),
        ),
        body: _buildBody(context),
        actions: [
          prism.OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          if (widget.fileExtensions == null)
            prism.FilledButton.icon(
              onPressed: currentPath == null || _loading || _error != null
                  ? null
                  : () => Navigator.of(context).pop(currentPath),
              icon: const Icon(Icons.check_rounded),
              label: const Text('选择此文件夹'),
            ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final error = _error;
    if (error != null) {
      return _PickerMessage(
        icon: Icons.folder_off_outlined,
        title: '无法读取文件夹',
        subtitle: error,
        action: prism.TextButton.icon(
          onPressed: _load,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('重试'),
        ),
      );
    }
    if (_entries.isEmpty) {
      return _PickerMessage(
        icon: Icons.folder_open_outlined,
        title: _currentPath == null
            ? '没有可浏览的存储位置'
            : widget.fileExtensions == null
            ? '没有子文件夹'
            : '没有可导入的脚本或子文件夹',
        subtitle: _currentPath == null ? '请确认已授予存储访问权限' : _currentPath!,
        action: prism.TextButton.icon(
          onPressed: _load,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('刷新'),
        ),
      );
    }
    return AnimatedSwitcher(
      duration: AppMotion.medium,
      child: ListView.builder(
        key: ValueKey(_currentPath ?? 'roots'),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
        itemCount: _entries.length,
        itemBuilder: (context, index) {
          final entry = _entries[index];
          return _StorageEntryTile(entry: entry, onTap: () => _open(entry));
        },
      ),
    );
  }
}

class _StorageEntryTile extends StatelessWidget {
  const _StorageEntryTile({required this.entry, required this.onTap});

  final StorageBrowserEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final subtitle = entry.isRoot ? _rootSubtitle(entry) : entry.path;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: prism.Card(
        radius: 18,
        onPressed: entry.canRead ? onTap : null,
        child: prism.ListRow(
          leading: Icon(
            entry.isRoot
                ? Icons.storage_rounded
                : entry.isDirectory
                ? Icons.folder_rounded
                : Icons.javascript_rounded,
            color: entry.canRead ? scheme.primary : scheme.outline,
          ),
          title: Text(entry.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Icon(
            entry.isDirectory
                ? Icons.chevron_right_rounded
                : Icons.file_open_outlined,
          ),
        ),
      ),
    );
  }

  String _rootSubtitle(StorageBrowserEntry entry) {
    final parts = <String>[entry.path];
    final capacity = _formatCapacity(entry);
    if (capacity != null) parts.add(capacity);
    if (entry.isReadOnly) parts.add('只读');
    return parts.join(' · ');
  }

  String? _formatCapacity(StorageBrowserEntry entry) {
    if (entry.totalBytes <= 0) return null;
    final used = entry.totalBytes - entry.freeBytes;
    return '${_formatBytes(used)} / ${_formatBytes(entry.totalBytes)}';
  }

  String _formatBytes(int bytes) {
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var value = bytes.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    if (unit == 0) return '${value.toStringAsFixed(0)} ${units[unit]}';
    return '${value.toStringAsFixed(value >= 10 ? 1 : 2)} ${units[unit]}';
  }
}

class _PickerMessage extends StatelessWidget {
  const _PickerMessage({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.action,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 38, color: scheme.outline),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.outline),
              ),
              const SizedBox(height: 14),
              action,
            ],
          ),
        ),
      ),
    );
  }
}
