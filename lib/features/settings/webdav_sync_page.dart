import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_ui/prism_ui.dart' as prism;

import '../../core/sync/webdav_config_store.dart';
import '../../core/sync/webdav_sync_controller.dart';
import '../../core/ui/app_toast.dart';
import '../../core/ui/car_display_layout.dart';
import '../../theme/app_theme.dart';
import '../shell/shell_bottom_area.dart';
import '../shell/widgets/scrolling_page_header.dart';
import 'widgets/settings_action.dart';
import 'widgets/settings_sheet.dart';
import 'widgets/webdav_connection_fields.dart';

class WebDavSyncPage extends ConsumerStatefulWidget {
  const WebDavSyncPage({super.key});

  @override
  ConsumerState<WebDavSyncPage> createState() => _WebDavSyncPageState();
}

class _WebDavSyncPageState extends ConsumerState<WebDavSyncPage> {
  final _urlController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _autoSync = true;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadConfig());
  }

  Future<void> _loadConfig() async {
    final value = await ref.read(webDavSyncControllerProvider.future);
    if (!mounted) return;
    _urlController.text = value.config.baseUrl;
    _usernameController.text = value.config.username;
    _passwordController.text = value.config.password;
    setState(() {
      _autoSync = value.config.autoSync;
      _initialized = true;
    });
  }

  @override
  void dispose() {
    _urlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final asyncState = ref.watch(webDavSyncControllerProvider);
    final syncState = asyncState.valueOrNull;
    final busy = syncState?.busy ?? true;
    final configured = syncState?.config.isConfigured ?? false;
    final autoSync = configured ? syncState!.config.autoSync : _autoSync;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.appSettingsSurface,
      body: CustomScrollView(
        key: const PageStorageKey('webdav-sync-scroll'),
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        slivers: [
          const SliverToBoxAdapter(child: ScrollHeaderSpacer()),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              16,
              0,
              16,
              ShellBottomArea.contentPadding(context, 118),
            ),
            sliver: SliverToBoxAdapter(
              child: Center(
                child: ConstrainedBox(
                  constraints: CarDisplayLayout.contentConstraints(
                    context,
                    maxWidth: 640,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SettingsCard(
                        title: '连接',
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                            child: WebDavConnectionFields(
                              urlController: _urlController,
                              usernameController: _usernameController,
                              passwordController: _passwordController,
                              enabled: _initialized && !busy,
                              onSubmitted: _connect,
                            ),
                          ),
                          SettingsSwitchAction(
                            icon: Icons.sync_rounded,
                            title: '自动同步',
                            value: autoSync,
                            onChanged: busy
                                ? (_) {}
                                : (value) {
                                    setState(() => _autoSync = value);
                                    if (configured) {
                                      unawaited(
                                        ref
                                            .read(
                                              webDavSyncControllerProvider
                                                  .notifier,
                                            )
                                            .setAutoSync(value),
                                      );
                                    }
                                  },
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                            child: FilledButton.icon(
                              key: const ValueKey('webdav-connect-button'),
                              onPressed: _initialized && !busy
                                  ? _connect
                                  : null,
                              icon: Icon(
                                configured
                                    ? Icons.settings_ethernet_rounded
                                    : Icons.link_rounded,
                                size: 20,
                              ),
                              label: Text(configured ? '重新连接' : '连接'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SettingsCard(
                        insetContent: true,
                        title: '同步状态',
                        children: [
                          _SyncStatusRow(state: asyncState),
                          if (configured) ...[
                            const SizedBox(height: 18),
                            Wrap(
                              spacing: 12,
                              runSpacing: 10,
                              children: [
                                prism.FilledButton.icon(
                                  key: const ValueKey('webdav-sync-now-button'),
                                  onPressed: busy ? null : _syncNow,
                                  icon: const Icon(Icons.sync_rounded),
                                  label: const Text('立即同步'),
                                ),
                                prism.OutlinedButton.icon(
                                  key: const ValueKey('webdav-unlink-button'),
                                  onPressed: busy ? null : _unlink,
                                  icon: const Icon(Icons.link_off_rounded),
                                  label: const Text('解除连接'),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _connect() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final rawUrl = _urlController.text;
    String normalized;
    try {
      normalized = normalizeWebDavBaseUrl(rawUrl);
    } on FormatException catch (error) {
      showAppToast(context, error.message, type: AppToastType.warning);
      return;
    }
    if (Uri.parse(normalized).scheme == 'http') {
      final accepted = await _confirmInsecureConnection();
      if (!accepted || !mounted) return;
    }

    try {
      final preview = await ref
          .read(webDavSyncControllerProvider.notifier)
          .connect(
            baseUrl: normalized,
            username: _usernameController.text,
            password: _passwordController.text,
            autoSync: _autoSync,
          );
      if (!mounted) return;
      if (preview != null) {
        final useRemote = await _chooseInitialDirection(preview);
        if (useRemote == null || !mounted) return;
        await ref
            .read(webDavSyncControllerProvider.notifier)
            .completeInitialLink(useRemote: useRemote);
      }
      if (!mounted) return;
      showAppToast(context, 'WebDAV 已连接并完成同步', type: AppToastType.success);
    } catch (error) {
      if (!mounted) return;
      showAppToast(context, error.toString(), type: AppToastType.error);
    }
  }

  Future<void> _syncNow() async {
    FocusManager.instance.primaryFocus?.unfocus();
    try {
      await ref.read(webDavSyncControllerProvider.notifier).syncNow();
      if (!mounted) return;
      showAppToast(context, '同步完成', type: AppToastType.success);
    } catch (error) {
      if (!mounted) return;
      showAppToast(context, error.toString(), type: AppToastType.error);
    }
  }

  Future<void> _unlink() async {
    final confirmed =
        await showSettingsDialog<bool>(
          context: context,
          builder: (dialogContext) => prism.AlertDialog(
            title: '解除 WebDAV 连接？',
            actions: [
              prism.TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('取消'),
              ),
              prism.TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('解除连接'),
              ),
            ],
            child: const Text('只会删除本机连接信息，云端同步文件会保留。'),
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    await ref.read(webDavSyncControllerProvider.notifier).unlink();
    if (!mounted) return;
    _urlController.clear();
    _usernameController.clear();
    _passwordController.clear();
    setState(() => _autoSync = true);
    showAppToast(context, '已解除 WebDAV 连接', type: AppToastType.success);
  }

  Future<bool> _confirmInsecureConnection() async {
    return await showSettingsDialog<bool>(
          context: context,
          builder: (dialogContext) => prism.AlertDialog(
            title: '连接未加密',
            actions: [
              prism.TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('取消'),
              ),
              prism.TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('继续连接'),
              ),
            ],
            child: const Text('HTTP 会明文传输账号和同步数据，仅应在可信局域网中使用。'),
          ),
        ) ??
        false;
  }

  Future<bool?> _chooseInitialDirection(WebDavLinkPreview preview) {
    return showSettingsDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: prism.AlertDialog(
          title: '发现云端数据',
          actions: [
            prism.TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('用本机覆盖云端'),
            ),
            prism.TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('使用云端'),
            ),
          ],
          child: Text(
            '云端更新时间：${_formatDateTime(preview.generatedAt.toLocal())}\n'
            '歌单：${preview.playlistCount} 个 · 音源：${preview.musicSourceCount} 个',
          ),
        ),
      ),
    );
  }
}

class _SyncStatusRow extends StatelessWidget {
  const _SyncStatusRow({required this.state});

  final AsyncValue<WebDavSyncState> state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return state.when(
      loading: () => const prism.ListRow(
        padding: EdgeInsets.zero,
        leading: prism.ActivityIndicator(size: 24, semanticLabel: '正在读取配置'),
        title: Text('正在读取配置'),
      ),
      error: (error, _) => prism.ListRow(
        padding: EdgeInsets.zero,
        leading: Icon(Icons.error_outline_rounded, color: scheme.error),
        title: const Text('配置读取失败'),
        subtitle: Text(error.toString()),
      ),
      data: (value) {
        final (icon, title, subtitle) = switch (value.phase) {
          WebDavSyncPhase.unconfigured => (
            Icons.cloud_off_outlined,
            '未连接',
            '填写连接信息后开始同步',
          ),
          WebDavSyncPhase.connecting => (
            Icons.cloud_queue_rounded,
            '正在连接',
            value.config.baseUrl,
          ),
          WebDavSyncPhase.syncing => (
            Icons.sync_rounded,
            '正在同步',
            value.config.baseUrl,
          ),
          WebDavSyncPhase.failure => (
            Icons.sync_problem_rounded,
            '同步失败',
            value.errorMessage ?? '请检查网络和连接信息',
          ),
          WebDavSyncPhase.idle => (
            Icons.cloud_done_outlined,
            '已连接',
            value.lastSyncedAt == null
                ? value.config.baseUrl
                : '上次同步 ${_formatDateTime(value.lastSyncedAt!.toLocal())}',
          ),
        };
        return prism.ListRow(
          padding: EdgeInsets.zero,
          leading: Icon(
            icon,
            color: value.phase == WebDavSyncPhase.failure
                ? scheme.error
                : scheme.primary,
          ),
          title: Text(title),
          subtitle: Text(
            subtitle,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        );
      },
    );
  }
}

String _formatDateTime(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)} '
      '${two(value.hour)}:${two(value.minute)}';
}
