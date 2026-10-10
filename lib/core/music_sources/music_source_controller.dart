import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../models/download_capabilities.dart';
import '../services/app_logger.dart';
import 'music_source_metadata_parser.dart';
import 'music_source_models.dart';
import 'music_source_runtime.dart';
import 'music_source_store.dart';
import 'music_source_updates.dart';

class MusicSourceController extends AsyncNotifier<MusicSourceState> {
  MusicSourceStore get _store => ref.read(musicSourceStoreProvider);
  MusicSourceRuntime get _runtime => ref.read(musicSourceRuntimeProvider);
  bool _updating = false;
  int _pendingChanges = 0;
  Completer<void>? _updateCompleted;
  bool _checkingAllUpdates = false;

  void _checkUpdating() {
    if (_updating) {
      throw const MusicSourceRuntimeException('正在更新音源，请稍候');
    }
  }

  Future<T> _change<T>(Future<T> Function() action) async {
    final updateCompleted = _updateCompleted;
    if (updateCompleted != null) await updateCompleted.future;
    _checkUpdating();
    _pendingChanges++;
    try {
      return await action();
    } finally {
      _pendingChanges--;
    }
  }

  @override
  Future<MusicSourceState> build() async {
    // Imported scripts were validated before they were enabled. Loading them
    // lazily avoids initializing up to five QuickJS contexts during startup.
    return _store.load();
  }

  Future<void> checkAllForUpdates() async {
    if (_checkingAllUpdates) return;
    _checkingAllUpdates = true;
    try {
      final records = (await future).records;
      for (final record in records) {
        try {
          await checkForUpdate(record.id);
        } catch (_) {
          // An unreachable source must not stop checking the remaining ones.
          // Avoid logging exception text that may contain credential URLs.
          await AppLogger.write(
            'music-source-update',
            'check failed for source ${record.id}',
          );
        }
      }
    } catch (_) {
      await AppLogger.write('music-source-update', 'source list check failed');
    } finally {
      _checkingAllUpdates = false;
    }
  }

  Future<bool> checkForUpdate(String id, {bool showAgain = false}) async {
    final updateCompleted = _updateCompleted;
    if (updateCompleted != null) await updateCompleted.future;
    final current = await future;
    final record = current.records.firstWhere(
      (item) => item.id == id,
      orElse: () => throw const MusicSourceRuntimeException('音源不存在'),
    );
    final updates = ref.read(musicSourceUpdatesProvider.notifier);
    var notice = updates.latestFor(record);
    if (notice != null) {
      if (showAgain) updates.showAgain(notice);
      return true;
    }
    final script = await _store.readScript(id);
    Object? checkError;
    try {
      await ref
          .read(musicSourceUpdateRuntimeProvider)
          .checkForUpdates(record, script);
    } catch (error) {
      checkError = error;
    }
    if (!_isCurrent(record)) return false;
    notice = updates.latestFor(record);
    if (notice != null) {
      if (showAgain) updates.showAgain(notice);
      return true;
    }

    final origin = Uri.tryParse(record.origin);
    if (origin != null &&
        (origin.scheme == 'http' || origin.scheme == 'https') &&
        origin.host.isNotEmpty) {
      final remoteScript = await _downloadUpdate(record.origin);
      if (!_isCurrent(record) || remoteScript == script) return false;
      final metadata = parseMusicSourceMetadata(remoteScript);
      if (musicSourceId(metadata) != record.id) {
        throw const MusicSourceRuntimeException('原导入地址返回了不同的音源，请手动导入新版');
      }
      final versionNote = metadata.version != record.version
          ? '版本：${record.version.isEmpty ? '未标注' : record.version}'
                ' → ${metadata.version.isEmpty ? '未标注' : metadata.version}'
          : '版本号未变化，但脚本内容已发生变化。';
      notice = MusicSourceUpdateNotice(
        sourceId: record.id,
        sourceKey: record.runtimeKey,
        log: '从原导入 URL 检测到脚本更新。\n$versionNote\n\n作者未提供更新说明。',
        updateUrl: record.origin,
      );
      updates.receive(notice);
      if (showAgain) updates.showAgain(notice);
      return true;
    }
    if (checkError != null) throw checkError;
    return false;
  }

  bool _isCurrent(MusicSourceRecord record) =>
      state.valueOrNull?.records.any(
        (item) => item.id == record.id && item.runtimeKey == record.runtimeKey,
      ) ??
      false;

  Future<MusicSourceRecord> importScript({
    required String script,
    required String origin,
  }) => _change(() async {
    final current = await future;
    final metadata = parseMusicSourceMetadata(script);
    final id = musicSourceId(metadata);
    MusicSourceRecord? previous;
    for (final record in current.records) {
      if (record.id == id) previous = record;
    }
    if (previous == null && current.records.length >= kMaxMusicSourceCount) {
      throw const MusicSourceRuntimeException('最多只能保存 20 个音源');
    }
    final now = DateTime.now();
    final record = MusicSourceRecord(
      id: id,
      name: metadata.name,
      description: metadata.description,
      author: metadata.author,
      homepage: metadata.homepage,
      version: metadata.version,
      origin: origin,
      importedAt: previous?.importedAt ?? now,
      updatedAt: now,
      capabilities: previous?.capabilities ?? const {},
    );
    await _store.writeScript(id, script);
    final records = previous == null
        ? [...current.records, record]
        : _replace(current.records, record);
    final next = current.copyWith(records: List.unmodifiable(records));
    state = AsyncData(next);
    await _store.save(next);
    if (current.isEnabled(id) ||
        current.enabledIds.length < kMaxEnabledMusicSourceCount) {
      await activate(id);
    } else {
      await _validateInactive(record);
    }
    return state.requireValue.records.firstWhere((item) => item.id == id);
  });

  Future<bool> updateScript(MusicSourceUpdateNotice notice) async {
    final current = await future;
    _checkUpdating();
    if (_pendingChanges != 0 || current.activatingId != null) {
      throw const MusicSourceRuntimeException('音源正在处理，请稍后重试');
    }
    final record = current.records.firstWhere(
      (item) => item.id == notice.sourceId,
      orElse: () => throw const MusicSourceRuntimeException('音源已被删除'),
    );
    if (!notice.matches(record)) {
      throw const MusicSourceRuntimeException('音源已发生变化，请使用新的更新通知');
    }

    _updating = true;
    _updateCompleted = Completer<void>();
    state = AsyncData(current.copyWith(activatingId: record.id));
    String? previousScript;
    var replacing = false;
    try {
      final script = await _downloadUpdate(notice.updateUrl);
      final metadata = parseMusicSourceMetadata(script);
      if (musicSourceId(metadata) != record.id) {
        throw const MusicSourceRuntimeException(
          '更新脚本的名称或作者与当前音源不一致，请复制更新 URL 后手动导入',
        );
      }
      previousScript = await _store.readScript(record.id);
      if (script == previousScript) return false;
      final candidate = MusicSourceRecord(
        id: record.id,
        name: metadata.name,
        description: metadata.description,
        author: metadata.author,
        homepage: metadata.homepage,
        version: metadata.version,
        origin: record.origin,
        importedAt: record.importedAt,
        updatedAt: DateTime.now(),
        capabilities: record.capabilities,
      );
      final ready = await _validate(candidate, script);
      final next = current.copyWith(
        records: _replace(current.records, ready),
        clearActivating: true,
      );
      // Only replace a usable script after the candidate has initialized.
      // Restore both the script and index if committing the update fails.
      replacing = true;
      await _store.writeScript(record.id, script);
      await _store.save(next);
      state = AsyncData(next);
      return true;
    } catch (_) {
      try {
        await _runtime.disposeRuntime();
        if (replacing && previousScript != null) {
          await _store.writeScript(record.id, previousScript);
          await _store.save(current);
        }
      } finally {
        state = AsyncData(current);
      }
      rethrow;
    } finally {
      _updating = false;
      final latest = state.valueOrNull;
      if (latest?.activatingId == record.id) {
        state = AsyncData(latest!.copyWith(clearActivating: true));
      }
      _updateCompleted!.complete();
      _updateCompleted = null;
    }
  }

  Future<String> _downloadUpdate(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      throw const MusicSourceRuntimeException('更新 URL 无效');
    }
    final cancelToken = CancelToken();
    try {
      final response = await ref
          .read(apiClientProvider)
          .get<ResponseBody>(
            url,
            cancelToken: cancelToken,
            options: Options(
              responseType: ResponseType.stream,
              receiveTimeout: const Duration(seconds: 30),
              headers: const {
                'Accept': 'application/javascript, text/plain, */*',
              },
            ),
          );
      final body = response.data;
      if (body == null) {
        throw const MusicSourceRuntimeException('更新脚本为空');
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in body.stream) {
        if (bytes.length + chunk.length > kMaxMusicSourceScriptBytes) {
          throw const MusicSourceRuntimeException('音源脚本不能超过 2 MB');
        }
        bytes.add(chunk);
      }
      return utf8.decode(bytes.takeBytes());
    } on DioException catch (error) {
      // Dio's exception text can contain the paid source's credential URL.
      final status = error.response?.statusCode;
      throw MusicSourceRuntimeException(
        status == null ? '下载更新失败，请检查网络后重试' : '下载更新失败（HTTP $status）',
      );
    } finally {
      cancelToken.cancel();
    }
  }

  Future<Map<String, dynamic>> exportForSync() => _change(() async {
    final current = await future;
    final scripts = <String, String>{};
    final records = <Map<String, dynamic>>[];
    for (final record in current.records) {
      scripts[record.id] = await _store.readScript(record.id);
      final json = record.toJson()..remove('lastError');
      json['origin'] = _portableOrigin(record.origin);
      records.add(json);
    }
    return {
      'records': records,
      'enabledIds': current.enabledIds,
      'scripts': scripts,
    };
  });

  Future<void> applyFromSync(Object value) => _change(() async {
    if (value is! Map) {
      throw const MusicSourceRuntimeException('云端音源格式无效');
    }
    final json = Map<String, dynamic>.from(value);
    final rawRecords = json['records'];
    final rawEnabledIds = json['enabledIds'];
    final rawScripts = json['scripts'];
    if (rawRecords is! List || rawEnabledIds is! List || rawScripts is! Map) {
      throw const MusicSourceRuntimeException('云端音源数据不完整');
    }
    if (rawRecords.length > kMaxMusicSourceCount) {
      throw const MusicSourceRuntimeException('云端音源数量超过 20 个');
    }

    final scripts = <String, String>{};
    for (final entry in rawScripts.entries) {
      if (entry.key is String && entry.value is String) {
        scripts[entry.key as String] = entry.value as String;
      }
    }
    final parsedRecords = <MusicSourceRecord>[];
    final ids = <String>{};
    try {
      for (final rawRecord in rawRecords) {
        if (rawRecord is! Map) throw const FormatException();
        final record = MusicSourceRecord.fromJson(
          Map<String, dynamic>.from(rawRecord),
        );
        final script = scripts[record.id];
        if (record.id.isEmpty || script == null || !ids.add(record.id)) {
          throw const FormatException();
        }
        final metadata = parseMusicSourceMetadata(script);
        if (musicSourceId(metadata) != record.id) throw const FormatException();
        parsedRecords.add(record);
      }
    } catch (error) {
      throw const MusicSourceRuntimeException('云端音源脚本或索引无效');
    }

    final enabledIds = <String>[];
    for (final rawId in rawEnabledIds) {
      if (rawId is! String || !ids.contains(rawId)) {
        throw const MusicSourceRuntimeException('云端启用音源列表无效');
      }
      if (!enabledIds.contains(rawId)) enabledIds.add(rawId);
    }
    if (enabledIds.length > kMaxEnabledMusicSourceCount) {
      throw const MusicSourceRuntimeException('云端启用音源数量超过 5 个');
    }
    if (scripts.length != parsedRecords.length) {
      throw const MusicSourceRuntimeException('云端音源脚本数量不一致');
    }

    final records = <MusicSourceRecord>[];
    try {
      for (final record in parsedRecords) {
        records.add(await _validate(record, scripts[record.id]!));
      }
    } catch (error) {
      await _runtime.disposeRuntime();
      if (error is MusicSourceRuntimeException) rethrow;
      throw const MusicSourceRuntimeException('云端音源脚本初始化失败');
    }

    final next = MusicSourceState(
      records: List<MusicSourceRecord>.unmodifiable(records),
      enabledIds: List<String>.unmodifiable(enabledIds),
    );
    await _runtime.disposeRuntime();
    await _store.replaceAll(next, scripts);
    state = AsyncData(next);
  });

  Future<void> activate(String id) => _change(() async {
    final current = await future;
    final record = current.records.firstWhere(
      (item) => item.id == id,
      orElse: () => throw const MusicSourceRuntimeException('音源不存在'),
    );
    final alreadyEnabled = current.isEnabled(id);
    if (!alreadyEnabled &&
        current.enabledIds.length >= kMaxEnabledMusicSourceCount) {
      throw const MusicSourceRuntimeException('最多同时启用 5 个音源');
    }
    state = AsyncData(current.copyWith(activatingId: id));
    try {
      final script = await _store.readScript(id);
      final ready = await _validate(record, script);
      final next = current.copyWith(
        records: _replace(current.records, ready),
        enabledIds: alreadyEnabled
            ? current.enabledIds
            : List.unmodifiable([...current.enabledIds, id]),
        clearActivating: true,
      );
      state = AsyncData(next);
      await _store.save(next);
    } catch (error) {
      await _runtime.disposeRuntime();
      final failed = record.copyWith(lastError: error.toString());
      final next = current.copyWith(
        records: _replace(current.records, failed),
        enabledIds: List.unmodifiable(
          current.enabledIds.where((enabledId) => enabledId != id),
        ),
        clearActivating: true,
      );
      state = AsyncData(next);
      await _store.save(next);
      rethrow;
    }
  });

  Future<void> _validateInactive(MusicSourceRecord record) async {
    final current = await future;
    state = AsyncData(current.copyWith(activatingId: record.id));
    try {
      final script = await _store.readScript(record.id);
      final ready = await _validate(record, script);
      final next = current.copyWith(
        records: _replace(current.records, ready),
        clearActivating: true,
      );
      state = AsyncData(next);
      await _store.save(next);
    } catch (error) {
      final failed = record.copyWith(lastError: error.toString());
      final next = current.copyWith(
        records: _replace(current.records, failed),
        clearActivating: true,
      );
      state = AsyncData(next);
      await _store.save(next);
      rethrow;
    }
  }

  Future<MusicSourceRecord> _validate(
    MusicSourceRecord record,
    String script,
  ) async {
    final capabilities = await _runtime.load(record, script);
    if (capabilities.isEmpty) {
      throw const MusicSourceRuntimeException('音源没有声明可用的 musicUrl 能力');
    }
    return record.copyWith(capabilities: capabilities, clearLastError: true);
  }

  Future<void> deactivate(String id) => _change(() async {
    final current = await future;
    if (!current.isEnabled(id)) return;
    await _runtime.disposeRuntime();
    final next = current.copyWith(
      enabledIds: List.unmodifiable(
        current.enabledIds.where((enabledId) => enabledId != id),
      ),
      clearActivating: current.activatingId == id,
    );
    state = AsyncData(next);
    await _store.save(next);
  });

  Future<void> remove(String id) => _change(() async {
    final current = await future;
    if (current.isEnabled(id)) await _runtime.disposeRuntime();
    await _store.deleteScript(id);
    final next = current.copyWith(
      records: List.unmodifiable(
        current.records.where((record) => record.id != id),
      ),
      enabledIds: List.unmodifiable(
        current.enabledIds.where((enabledId) => enabledId != id),
      ),
      clearActivating: current.activatingId == id,
    );
    state = AsyncData(next);
    await _store.save(next);
  });

  List<MusicSourceRecord> _replace(
    List<MusicSourceRecord> records,
    MusicSourceRecord replacement,
  ) {
    return List.unmodifiable([
      for (final record in records)
        if (record.id == replacement.id) replacement else record,
    ]);
  }
}

String _portableOrigin(String origin) {
  final uri = Uri.tryParse(origin.trim());
  if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
    return uri.toString();
  }
  return 'WebDAV 同步';
}

final musicSourceControllerProvider =
    AsyncNotifierProvider<MusicSourceController, MusicSourceState>(
      MusicSourceController.new,
    );

final downloadCapabilitiesProvider = Provider<AsyncValue<DownloadCapabilities>>(
  (ref) {
    return ref
        .watch(musicSourceControllerProvider)
        .whenData((state) => state.downloadCapabilities);
  },
);
