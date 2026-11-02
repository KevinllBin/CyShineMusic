import 'dart:io';

import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PermissionService {
  const PermissionService._();

  static const _storagePermissionAttemptedKey =
      'storage_permission_request_attempted_v1';
  static Future<bool>? _pendingStoragePermissionRequest;

  static Future<bool> hasStoragePermissionRequestAttempted() async {
    if (!Platform.isAndroid) return false;
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(_storagePermissionAttemptedKey) ?? false;
  }

  static Future<void> markStoragePermissionRequestAttempted() async {
    if (!Platform.isAndroid) return;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_storagePermissionAttemptedKey, true);
  }

  // Feature entry points only check access; they must never open system UI.
  static Future<bool> hasExternalStorageWrite() async {
    if (!Platform.isAndroid) return true;

    // MANAGE_EXTERNAL_STORAGE is restricted below Android 11. There, the
    // storage group checks both READ and WRITE in legacy storage mode.
    final manage = await Permission.manageExternalStorage.status;
    if (!manage.isRestricted) return manage.isGranted;
    return Permission.storage.isGranted;
  }

  static Future<bool> hasExternalStorageRead() async {
    if (!Platform.isAndroid) return true;

    if (await Permission.manageExternalStorage.isGranted) return true;
    if (await Permission.audio.isGranted) return true;
    return Permission.storage.isGranted;
  }

  /// JS scripts need all-files access on Android 11+, or legacy storage access.
  static Future<bool> hasScriptFileRead() => hasExternalStorageWrite();

  /// Called only after accepting the first startup explanation or tapping the
  /// permission entry in Settings. Explicit requests remain available later.
  static Future<bool> requestExternalStorageWrite() async {
    if (!Platform.isAndroid) return true;

    final pending = _pendingStoragePermissionRequest;
    if (pending != null) return pending;
    final request = _requestExternalStorageWrite();
    _pendingStoragePermissionRequest = request;
    try {
      return await request;
    } finally {
      _pendingStoragePermissionRequest = null;
    }
  }

  static Future<bool> _requestExternalStorageWrite() async {
    await markStoragePermissionRequestAttempted();
    final manage = await Permission.manageExternalStorage.status;
    if (!manage.isRestricted) {
      if (manage.isGranted) return true;
      return (await Permission.manageExternalStorage.request()).isGranted;
    }

    final storage = await Permission.storage.status;
    if (storage.isGranted) return true;
    if (storage.isPermanentlyDenied) {
      // Legacy Android no longer shows a dialog after "don't ask again".
      await openSystemAppSettings();
    } else {
      await Permission.storage.request();
    }
    // The callback may describe READ only; also verify the WRITE group status.
    return Permission.storage.isGranted;
  }

  static Future<void> openSystemAppSettings() => openAppSettings();
}
