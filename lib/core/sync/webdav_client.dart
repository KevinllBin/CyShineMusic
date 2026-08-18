import 'dart:convert';

import 'package:dio/dio.dart';

import '../api/dio_factory.dart';
import 'sync_models.dart';
import 'webdav_config_store.dart';

class WebDavException implements Exception {
  const WebDavException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class WebDavRemoteSnapshot {
  const WebDavRemoteSnapshot({required this.snapshot, this.etag});

  final WebDavSyncSnapshot snapshot;
  final String? etag;
}

class WebDavClient {
  WebDavClient(this.config, {Dio? dio}) : _dio = dio ?? _createDio();

  final WebDavSyncConfig config;
  final Dio _dio;

  Uri get directoryUri => Uri.parse('${config.baseUrl}/CyShineMusic');
  Uri get snapshotUri => Uri.parse('${directoryUri.toString()}/sync-v1.json');

  static Dio _createDio() => createDio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      responseType: ResponseType.plain,
      validateStatus: (status) => status != null && status < 600,
    ),
  );

  Future<WebDavRemoteSnapshot?> connectAndRead() async {
    await ensureDirectory();
    return read();
  }

  Future<void> ensureDirectory() async {
    final response = await _request(
      directoryUri.toString(),
      options: Options(method: 'MKCOL'),
    );
    final status = response.statusCode ?? 0;
    if (status == 200 || status == 201 || status == 204 || status == 405) {
      return;
    }
    throw _statusException(status);
  }

  Future<WebDavRemoteSnapshot?> read() async {
    final response = await _request(
      snapshotUri.toString(),
      options: Options(method: 'GET', responseType: ResponseType.plain),
    );
    final status = response.statusCode ?? 0;
    if (status == 404) return null;
    if (status < 200 || status >= 300) throw _statusException(status);
    final body = response.data?.toString() ?? '';
    return WebDavRemoteSnapshot(
      snapshot: WebDavSyncSnapshot.decode(body),
      etag: response.headers.value('etag'),
    );
  }

  Future<String?> write(
    WebDavSyncSnapshot snapshot, {
    String? etag,
    bool createOnly = false,
  }) async {
    final headers = <String, Object>{'Content-Type': 'application/json'};
    if (etag != null && etag.isNotEmpty) headers['If-Match'] = etag;
    if (createOnly) headers['If-None-Match'] = '*';
    final response = await _request(
      snapshotUri.toString(),
      data: snapshot.encode(),
      options: Options(method: 'PUT', headers: headers),
    );
    final status = response.statusCode ?? 0;
    if (status < 200 || status >= 300) throw _statusException(status);
    return response.headers.value('etag');
  }

  Future<Response<dynamic>> _request(
    String url, {
    Object? data,
    required Options options,
  }) async {
    final headers = <String, Object>{...?options.headers};
    if (config.username.isNotEmpty || config.password.isNotEmpty) {
      final credentials = base64Encode(
        utf8.encode('${config.username}:${config.password}'),
      );
      headers['Authorization'] = 'Basic $credentials';
    }
    try {
      return await _dio.request<dynamic>(
        url,
        data: data,
        options: options.copyWith(headers: headers),
      );
    } on DioException catch (error) {
      if (error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.sendTimeout ||
          error.type == DioExceptionType.receiveTimeout) {
        throw const WebDavException('连接 WebDAV 超时');
      }
      throw WebDavException('无法连接 WebDAV：${error.message ?? '网络错误'}');
    }
  }

  WebDavException _statusException(int status) {
    return switch (status) {
      401 || 403 => WebDavException('WebDAV 用户名、密码或权限不正确', statusCode: status),
      409 => WebDavException('WebDAV 目录无法创建，请检查地址', statusCode: status),
      412 => WebDavException('云端数据已被其他设备更新', statusCode: status),
      _ => WebDavException('WebDAV 请求失败（HTTP $status）', statusCode: status),
    };
  }

  void close() => _dio.close();
}
