import 'dart:io';

import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PermissionService {
  const PermissionService._();

  // Persist the first storage-permission decision across app launches. A denied
  // request must not cause another system dialog every time a feature is used.
  static const _storagePermissionAttemptedKey =
      'storage_permission_request_attempted_v1';
  static Future<bool>? _pendingStoragePermissionRequest;

  static Future<bool> hasStoragePermissionRequestAttempted() async {
    if (!Platform.isAndroid) return false;
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(_storagePermissionAttemptedKey) ?? false;
  }

  /// Records a user's decision not to request storage access (for example,
  /// choosing "稍后再说" in the startup explanation dialog).
  static Future<void> markStoragePermissionRequestAttempted() async {
    if (!Platform.isAndroid) return;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_storagePermissionAttemptedKey, true);
  }

  static Future<bool> _requestStoragePermissionOnce(
    Future<PermissionStatus> Function() request,
  ) async {
    // Avoid two features racing to show separate permission dialogs.
    final pending = _pendingStoragePermissionRequest;
    if (pending != null) return pending;

    final requestFuture = _performStoragePermissionRequest(request);
    _pendingStoragePermissionRequest = requestFuture;
    try {
      return await requestFuture;
    } finally {
      if (identical(_pendingStoragePermissionRequest, requestFuture)) {
        _pendingStoragePermissionRequest = null;
      }
    }
  }

  static Future<bool> _performStoragePermissionRequest(
    Future<PermissionStatus> Function() request,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    if (preferences.getBool(_storagePermissionAttemptedKey) ?? false) {
      return false;
    }

    // Save before opening system UI so a denial (or interruption) is still
    // treated as the one allowed attempt on the next app launch.
    await preferences.setBool(_storagePermissionAttemptedKey, true);
    return (await request()).isGranted;
  }

  // Non-prompting check used on startup for the onboarding dialog.
  static Future<bool> hasExternalStorageWrite() async {
    if (!Platform.isAndroid) return true;

    // MANAGE_EXTERNAL_STORAGE is restricted below Android 11. There, the
    // storage group checks both READ and WRITE in legacy storage mode.
    final manage = await Permission.manageExternalStorage.status;
    if (!manage.isRestricted) return manage.isGranted;
    return Permission.storage.isGranted;
  }

  // Returns true once we have permission to write into a user-chosen public
  // directory (e.g. /storage/emulated/0/Music). The app makes at most one
  // automatic storage-permission request. If it is denied, the user can still
  // grant access manually from Android's app settings.
  static Future<bool> ensureExternalStorageWrite() async {
    if (!Platform.isAndroid) return true;

    final manage = await Permission.manageExternalStorage.status;
    if (!manage.isRestricted) {
      if (manage.isGranted) return true;
      return _requestStoragePermissionOnce(
        Permission.manageExternalStorage.request,
      );
    }

    if (await Permission.storage.isGranted) return true;
    return _requestStoragePermissionOnce(Permission.storage.request);
  }

  static Future<bool> ensureExternalStorageRead() async {
    if (!Platform.isAndroid) return true;

    final manage = await Permission.manageExternalStorage.status;
    if (manage.isGranted) return true;
    final audio = await Permission.audio.status;
    if (audio.isGranted) return true;

    if (!manage.isRestricted) {
      return _requestStoragePermissionOnce(
        Permission.manageExternalStorage.request,
      );
    }

    if (await Permission.storage.isGranted) return true;
    if (!audio.isRestricted) {
      return _requestStoragePermissionOnce(Permission.audio.request);
    }
    return _requestStoragePermissionOnce(Permission.storage.request);
  }

  /// JS scripts are documents: Android 13's audio permission cannot read them.
  static Future<bool> ensureScriptFileRead() async {
    if (!Platform.isAndroid) return true;

    final manage = await Permission.manageExternalStorage.status;
    if (!manage.isRestricted) {
      if (manage.isGranted) return true;
      return _requestStoragePermissionOnce(
        Permission.manageExternalStorage.request,
      );
    }
    if (await Permission.storage.isGranted) return true;
    return _requestStoragePermissionOnce(Permission.storage.request);
  }

  static Future<void> openSystemAppSettings() => openAppSettings();
}
