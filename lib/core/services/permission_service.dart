import 'dart:io';

import 'package:permission_handler/permission_handler.dart';

class PermissionService {
  const PermissionService._();

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
  // directory (e.g. /storage/emulated/0/Music). Strategy:
  //   1. On non-Android, no-op.
  //   2. Request MANAGE_EXTERNAL_STORAGE on Android 11+.
  //   3. Request READ and WRITE on Android 10 and below, with
  //      requestLegacyExternalStorage in the manifest for Android 10.
  // If denied, callers should fall back to the app-private dir.
  static Future<bool> ensureExternalStorageWrite() async {
    if (!Platform.isAndroid) return true;

    final manage = await Permission.manageExternalStorage.status;
    if (!manage.isRestricted) {
      if (manage.isGranted) return true;
      return (await Permission.manageExternalStorage.request()).isGranted;
    }

    await Permission.storage.request();
    // The request callback can report the READ result for the storage group.
    // Recheck to ensure WRITE was granted as well.
    return Permission.storage.isGranted;
  }

  static Future<bool> ensureExternalStorageRead() async {
    if (!Platform.isAndroid) return true;

    final manage = await Permission.manageExternalStorage.request();
    if (manage.isGranted) return true;

    final audio = await Permission.audio.request();
    if (audio.isGranted) return true;

    final legacy = await Permission.storage.request();
    return legacy.isGranted;
  }

  static Future<void> openSystemAppSettings() => openAppSettings();
}
