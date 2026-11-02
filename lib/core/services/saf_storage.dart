import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'storage_location.dart';

/// The stored location is either a legacy filesystem path or an opaque SAF URI.
class SafStorage {
  static const _channel = MethodChannel('cy_shine_music/saf_storage');
  static final Map<String, String> _labels = {};
  static const _labelPrefix = 'saf_directory_label:';

  static void loadLabels(SharedPreferences prefs) {
    for (final key in prefs.getKeys().where(
      (k) => k.startsWith(_labelPrefix),
    )) {
      _labels[key.substring(_labelPrefix.length)] = prefs.getString(key)!;
    }
  }

  static String label(String location) =>
      _labels[location] ?? storageLocationLabel(location);

  static Future<String?> pickDirectory({
    required bool writable,
    String? initialLocation,
  }) async {
    if (!Platform.isAndroid) {
      return FilePicker.platform.getDirectoryPath(lockParentWindow: true);
    }
    final selected = await _channel.invokeMapMethod<String, dynamic>(
      'pickDirectory',
      {'writable': writable, 'initialUri': initialLocation},
    );
    if (selected == null) return null;
    final uri = selected['uri'] as String;
    final name = selected['name'] as String;
    _labels[uri] = name;
    await (await SharedPreferences.getInstance()).setString(
      '$_labelPrefix$uri',
      name,
    );
    return uri;
  }

  static Future<void> validateDirectory(
    String location, {
    required bool writable,
  }) async {
    if (isContentLocation(location)) {
      await _channel.invokeMethod<void>('validateDirectory', {
        'uri': location,
        'writable': writable,
      });
      return;
    }
    final directory = Directory(location);
    if (!await directory.exists()) throw const FileSystemException('目录不存在');
    if (!writable) {
      await directory.list(followLinks: false).take(1).drain<void>();
      return;
    }
    final probe = await directory.createTemp('.cyshine-probe-');
    try {
      await File('${probe.path}/write-test').writeAsString('ok');
    } finally {
      await probe.delete(recursive: true);
    }
  }

  static Future<List<Map<String, dynamic>>> scan(String uri) async {
    final rows = await _channel.invokeListMethod<dynamic>('scan', {'uri': uri});
    return [
      for (final row in rows ?? []) Map<String, dynamic>.from(row as Map),
    ];
  }

  static Future<String> saveFile(
    String tree,
    String source,
    String name,
  ) async => (await _channel.invokeMethod<String>('saveFile', {
    'uri': tree,
    'source': source,
    'name': name,
  }))!;

  static Future<bool> exists(String location) async {
    if (!isContentLocation(location)) return File(location).exists();
    return await _channel.invokeMethod<bool>('exists', {'uri': location}) ??
        false;
  }

  static Future<int> size(String location) async {
    if (!isContentLocation(location)) return File(location).length();
    return await _channel.invokeMethod<int>('size', {'uri': location}) ?? 0;
  }

  /// Files are removed only after native confirmation. Cancellation and partial
  /// success are returned separately so callers retain undeleted records.
  static Future<FileDeletionResult> deleteFiles(
    Iterable<String> locations,
  ) async {
    if (!Platform.isAndroid) throw UnsupportedError('系统删除确认仅支持 Android');
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'deleteFiles',
      {'paths': locations.where((p) => p.isNotEmpty).toSet().toList()},
    );
    if (result == null) throw StateError('未收到删除结果');
    return FileDeletionResult(
      deletedPaths: Set<String>.from(
        result['deletedPaths'] as List? ?? const [],
      ),
      failed: Map<String, String>.from(result['failed'] as Map? ?? const {}),
      cancelled: result['cancelled'] == true,
    );
  }
}

class FileDeletionResult {
  const FileDeletionResult({
    required this.deletedPaths,
    required this.failed,
    required this.cancelled,
  });

  final Set<String> deletedPaths;
  final Map<String, String> failed;
  final bool cancelled;
}
