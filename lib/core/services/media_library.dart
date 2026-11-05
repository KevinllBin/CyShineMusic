import 'dart:io';

import 'package:flutter/services.dart';

class MediaLibrary {
  static const _channel = MethodChannel('cy_shine_music/media_library');
  static Future<int>? _sdk;

  static Future<int> get sdk => _sdk ??= Platform.isAndroid
      ? _channel.invokeMethod<int>('sdk').then((value) => value ?? 0)
      : Future.value(0);

  static Future<({List<Map<String, dynamic>> files, List<String> unavailable})>
  query(List<String> directories) async {
    final result = await _channel.invokeMapMethod<String, dynamic>('query', {
      'directories': directories,
    });
    if (result == null) throw StateError('系统音乐库未返回结果');
    return (
      files: [
        for (final row in result['files'] as List? ?? [])
          Map<String, dynamic>.from(row as Map),
      ],
      unavailable: (result['unavailable'] as List? ?? [])
          .whereType<String>()
          .toList(),
    );
  }

  static Future<List<String>> folders() async =>
      await _channel.invokeListMethod<String>('folders') ?? const [];

  static Future<Map<String, dynamic>?> find(String path) async {
    if (!Platform.isAndroid) return null;
    return _channel.invokeMapMethod<String, dynamic>('find', {'path': path});
  }

  static Future<Uint8List?> artwork(String uri) =>
      _channel.invokeMethod<Uint8List>('artwork', {'uri': uri});

  static Future<bool> canSave(String directory) async {
    if (!Platform.isAndroid) return false;
    return await _channel.invokeMethod<bool>('canSave', {
          'directory': directory,
        }) ??
        false;
  }

  static Future<String> save(
    String directory,
    String source,
    String name,
  ) async => (await _channel.invokeMethod<String>('save', {
    'directory': directory,
    'source': source,
    'name': name,
  }))!;
}
