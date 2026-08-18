import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../storage/settings_store.dart';

const String _kWebDavUrlKey = 'webdav_sync_url_v1';
const String _kWebDavUsernameKey = 'webdav_sync_username_v1';
const String _kWebDavAutoSyncKey = 'webdav_auto_sync_v1';
const String _kWebDavLinkedKey = 'webdav_linked_v1';
const String _kWebDavLastSyncKey = 'webdav_last_sync_v1';
const String _kWebDavPasswordKey = 'webdav_sync_password_v1';

class WebDavSyncConfig {
  const WebDavSyncConfig({
    required this.baseUrl,
    required this.username,
    required this.password,
    this.autoSync = true,
    this.linked = false,
  });

  final String baseUrl;
  final String username;
  final String password;
  final bool autoSync;
  final bool linked;

  bool get isConfigured => baseUrl.isNotEmpty && linked;

  WebDavSyncConfig copyWith({
    String? baseUrl,
    String? username,
    String? password,
    bool? autoSync,
    bool? linked,
  }) {
    return WebDavSyncConfig(
      baseUrl: baseUrl ?? this.baseUrl,
      username: username ?? this.username,
      password: password ?? this.password,
      autoSync: autoSync ?? this.autoSync,
      linked: linked ?? this.linked,
    );
  }

  static const empty = WebDavSyncConfig(
    baseUrl: '',
    username: '',
    password: '',
  );
}

abstract class WebDavSecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class FlutterWebDavSecretStore implements WebDavSecretStore {
  const FlutterWebDavSecretStore(this._storage);

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) async {
    try {
      return await _storage.read(key: key);
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class WebDavConfigStore {
  WebDavConfigStore(this._preferences, this._secrets);

  final SharedPreferences _preferences;
  final WebDavSecretStore _secrets;

  Future<WebDavSyncConfig> load() async {
    return WebDavSyncConfig(
      baseUrl: _preferences.getString(_kWebDavUrlKey) ?? '',
      username: _preferences.getString(_kWebDavUsernameKey) ?? '',
      password: await _secrets.read(_kWebDavPasswordKey) ?? '',
      autoSync: _preferences.getBool(_kWebDavAutoSyncKey) ?? true,
      linked: _preferences.getBool(_kWebDavLinkedKey) ?? false,
    );
  }

  Future<void> save(WebDavSyncConfig config) async {
    await _preferences.setString(_kWebDavUrlKey, config.baseUrl);
    await _preferences.setString(_kWebDavUsernameKey, config.username);
    await _preferences.setBool(_kWebDavAutoSyncKey, config.autoSync);
    await _preferences.setBool(_kWebDavLinkedKey, config.linked);
    if (config.password.isEmpty) {
      await _secrets.delete(_kWebDavPasswordKey);
    } else {
      await _secrets.write(_kWebDavPasswordKey, config.password);
    }
  }

  Future<void> setAutoSync(bool value) =>
      _preferences.setBool(_kWebDavAutoSyncKey, value);

  DateTime? loadLastSyncAt() {
    return DateTime.tryParse(_preferences.getString(_kWebDavLastSyncKey) ?? '');
  }

  Future<void> setLastSyncAt(DateTime value) => _preferences.setString(
    _kWebDavLastSyncKey,
    value.toUtc().toIso8601String(),
  );

  Future<void> clear() async {
    await _preferences.remove(_kWebDavUrlKey);
    await _preferences.remove(_kWebDavUsernameKey);
    await _preferences.remove(_kWebDavAutoSyncKey);
    await _preferences.remove(_kWebDavLinkedKey);
    await _preferences.remove(_kWebDavLastSyncKey);
    await _secrets.delete(_kWebDavPasswordKey);
  }
}

final webDavSecretStoreProvider = Provider<WebDavSecretStore>((ref) {
  return const FlutterWebDavSecretStore(FlutterSecureStorage());
});

final webDavConfigStoreProvider = Provider<WebDavConfigStore>((ref) {
  return WebDavConfigStore(
    ref.watch(sharedPreferencesProvider),
    ref.watch(webDavSecretStoreProvider),
  );
});

String normalizeWebDavBaseUrl(String value) {
  var raw = value.trim();
  if (raw.isEmpty) throw const FormatException('请输入 WebDAV 地址');
  if (!raw.contains('://')) raw = 'https://$raw';
  final uri = Uri.tryParse(raw);
  if (uri == null ||
      (uri.scheme != 'http' && uri.scheme != 'https') ||
      uri.host.isEmpty) {
    throw const FormatException('请输入有效的 HTTP 或 HTTPS 地址');
  }
  final path = uri.path == '/' ? '' : uri.path.replaceFirst(RegExp(r'/+$'), '');
  return Uri(
    scheme: uri.scheme,
    userInfo: uri.userInfo,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    path: path,
  ).toString();
}
