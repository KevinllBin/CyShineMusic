import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cy_shine_music/core/sync/sync_models.dart';
import 'package:cy_shine_music/core/sync/webdav_client.dart';
import 'package:cy_shine_music/core/sync/webdav_config_store.dart';

void main() {
  test('normalizes WebDAV directory URLs', () {
    expect(
      normalizeWebDavBaseUrl('dav.example.com/root/'),
      'https://dav.example.com/root',
    );
    expect(
      normalizeWebDavBaseUrl('http://192.168.1.2:8080/dav/?token=hidden'),
      'http://192.168.1.2:8080/dav',
    );
    expect(
      () => normalizeWebDavBaseUrl('ftp://example.com'),
      throwsFormatException,
    );
  });

  test(
    'creates the app directory and conditionally creates a snapshot',
    () async {
      final requests = <RequestOptions>[];
      final dio = _dioWith((options) {
        requests.add(options);
        return switch (options.method) {
          'MKCOL' => ResponseBody.fromString('', 405),
          'GET' => ResponseBody.fromString('', 404),
          'PUT' => ResponseBody.fromString(
            '',
            201,
            headers: {
              'etag': ['"v1"'],
            },
          ),
          _ => ResponseBody.fromString('', 500),
        };
      });
      final client = WebDavClient(
        const WebDavSyncConfig(
          baseUrl: 'https://dav.example.com/root',
          username: 'user',
          password: 'pass',
        ),
        dio: dio,
      );
      addTearDown(client.close);

      expect(await client.connectAndRead(), isNull);
      expect(await client.write(_snapshot(), createOnly: true), '"v1"');

      expect(requests.map((request) => request.method), [
        'MKCOL',
        'GET',
        'PUT',
      ]);
      expect(requests.last.headers['If-None-Match'], '*');
      expect(
        requests.every(
          (request) =>
              request.headers['Authorization'] ==
              'Basic ${base64Encode(utf8.encode('user:pass'))}',
        ),
        isTrue,
      );
      expect(requests.last.uri.path, '/root/CyShineMusic/sync-v1.json');
    },
  );

  test('reads ETag and uses it for guarded writes', () async {
    final snapshot = _snapshot();
    final requests = <RequestOptions>[];
    final dio = _dioWith((options) {
      requests.add(options);
      if (options.method == 'GET') {
        return ResponseBody.fromString(
          snapshot.encode(),
          200,
          headers: {
            'etag': ['"cloud-1"'],
          },
        );
      }
      return ResponseBody.fromString('', options.method == 'MKCOL' ? 201 : 204);
    });
    final client = WebDavClient(
      const WebDavSyncConfig(
        baseUrl: 'https://dav.example.com',
        username: '',
        password: '',
      ),
      dio: dio,
    );
    addTearDown(client.close);

    final remote = await client.connectAndRead();
    expect(remote?.etag, '"cloud-1"');
    await client.write(snapshot, etag: remote?.etag);
    expect(requests.last.headers['If-Match'], '"cloud-1"');
  });

  test('surfaces precondition failures as sync conflicts', () async {
    final dio = _dioWith((options) => ResponseBody.fromString('', 412));
    final client = WebDavClient(
      const WebDavSyncConfig(
        baseUrl: 'https://dav.example.com',
        username: '',
        password: '',
      ),
      dio: dio,
    );
    addTearDown(client.close);

    await expectLater(
      client.write(_snapshot(), etag: '"old"'),
      throwsA(
        isA<WebDavException>().having(
          (error) => error.statusCode,
          'statusCode',
          412,
        ),
      ),
    );
  });
}

Dio _dioWith(ResponseBody Function(RequestOptions options) handler) {
  final dio = Dio(
    BaseOptions(
      responseType: ResponseType.plain,
      validateStatus: (status) => status != null && status < 500,
    ),
  );
  dio.httpClientAdapter = _FakeAdapter(handler);
  return dio;
}

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.handler);

  final ResponseBody Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

WebDavSyncSnapshot _snapshot() {
  final now = DateTime.utc(2026, 8, 17, 8);
  return WebDavSyncSnapshot(
    generatedAt: now,
    playlists: WebDavSyncSection(modifiedAt: now, data: const <Object>[]),
    appearance: WebDavSyncSection(
      modifiedAt: now,
      data: const {
        'themeMode': 'system',
        'themeSeedArgb': 0xFF6750A4,
        'useDynamicColor': false,
      },
    ),
    musicSources: WebDavSyncSection(
      modifiedAt: now,
      data: const {
        'records': <Object>[],
        'enabledIds': <Object>[],
        'scripts': <String, Object>{},
      },
    ),
  );
}
