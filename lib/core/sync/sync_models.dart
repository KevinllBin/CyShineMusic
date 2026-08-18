import 'dart:convert';

import 'package:crypto/crypto.dart';

const int kWebDavSyncSchemaVersion = 1;

class SyncFormatException implements Exception {
  const SyncFormatException(this.message);

  final String message;

  @override
  String toString() => message;
}

class WebDavSyncSection {
  const WebDavSyncSection({required this.modifiedAt, required this.data});

  final DateTime modifiedAt;
  final Object data;

  Map<String, dynamic> toJson() => {
    'modifiedAt': modifiedAt.toUtc().toIso8601String(),
    'data': data,
  };

  factory WebDavSyncSection.fromJson(Object? value, String name) {
    final json = _stringMap(value);
    if (json == null) {
      throw SyncFormatException('同步文件中的 $name 数据无效');
    }
    final modifiedAt = DateTime.tryParse(json['modifiedAt']?.toString() ?? '');
    final data = json['data'];
    if (modifiedAt == null || (data is! Map && data is! List)) {
      throw SyncFormatException('同步文件中的 $name 数据不完整');
    }
    return WebDavSyncSection(modifiedAt: modifiedAt.toUtc(), data: data);
  }

  WebDavSyncSection copyWith({DateTime? modifiedAt, Object? data}) {
    return WebDavSyncSection(
      modifiedAt: modifiedAt ?? this.modifiedAt,
      data: data ?? this.data,
    );
  }
}

class WebDavSyncSnapshot {
  const WebDavSyncSnapshot({
    required this.generatedAt,
    required this.playlists,
    required this.appearance,
    required this.musicSources,
  });

  final DateTime generatedAt;
  final WebDavSyncSection playlists;
  final WebDavSyncSection appearance;
  final WebDavSyncSection musicSources;

  Map<String, dynamic> toJson() => {
    'schemaVersion': kWebDavSyncSchemaVersion,
    'generatedAt': generatedAt.toUtc().toIso8601String(),
    'sections': {
      'playlists': playlists.toJson(),
      'appearance': appearance.toJson(),
      'musicSources': musicSources.toJson(),
    },
  };

  String encode() => jsonEncode(toJson());

  factory WebDavSyncSnapshot.decode(String source) {
    Object? decoded;
    try {
      decoded = jsonDecode(source);
    } catch (_) {
      throw const SyncFormatException('WebDAV 同步文件不是有效的 JSON');
    }
    final json = _stringMap(decoded);
    if (json == null) throw const SyncFormatException('WebDAV 同步文件格式无效');
    if (json['schemaVersion'] != kWebDavSyncSchemaVersion) {
      throw const SyncFormatException('WebDAV 同步文件版本不受支持');
    }
    final generatedAt = DateTime.tryParse(
      json['generatedAt']?.toString() ?? '',
    );
    final sections = _stringMap(json['sections']);
    if (generatedAt == null || sections == null) {
      throw const SyncFormatException('WebDAV 同步文件缺少必要信息');
    }
    return WebDavSyncSnapshot(
      generatedAt: generatedAt.toUtc(),
      playlists: WebDavSyncSection.fromJson(sections['playlists'], '歌单'),
      appearance: WebDavSyncSection.fromJson(sections['appearance'], '外观'),
      musicSources: WebDavSyncSection.fromJson(sections['musicSources'], '音源'),
    );
  }

  WebDavSyncSnapshot copyWith({
    DateTime? generatedAt,
    WebDavSyncSection? playlists,
    WebDavSyncSection? appearance,
    WebDavSyncSection? musicSources,
  }) {
    return WebDavSyncSnapshot(
      generatedAt: generatedAt ?? this.generatedAt,
      playlists: playlists ?? this.playlists,
      appearance: appearance ?? this.appearance,
      musicSources: musicSources ?? this.musicSources,
    );
  }
}

String syncDataHash(Object value) {
  final canonical = _canonicalize(value);
  return sha256.convert(utf8.encode(jsonEncode(canonical))).toString();
}

WebDavSyncSection newerSyncSection(
  WebDavSyncSection local,
  WebDavSyncSection remote,
) {
  if (local.modifiedAt.isAfter(remote.modifiedAt)) return local;
  if (remote.modifiedAt.isAfter(local.modifiedAt)) return remote;
  return syncDataHash(local.data) == syncDataHash(remote.data) ? local : remote;
}

Object? _canonicalize(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((key) => key.toString()).toList()..sort();
    return <String, Object?>{
      for (final key in keys) key: _canonicalize(value[key]),
    };
  }
  if (value is List) return [for (final item in value) _canonicalize(item)];
  return value;
}

Map<String, dynamic>? syncStringMap(Object? value) => _stringMap(value);

Map<String, dynamic>? _stringMap(Object? value) {
  if (value is! Map) return null;
  try {
    return Map<String, dynamic>.from(value);
  } catch (_) {
    return null;
  }
}
