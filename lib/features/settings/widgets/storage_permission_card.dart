import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/permission_service.dart';
import '../../../core/storage/settings_store.dart';
import '../../../core/ui/app_toast.dart';
import '../../songs/local_song_scan_cache.dart';
import 'settings_action.dart';

class StoragePermissionCard extends ConsumerStatefulWidget {
  const StoragePermissionCard({super.key});

  @override
  ConsumerState<StoragePermissionCard> createState() =>
      _StoragePermissionCardState();
}

class _StoragePermissionCardState extends ConsumerState<StoragePermissionCard>
    with WidgetsBindingObserver {
  bool? _granted;
  bool _requesting = false;
  bool _checkFailed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refreshPermission());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshPermission());
    }
  }

  Future<void> _refreshPermission() async {
    try {
      final granted = await PermissionService.hasExternalStorageWrite();
      if (!mounted) return;
      final wasGranted = _granted;
      setState(() {
        _granted = granted;
        _checkFailed = false;
      });
      if (granted && wasGranted == false) {
        unawaited(
          ref
              .read(localSongScanCacheProvider)
              .refresh(directories: ref.read(settingsProvider).localMusicDirs),
        );
      }
    } catch (_) {
      if (mounted) setState(() => _checkFailed = true);
    }
  }

  Future<void> _requestPermission() async {
    if (_requesting) return;
    setState(() => _requesting = true);
    try {
      final granted = await PermissionService.requestExternalStorageWrite();
      await _refreshPermission();
      if (!mounted) return;
      showAppToast(
        context,
        granted ? '已授予存储权限' : '未授予存储权限，内置目录暂不可用',
        type: granted ? AppToastType.success : AppToastType.warning,
      );
    } catch (_) {
      if (!mounted) return;
      showAppToast(context, '权限申请失败，请稍后重试或在系统设置中开启', type: AppToastType.error);
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final granted = _granted == true;
    final subtitle = _checkFailed
        ? '无法读取权限状态，点击重新申请'
        : _requesting
        ? '请在系统界面允许存储访问，返回后会自动检查'
        : _granted == null
        ? '正在检查存储权限'
        : granted
        ? '可使用内置目录选择器、下载音乐和扫描本地文件夹'
        : '未授权；仍可通过系统选择器单独授权下载和扫描文件夹';
    return SettingsCard(
      title: '权限',
      children: [
        SettingsAction(
          icon: Icons.folder_shared_outlined,
          title: granted ? '存储权限已授予' : '授予存储权限',
          subtitle: subtitle,
          trailing: granted
              ? Icons.check_circle_outline_rounded
              : Icons.chevron_right_rounded,
          onTap: _requestPermission,
        ),
      ],
    );
  }
}
