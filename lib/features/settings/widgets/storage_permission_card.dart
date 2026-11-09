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
  bool? _audioGranted;
  bool? _wideGranted;
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
    if (state == AppLifecycleState.resumed) unawaited(_refreshPermission());
  }

  Future<void> _refreshPermission() async {
    try {
      final status = await Future.wait([
        PermissionService.hasAudioLibraryRead(),
        PermissionService.hasExternalStorageWrite(),
      ]);
      if (!mounted) return;
      final newlyGranted =
          (status[0] && _audioGranted == false) ||
          (status[1] && _wideGranted == false);
      setState(() {
        _audioGranted = status[0];
        _wideGranted = status[1];
        _checkFailed = false;
      });
      if (newlyGranted) {
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

  Future<void> _requestPermission({bool compatibility = false}) async {
    if (_requesting) return;
    setState(() => _requesting = true);
    try {
      if (compatibility) {
        await PermissionService.openExternalStorageSettings();
        await _refreshPermission();
        return;
      }
      if (_audioGranted == true) {
        await PermissionService.openSystemAppSettings();
        return;
      }
      final granted = await PermissionService.requestAudioLibraryRead();
      await _refreshPermission();
      if (!mounted) return;
      showAppToast(
        context,
        granted ? '已允许读取本地音乐' : '未允许读取本地音乐，可稍后重新授权',
        type: granted ? AppToastType.success : AppToastType.warning,
      );
    } catch (_) {
      if (mounted) {
        showAppToast(context, '权限申请失败，请在系统设置中检查', type: AppToastType.error);
      }
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SettingsCard(
      title: '权限',
      children: [
        SettingsAction(
          icon: Icons.library_music_outlined,
          title: '音乐和音频',
          value: _checkFailed ? '检查失败' : null,
          trailing: _audioGranted == true
              ? Icons.check_circle_outline_rounded
              : Icons.chevron_right_rounded,
          onTap: () => _requestPermission(),
        ),
        SettingsAction(
          icon: Icons.folder_shared_outlined,
          title: '所有文件访问（兼容）',
          value: _checkFailed ? '检查失败' : null,
          trailing: _wideGranted == true
              ? Icons.check_circle_outline_rounded
              : Icons.chevron_right_rounded,
          onTap: () => _requestPermission(compatibility: true),
        ),
      ],
    );
  }
}
