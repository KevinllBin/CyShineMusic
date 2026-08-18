import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/playlists/playlist_store.dart';
import '../music_sources/music_source_controller.dart';
import '../storage/settings_store.dart';
import 'sync_models.dart';
import 'webdav_client.dart';
import 'webdav_config_store.dart';

const Duration _uploadDebounce = Duration(seconds: 2);

enum WebDavSyncPhase { unconfigured, idle, connecting, syncing, failure }

class WebDavSyncState {
  const WebDavSyncState({
    required this.config,
    required this.phase,
    this.lastSyncedAt,
    this.errorMessage,
  });

  final WebDavSyncConfig config;
  final WebDavSyncPhase phase;
  final DateTime? lastSyncedAt;
  final String? errorMessage;

  bool get busy =>
      phase == WebDavSyncPhase.connecting || phase == WebDavSyncPhase.syncing;

  WebDavSyncState copyWith({
    WebDavSyncConfig? config,
    WebDavSyncPhase? phase,
    DateTime? lastSyncedAt,
    String? errorMessage,
    bool clearError = false,
  }) {
    return WebDavSyncState(
      config: config ?? this.config,
      phase: phase ?? this.phase,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

class WebDavLinkPreview {
  const WebDavLinkPreview({
    required this.generatedAt,
    required this.playlistCount,
    required this.musicSourceCount,
  });

  final DateTime generatedAt;
  final int playlistCount;
  final int musicSourceCount;
}

typedef WebDavClientFactory = WebDavClient Function(WebDavSyncConfig config);

final webDavClientFactoryProvider = Provider<WebDavClientFactory>((ref) {
  return (config) => WebDavClient(config);
});

class WebDavSyncController extends AsyncNotifier<WebDavSyncState> {
  late SharedPreferences _preferences;
  late WebDavConfigStore _configStore;
  Timer? _uploadTimer;
  bool _readyForChanges = false;
  bool _applyingRemote = false;
  bool _syncing = false;
  bool _syncAgain = false;
  WebDavSyncConfig? _pendingConfig;
  WebDavRemoteSnapshot? _pendingRemote;

  @override
  Future<WebDavSyncState> build() async {
    _preferences = ref.read(sharedPreferencesProvider);
    _configStore = ref.read(webDavConfigStoreProvider);
    ref.onDispose(() => _uploadTimer?.cancel());
    ref.listen<List<dynamic>>(localPlaylistsProvider, (_, _) {
      unawaited(_recordLocalChange(_SyncSectionName.playlists));
    });
    ref.listen<AppSettings>(settingsProvider, (_, _) {
      unawaited(_recordLocalChange(_SyncSectionName.appearance));
    });
    ref.listen(musicSourceControllerProvider, (_, next) {
      if (next.hasValue) {
        unawaited(_recordLocalChange(_SyncSectionName.musicSources));
      }
    });

    final config = await _configStore.load();
    final initial = WebDavSyncState(
      config: config,
      phase: config.isConfigured
          ? WebDavSyncPhase.idle
          : WebDavSyncPhase.unconfigured,
      lastSyncedAt: _configStore.loadLastSyncAt(),
    );
    Timer.run(() => unawaited(_initialize()));
    return initial;
  }

  Future<void> _initialize() async {
    try {
      await ref.read(musicSourceControllerProvider.future);
      final snapshot = await _captureLocalSnapshot();
      await _initializeRevision(_SyncSectionName.playlists, snapshot.playlists);
      await _initializeRevision(
        _SyncSectionName.appearance,
        snapshot.appearance,
      );
      await _initializeRevision(
        _SyncSectionName.musicSources,
        snapshot.musicSources,
      );
      _readyForChanges = true;
      final current = state.valueOrNull;
      if (current?.config.isConfigured == true && current!.config.autoSync) {
        await _syncSilently();
      }
    } catch (error) {
      _setFailure(error);
    }
  }

  Future<WebDavLinkPreview?> connect({
    required String baseUrl,
    required String username,
    required String password,
    required bool autoSync,
  }) async {
    final normalizedUrl = normalizeWebDavBaseUrl(baseUrl);
    final config = WebDavSyncConfig(
      baseUrl: normalizedUrl,
      username: username.trim(),
      password: password,
      autoSync: autoSync,
    );
    _setPhase(WebDavSyncPhase.connecting);
    final client = ref.read(webDavClientFactoryProvider)(config);
    try {
      final remote = await client.connectAndRead();
      if (remote == null) {
        final now = DateTime.now().toUtc();
        await _resetAllRevisionTimes(now);
        final local = await _captureLocalSnapshot(generatedAt: now);
        await client.write(local, createOnly: true);
        await _finishLink(config.copyWith(linked: true), now);
        return null;
      }
      _pendingConfig = config;
      _pendingRemote = remote;
      _setPhase(WebDavSyncPhase.idle);
      return WebDavLinkPreview(
        generatedAt: remote.snapshot.generatedAt,
        playlistCount: _playlistCount(remote.snapshot.playlists.data),
        musicSourceCount: _musicSourceCount(remote.snapshot.musicSources.data),
      );
    } catch (error) {
      _setFailure(error);
      rethrow;
    } finally {
      client.close();
    }
  }

  Future<void> completeInitialLink({required bool useRemote}) async {
    final config = _pendingConfig;
    final remote = _pendingRemote;
    if (config == null || remote == null) {
      throw const WebDavException('没有等待确认的云端数据');
    }
    _setPhase(WebDavSyncPhase.syncing);
    final client = ref.read(webDavClientFactoryProvider)(config);
    try {
      final now = DateTime.now().toUtc();
      if (useRemote) {
        final latest = await client.connectAndRead();
        if (latest == null) {
          throw const WebDavException('云端同步文件已不存在，请重新连接');
        }
        await _applyRemoteSnapshot(latest.snapshot);
        await _saveSnapshotRevisions(latest.snapshot);
      } else {
        await _resetAllRevisionTimes(now);
        final local = await _captureLocalSnapshot(generatedAt: now);
        await client.write(local, etag: remote.etag);
      }
      _pendingConfig = null;
      _pendingRemote = null;
      await _finishLink(config.copyWith(linked: true), now);
    } catch (error) {
      _setFailure(error);
      rethrow;
    } finally {
      client.close();
    }
  }

  Future<void> setAutoSync(bool value) async {
    final current = await future;
    final config = current.config.copyWith(autoSync: value);
    await _configStore.save(config);
    state = AsyncData(current.copyWith(config: config));
    if (value && config.isConfigured) unawaited(_syncSilently());
  }

  Future<void> unlink() async {
    _uploadTimer?.cancel();
    _pendingConfig = null;
    _pendingRemote = null;
    await _configStore.clear();
    state = const AsyncData(
      WebDavSyncState(
        config: WebDavSyncConfig.empty,
        phase: WebDavSyncPhase.unconfigured,
      ),
    );
  }

  Future<void> onAppResumed() async {
    final current = state.valueOrNull;
    if (current?.config.isConfigured == true && current!.config.autoSync) {
      await _syncSilently();
    }
  }

  Future<void> syncNow() async {
    final current = state.valueOrNull ?? await future;
    if (!current.config.isConfigured) return;
    if (_syncing) {
      _syncAgain = true;
      return;
    }
    _syncing = true;
    _uploadTimer?.cancel();
    _setPhase(WebDavSyncPhase.syncing);
    final client = ref.read(webDavClientFactoryProvider)(current.config);
    try {
      await _syncOnce(client, retryOnConflict: true);
      await _recordSuccess();
    } catch (error) {
      _setFailure(error);
      rethrow;
    } finally {
      client.close();
      _syncing = false;
      if (_syncAgain) {
        _syncAgain = false;
        unawaited(_syncSilently());
      }
    }
  }

  Future<void> _syncOnce(
    WebDavClient client, {
    required bool retryOnConflict,
  }) async {
    final remote = await client.connectAndRead();
    final local = await _captureLocalSnapshot();
    if (remote == null) {
      await client.write(local, createOnly: true);
      await _saveSnapshotRevisions(local);
      return;
    }

    final merged = WebDavSyncSnapshot(
      generatedAt: DateTime.now().toUtc(),
      playlists: newerSyncSection(local.playlists, remote.snapshot.playlists),
      appearance: newerSyncSection(
        local.appearance,
        remote.snapshot.appearance,
      ),
      musicSources: newerSyncSection(
        local.musicSources,
        remote.snapshot.musicSources,
      ),
    );
    await _applyRemoteSections(local, merged);
    await _saveSnapshotRevisions(merged);

    if (_sameSnapshotData(merged, remote.snapshot)) return;
    try {
      await client.write(merged, etag: remote.etag);
    } on WebDavException catch (error) {
      if (error.statusCode == 412 && retryOnConflict) {
        await _syncOnce(client, retryOnConflict: false);
        return;
      }
      rethrow;
    }
  }

  Future<WebDavSyncSnapshot> _captureLocalSnapshot({
    DateTime? generatedAt,
  }) async {
    final playlistData = ref
        .read(localPlaylistsProvider.notifier)
        .exportForSync();
    final appearanceData = ref
        .read(settingsProvider.notifier)
        .exportAppearanceForSync();
    final sourceData = await ref
        .read(musicSourceControllerProvider.notifier)
        .exportForSync();
    return WebDavSyncSnapshot(
      generatedAt: generatedAt ?? DateTime.now().toUtc(),
      playlists: WebDavSyncSection(
        modifiedAt: _revision(_SyncSectionName.playlists).modifiedAt,
        data: playlistData,
      ),
      appearance: WebDavSyncSection(
        modifiedAt: _revision(_SyncSectionName.appearance).modifiedAt,
        data: appearanceData,
      ),
      musicSources: WebDavSyncSection(
        modifiedAt: _revision(_SyncSectionName.musicSources).modifiedAt,
        data: sourceData,
      ),
    );
  }

  Future<void> _applyRemoteSections(
    WebDavSyncSnapshot local,
    WebDavSyncSnapshot merged,
  ) async {
    _applyingRemote = true;
    try {
      if (syncDataHash(local.playlists.data) !=
          syncDataHash(merged.playlists.data)) {
        await ref
            .read(localPlaylistsProvider.notifier)
            .applyFromSync(merged.playlists.data);
      }
      if (syncDataHash(local.appearance.data) !=
          syncDataHash(merged.appearance.data)) {
        await ref
            .read(settingsProvider.notifier)
            .applyAppearanceFromSync(merged.appearance.data);
      }
      if (syncDataHash(local.musicSources.data) !=
          syncDataHash(merged.musicSources.data)) {
        await ref
            .read(musicSourceControllerProvider.notifier)
            .applyFromSync(merged.musicSources.data);
      }
    } finally {
      _applyingRemote = false;
    }
  }

  Future<void> _applyRemoteSnapshot(WebDavSyncSnapshot remote) async {
    final local = await _captureLocalSnapshot();
    await _applyRemoteSections(local, remote);
  }

  Future<void> _recordLocalChange(_SyncSectionName name) async {
    if (!_readyForChanges || _applyingRemote) return;
    final data = await _sectionData(name);
    final hash = syncDataHash(data);
    final currentHash = _preferences.getString(_hashKey(name));
    if (hash == currentHash) return;
    await _saveRevision(name, DateTime.now().toUtc(), hash);
    final current = state.valueOrNull;
    if (current?.config.isConfigured != true || !current!.config.autoSync) {
      return;
    }
    _uploadTimer?.cancel();
    _uploadTimer = Timer(_uploadDebounce, () => unawaited(_syncSilently()));
  }

  Future<Object> _sectionData(_SyncSectionName name) async {
    return switch (name) {
      _SyncSectionName.playlists =>
        ref.read(localPlaylistsProvider.notifier).exportForSync(),
      _SyncSectionName.appearance =>
        ref.read(settingsProvider.notifier).exportAppearanceForSync(),
      _SyncSectionName.musicSources =>
        await ref.read(musicSourceControllerProvider.notifier).exportForSync(),
    };
  }

  Future<void> _initializeRevision(
    _SyncSectionName name,
    WebDavSyncSection section,
  ) async {
    final hash = syncDataHash(section.data);
    final storedHash = _preferences.getString(_hashKey(name));
    final storedTime = DateTime.tryParse(
      _preferences.getString(_timeKey(name)) ?? '',
    );
    if (storedHash == hash && storedTime != null) return;
    await _saveRevision(name, DateTime.now().toUtc(), hash);
  }

  _SectionRevision _revision(_SyncSectionName name) {
    final modifiedAt = DateTime.tryParse(
      _preferences.getString(_timeKey(name)) ?? '',
    );
    return _SectionRevision(modifiedAt: (modifiedAt ?? DateTime.now()).toUtc());
  }

  Future<void> _saveSnapshotRevisions(WebDavSyncSnapshot snapshot) async {
    await _saveRevision(
      _SyncSectionName.playlists,
      snapshot.playlists.modifiedAt,
      syncDataHash(snapshot.playlists.data),
    );
    await _saveRevision(
      _SyncSectionName.appearance,
      snapshot.appearance.modifiedAt,
      syncDataHash(snapshot.appearance.data),
    );
    await _saveRevision(
      _SyncSectionName.musicSources,
      snapshot.musicSources.modifiedAt,
      syncDataHash(snapshot.musicSources.data),
    );
  }

  Future<void> _resetAllRevisionTimes(DateTime value) async {
    final snapshot = await _captureLocalSnapshot(generatedAt: value);
    await _saveRevision(
      _SyncSectionName.playlists,
      value,
      syncDataHash(snapshot.playlists.data),
    );
    await _saveRevision(
      _SyncSectionName.appearance,
      value,
      syncDataHash(snapshot.appearance.data),
    );
    await _saveRevision(
      _SyncSectionName.musicSources,
      value,
      syncDataHash(snapshot.musicSources.data),
    );
  }

  Future<void> _saveRevision(
    _SyncSectionName name,
    DateTime modifiedAt,
    String hash,
  ) async {
    await _preferences.setString(_hashKey(name), hash);
    await _preferences.setString(
      _timeKey(name),
      modifiedAt.toUtc().toIso8601String(),
    );
  }

  Future<void> _finishLink(WebDavSyncConfig config, DateTime now) async {
    await _configStore.save(config);
    await _configStore.setLastSyncAt(now);
    state = AsyncData(
      WebDavSyncState(
        config: config,
        phase: WebDavSyncPhase.idle,
        lastSyncedAt: now,
      ),
    );
  }

  Future<void> _recordSuccess() async {
    final now = DateTime.now().toUtc();
    await _configStore.setLastSyncAt(now);
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(
      current.copyWith(
        phase: WebDavSyncPhase.idle,
        lastSyncedAt: now,
        clearError: true,
      ),
    );
  }

  void _setPhase(WebDavSyncPhase phase) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(current.copyWith(phase: phase, clearError: true));
  }

  void _setFailure(Object error) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(
      current.copyWith(
        phase: WebDavSyncPhase.failure,
        errorMessage: error.toString(),
      ),
    );
  }

  Future<void> _syncSilently() async {
    try {
      await syncNow();
    } catch (_) {
      // Automatic sync exposes the failure through state and retries later.
    }
  }
}

final webDavSyncControllerProvider =
    AsyncNotifierProvider<WebDavSyncController, WebDavSyncState>(
      WebDavSyncController.new,
    );

enum _SyncSectionName { playlists, appearance, musicSources }

class _SectionRevision {
  const _SectionRevision({required this.modifiedAt});

  final DateTime modifiedAt;
}

String _hashKey(_SyncSectionName name) => 'webdav_${name.name}_hash_v1';
String _timeKey(_SyncSectionName name) => 'webdav_${name.name}_modified_v1';

bool _sameSnapshotData(WebDavSyncSnapshot left, WebDavSyncSnapshot right) {
  return syncDataHash(left.playlists.data) ==
          syncDataHash(right.playlists.data) &&
      syncDataHash(left.appearance.data) ==
          syncDataHash(right.appearance.data) &&
      syncDataHash(left.musicSources.data) ==
          syncDataHash(right.musicSources.data);
}

int _playlistCount(Object data) => data is List ? data.length : 0;

int _musicSourceCount(Object data) {
  final json = syncStringMap(data);
  final records = json?['records'];
  return records is List ? records.length : 0;
}
