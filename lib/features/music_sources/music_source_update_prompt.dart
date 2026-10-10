import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/music_sources/music_source_controller.dart';
import '../../core/music_sources/music_source_models.dart';
import '../../core/music_sources/music_source_runtime.dart';
import '../../core/music_sources/music_source_updates.dart';
import '../../core/ui/app_toast.dart';

class MusicSourceUpdatePrompt extends ConsumerStatefulWidget {
  const MusicSourceUpdatePrompt({
    super.key,
    required this.navigatorKey,
    required this.ready,
    required this.child,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final bool ready;
  final Widget child;

  @override
  ConsumerState<MusicSourceUpdatePrompt> createState() =>
      _MusicSourceUpdatePromptState();
}

class _MusicSourceUpdatePromptState
    extends ConsumerState<MusicSourceUpdatePrompt>
    with WidgetsBindingObserver {
  bool _scheduled = false;
  bool _showing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _schedulePrompt();
  }

  bool get _canShow {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    return mounted &&
        widget.ready &&
        (lifecycle == null || lifecycle == AppLifecycleState.resumed);
  }

  void _schedulePrompt() {
    if (!_canShow ||
        _scheduled ||
        _showing ||
        ref.read(musicSourceUpdatesProvider).isEmpty) {
      return;
    }
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (mounted) unawaited(_showNext());
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _showNext() async {
    if (!_canShow || _showing) return;
    final sources = ref.read(musicSourceControllerProvider).valueOrNull;
    if (sources == null || sources.activatingId != null) return;
    final context = widget.navigatorKey.currentContext;
    if (context == null || !context.mounted) return;

    final updates = ref.read(musicSourceUpdatesProvider.notifier);
    for (final notice in ref.read(musicSourceUpdatesProvider)) {
      MusicSourceRecord? record;
      for (final candidate in sources.records) {
        if (notice.matches(candidate)) {
          record = candidate;
          break;
        }
      }
      if (record == null) {
        // Ignore events from a script that was removed or replaced meanwhile.
        updates.dismiss(notice);
        continue;
      }
      _showing = true;
      try {
        final updated = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (_) =>
              _MusicSourceUpdateDialog(record: record!, notice: notice),
        );
        if (mounted && context.mounted && updated != null) {
          showAppToast(
            context,
            updated ? '已更新 ${record.name}' : '脚本内容无变化，已保留当前版本',
            type: AppToastType.success,
          );
        }
      } finally {
        if (mounted) updates.dismiss(notice);
        _showing = false;
        if (mounted) _schedulePrompt();
      }
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(musicSourceUpdatesProvider);
    ref.watch(musicSourceControllerProvider);
    _schedulePrompt();
    return widget.child;
  }
}

class _MusicSourceUpdateDialog extends ConsumerStatefulWidget {
  const _MusicSourceUpdateDialog({required this.record, required this.notice});

  final MusicSourceRecord record;
  final MusicSourceUpdateNotice notice;

  @override
  ConsumerState<_MusicSourceUpdateDialog> createState() =>
      _MusicSourceUpdateDialogState();
}

class _MusicSourceUpdateDialogState
    extends ConsumerState<_MusicSourceUpdateDialog> {
  bool _updating = false;
  String? _error;

  Future<void> _copyUrl() async {
    try {
      await Clipboard.setData(ClipboardData(text: widget.notice.updateUrl));
      if (mounted) showAppToast(context, '已复制更新 URL');
    } catch (_) {
      if (mounted) {
        showAppToast(context, '复制失败，请稍后重试', type: AppToastType.error);
      }
    }
  }

  Future<void> _update() async {
    if (_updating) return;
    setState(() {
      _updating = true;
      _error = null;
    });
    try {
      final updated = await ref
          .read(musicSourceControllerProvider.notifier)
          .updateScript(widget.notice);
      if (!mounted) return;
      // Allow the programmatic pop after blocking back during the update.
      setState(() => _updating = false);
      Navigator.of(context).pop(updated);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _updating = false;
        _error = switch (error) {
          MusicSourceRuntimeException() => error.message,
          FormatException() => '更新脚本格式无效：${error.message}',
          _ => '更新失败，请稍后重试',
        };
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: !_updating,
      child: AlertDialog(
        icon: const Icon(Icons.system_update_alt_rounded),
        title: const Text('音源有更新'),
        content: SizedBox(
          width: 420,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.5,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.record.name, style: theme.textTheme.titleMedium),
                  if (widget.record.version.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      '当前版本：${widget.record.version}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  SelectableText(
                    widget.notice.log.isEmpty ? '作者未提供更新说明' : widget.notice.log,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        actions: [
          SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _updating
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: const Text('稍后'),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: OutlinedButton.icon(
                          onPressed: _updating ? null : _copyUrl,
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                          icon: const Icon(Icons.copy_rounded, size: 18),
                          label: const Text('复制 URL', maxLines: 1),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: FilledButton(
                          onPressed: _updating ? null : _update,
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                          child: _updating
                              ? const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SizedBox.square(
                                      dimension: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                    SizedBox(width: 8),
                                    Text('更新中…'),
                                  ],
                                )
                              : const Text('立即更新'),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
