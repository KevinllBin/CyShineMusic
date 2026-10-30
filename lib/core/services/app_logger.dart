import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'log_category.dart';
import 'log_policy.dart';

// File-backed log so the user can hand over a real trace when something
// looks wrong. Each line is `ISO8601 [scope] message`, persisted to
// `<app-documents>/logs/cyshine.log` (rotated at 1 MiB).
class AppLogger {
  const AppLogger._();

  static final _live = StreamController<String>.broadcast(sync: false);
  static final List<String> _recent = <String>[];
  static File? _file;
  static final _policy = LogPolicy();
  static const recordingPreferenceKey = 'log_recording_categories';
  static final _recordingCategories = ValueNotifier<Set<AppLogCategory>>(
    const {},
  );
  static SharedPreferences? _preferences;
  static Future<void> _writeChain = Future<void>.value();
  static int _writtenBytes = 0;
  static Future<void>? _initFuture;
  static const _maxBytes = 1024 * 1024;
  static const _maxRecentLines = 500;
  static final sessionId = '${DateTime.now().microsecondsSinceEpoch}-$pid';
  static String _environment = 'environment=unavailable';
  static String _androidDiagnostics = 'unavailable';

  static ValueListenable<Set<AppLogCategory>> get recordingCategories =>
      _recordingCategories;

  static bool isRecording(AppLogCategory category) =>
      _recordingCategories.value.contains(category);

  static bool isRecordingScope(String scope) =>
      isRecording(logCategoryForScope(scope));

  static void configureRecording(SharedPreferences preferences) {
    _drainPolicy();
    _policy.clear();
    _preferences = preferences;
    _recordingCategories.value = Set.unmodifiable(
      decodeLogCategories(preferences.getStringList(recordingPreferenceKey)),
    );
  }

  static Future<void> setRecordingCategories(
    Set<AppLogCategory> categories,
  ) async {
    final preferences = _preferences;
    if (preferences == null) throw StateError('日志设置尚未初始化');
    final previous = _recordingCategories.value;
    _drainPolicy();
    _policy.clear();
    final next = Set<AppLogCategory>.unmodifiable(categories);
    _recordingCategories.value = next;
    try {
      final saved = await preferences.setStringList(recordingPreferenceKey, [
        for (final category in next) category.name,
      ]);
      if (!saved) throw StateError('无法保存日志分类');
    } catch (_) {
      _drainPolicy();
      _policy.clear();
      if (identical(_recordingCategories.value, next)) {
        _recordingCategories.value = previous;
      }
      rethrow;
    }
  }

  static Future<void> logEnvironment() async {
    final environment = <String, Object?>{
      'platform': Platform.operatingSystem,
      'os': Platform.operatingSystemVersion,
      'mode': kReleaseMode ? 'release' : (kProfileMode ? 'profile' : 'debug'),
      'timezone': DateTime.now().timeZoneName,
      'utcOffsetMinutes': DateTime.now().timeZoneOffset.inMinutes,
    };
    try {
      final info = await PackageInfo.fromPlatform().timeout(
        const Duration(seconds: 2),
      );
      environment.addAll({
        'app': info.appName,
        'package': info.packageName,
        'version': info.version,
        'build': info.buildNumber,
      });
    } catch (error) {
      environment['packageInfoError'] = error.toString();
    }
    _environment = jsonEncode(environment);
    await write(
      'app-session',
      'start session=$sessionId environment=$_environment',
    );
    await logAndroidDiagnostics('startup');
  }

  static Future<void> logAndroidDiagnostics(String reason) async {
    if (!Platform.isAndroid || !isRecording(AppLogCategory.application)) return;
    try {
      final data = await const MethodChannel('cy_shine_music/app_task')
          .invokeMapMethod<String, dynamic>('diagnostics')
          .timeout(const Duration(seconds: 2));
      _androidDiagnostics = jsonEncode(data);
      await write(
        'android-runtime',
        'reason=$reason data=$_androidDiagnostics',
      );
    } catch (error) {
      await write('android-runtime', 'reason=$reason unavailable=$error');
    }
  }

  static String exportText(List<String> lines) =>
      '${DateTime.now().toIso8601String()} [log-export] session=$sessionId '
      'pid=$pid environment=$_environment '
      'recording=${_recordingCategories.value.map((item) => item.name).join(',')} '
      'lastAndroidSnapshot=$_androidDiagnostics\n${lines.join('\n')}';

  static Future<void> _ensureInit() => _initFuture ??= _initialize();

  static Future<void> _initialize() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(docs.path, 'logs'));
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final file = File(p.join(dir.path, 'cyshine.log'));
      if (file.existsSync() && file.lengthSync() > _maxBytes) {
        final backup = File(p.join(dir.path, 'cyshine.prev.log'));
        if (backup.existsSync()) backup.deleteSync();
        file.renameSync(backup.path);
      }
      _file = file;
      _writtenBytes = file.existsSync() ? file.lengthSync() : 0;
    } catch (_) {
      // Persistence is best-effort; console logging still works.
    }
  }

  static Future<void> write(String scope, String message) async {
    if (!isRecordingScope(scope)) return;
    final compact = compactLogMessage(
      message,
      maxLength: scope.startsWith('groove-shift') ? 3200 : 1200,
    );
    for (final item in _policy.accept(scope, compact, DateTime.now())) {
      _append(scope, item);
    }
    // Disk writes are queued; only flush/export waits for persistence.
  }

  static void _append(String scope, String message) {
    final line = '${DateTime.now().toIso8601String()} [$scope] $message';
    developer.log(message, name: 'lx.$scope');
    if (scope == 'groove-shift-ui' ||
        (scope == 'groove-shift-trace' && message.contains('dart_'))) {
      debugPrint('[$scope] $message');
    }
    _remember(line);
    _writeChain = _writeChain
        .then((_) async {
          await _ensureInit();
          final file = _file;
          if (file == null) return;
          if (_writtenBytes >= _maxBytes && await file.exists()) {
            final backup = File(p.join(file.parent.path, 'cyshine.prev.log'));
            if (await backup.exists()) await backup.delete();
            await file.rename(backup.path);
            _writtenBytes = 0;
          }
          final bytes = utf8.encode('$line\n');
          await file.writeAsBytes(bytes, mode: FileMode.append);
          _writtenBytes += bytes.length;
        })
        .catchError((Object _) {});
  }

  /// A snapshot of both retained files, not just the visible console tail.
  static Future<String> exportFile() async {
    await flush();
    final pending = _writeChain.then((_) async {
      final chunks = <String>[];
      final file = _file;
      if (file != null) {
        final previous = File(p.join(file.parent.path, 'cyshine.prev.log'));
        if (await previous.exists()) chunks.add(await previous.readAsString());
        if (await file.exists()) chunks.add(await file.readAsString());
      }
      if (chunks.isEmpty) chunks.add(_recent.join('\n'));
      final temp = await getTemporaryDirectory();
      final snapshot = File(p.join(temp.path, 'cyshine-log-export.txt'));
      await snapshot.writeAsString(exportText(chunks), flush: true);
      return snapshot;
    });
    _writeChain = pending.then<void>((_) {}).catchError((Object _) {});
    final snapshot = await pending;
    if (!Platform.isAndroid) return snapshot.path;
    final result = await const MethodChannel(
      'cy_shine_music/app_task',
    ).invokeMapMethod<String, dynamic>('exportLog', {'path': snapshot.path});
    final path = result?['path'] as String?;
    if (path == null) throw StateError('日志导出未返回保存位置');
    return path;
  }

  static Stream<String> get liveLines => _live.stream;

  static List<String> get recentMemoryLines => List.unmodifiable(_recent);

  static Future<List<String>> readRecentLines({int limit = 400}) async {
    await _ensureInit();
    try {
      final file = _file;
      if (file == null || !file.existsSync()) {
        return _tail(_recent, limit);
      }
      await flush();
      final lines = await file.readAsLines();
      return _tail(lines, limit);
    } catch (_) {
      return _tail(_recent, limit);
    }
  }

  static Future<void> clear() async {
    await flush();
    await _ensureInit();
    final previousWrites = _writeChain;
    _writeChain = previousWrites
        .then((_) async {
          final file = _file;
          if (file != null) {
            await file.writeAsString('');
            final backup = File(p.join(file.parent.path, 'cyshine.prev.log'));
            if (await backup.exists()) await backup.delete();
          }
          _writtenBytes = 0;
        })
        .catchError((Object _) {});
    _policy.clear();
    _recent.clear();
    await _writeChain;
  }

  static Future<File?> currentLogFile() async {
    await _ensureInit();
    return _file;
  }

  static Future<void> flush() async {
    await _ensureInit();
    _drainPolicy();
    await _writeChain;
  }

  static void _drainPolicy() {
    for (final entry in _policy.drain().entries) {
      if (isRecordingScope(entry.key)) _append(entry.key, entry.value);
    }
  }

  static void _remember(String line) {
    _recent.add(line);
    if (_recent.length > _maxRecentLines) {
      _recent.removeRange(0, _recent.length - _maxRecentLines);
    }
    if (!_live.isClosed) _live.add(line);
  }

  static List<String> _tail(List<String> lines, int limit) {
    if (lines.length <= limit) return List<String>.of(lines);
    return lines.sublist(lines.length - limit);
  }
}
