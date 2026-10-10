import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cy_shine_music/core/models/enums.dart';
import 'package:cy_shine_music/core/api/api_client.dart';
import 'package:cy_shine_music/core/music_sources/music_source_controller.dart';
import 'package:cy_shine_music/core/music_sources/music_source_metadata_parser.dart';
import 'package:cy_shine_music/core/music_sources/music_source_models.dart';
import 'package:cy_shine_music/core/music_sources/music_source_runtime.dart';
import 'package:cy_shine_music/core/music_sources/music_source_store.dart';
import 'package:cy_shine_music/core/music_sources/music_source_updates.dart';
import 'package:cy_shine_music/core/storage/settings_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'controller enables at most five sources without changing their order',
    () async {
      final records = [
        for (var index = 1; index <= 6; index++) _record('s$index'),
      ];
      final harness = await _Harness.create(
        MusicSourceState(records: records, enabledIds: const []),
      );
      addTearDown(harness.container.dispose);
      final controller = harness.container.read(
        musicSourceControllerProvider.notifier,
      );

      for (var index = 1; index <= 5; index++) {
        await controller.activate('s$index');
      }
      expect(
        harness.container
            .read(musicSourceControllerProvider)
            .requireValue
            .enabledIds,
        ['s1', 's2', 's3', 's4', 's5'],
      );

      await expectLater(
        controller.activate('s6'),
        throwsA(
          isA<MusicSourceRuntimeException>().having(
            (error) => error.message,
            'message',
            contains('5'),
          ),
        ),
      );
      expect(
        harness.container
            .read(musicSourceControllerProvider)
            .requireValue
            .enabledIds,
        ['s1', 's2', 's3', 's4', 's5'],
      );
    },
  );

  test(
    'one source validation failure does not disable healthy sources',
    () async {
      final records = [_record('first'), _record('broken'), _record('third')];
      final harness = await _Harness.create(
        MusicSourceState(
          records: records,
          enabledIds: const ['first', 'broken', 'third'],
        ),
        failingIds: const {'broken'},
      );
      addTearDown(harness.container.dispose);
      final controller = harness.container.read(
        musicSourceControllerProvider.notifier,
      );

      await expectLater(
        controller.activate('broken'),
        throwsA(isA<MusicSourceRuntimeException>()),
      );
      final state = harness.container
          .read(musicSourceControllerProvider)
          .requireValue;

      expect(state.enabledIds, ['first', 'third']);
      expect(
        state.records.firstWhere((record) => record.id == 'broken').lastError,
        contains('初始化失败'),
      );
    },
  );

  test('deactivating a middle source preserves fallback priority', () async {
    final records = [_record('first'), _record('second'), _record('third')];
    final harness = await _Harness.create(
      MusicSourceState(
        records: records,
        enabledIds: const ['first', 'second', 'third'],
      ),
    );
    addTearDown(harness.container.dispose);
    final controller = harness.container.read(
      musicSourceControllerProvider.notifier,
    );

    await controller.deactivate('second');

    expect(
      harness.container
          .read(musicSourceControllerProvider)
          .requireValue
          .enabledIds,
      ['first', 'third'],
    );
  });

  test(
    'WebDAV restore validates scripts and preserves enabled order',
    () async {
      const firstScript = '// @name Cloud One\n// @author sync\n';
      const secondScript = '// @name Cloud Two\n// @author sync\n';
      final firstId = musicSourceId(parseMusicSourceMetadata(firstScript));
      final secondId = musicSourceId(parseMusicSourceMetadata(secondScript));
      final first = _record(firstId, name: 'Cloud One', author: 'sync');
      final second = _record(secondId, name: 'Cloud Two', author: 'sync');
      final harness = await _Harness.create(MusicSourceState.empty);
      addTearDown(harness.container.dispose);
      final controller = harness.container.read(
        musicSourceControllerProvider.notifier,
      );

      await controller.applyFromSync({
        'records': [first.toJson(), second.toJson()],
        'enabledIds': [secondId, firstId],
        'scripts': {firstId: firstScript, secondId: secondScript},
      });

      final restored = harness.container
          .read(musicSourceControllerProvider)
          .requireValue;
      expect(restored.records.map((record) => record.id), [firstId, secondId]);
      expect(restored.enabledIds, [secondId, firstId]);
      final exported = await controller.exportForSync();
      expect(exported['scripts'], {
        firstId: firstScript,
        secondId: secondScript,
      });
    },
  );

  test(
    'startup checks enabled and disabled sources and continues after a failure',
    () async {
      final initial = MusicSourceState(
        records: [
          _record('enabled'),
          _record('disabled'),
          _record('broken'),
          _record('last'),
        ],
        enabledIds: const ['enabled'],
      );
      final harness = await _Harness.create(
        initial,
        checkFailedIds: const {'broken'},
        checkUpdateUrls: const {
          'disabled': 'https://example.invalid/disabled.js',
          'last': 'https://example.invalid/last.js',
        },
      );
      addTearDown(harness.container.dispose);

      await harness.container
          .read(musicSourceControllerProvider.notifier)
          .checkAllForUpdates();

      final checker =
          harness.container.read(musicSourceUpdateRuntimeProvider)
              as _CheckingRuntime;
      expect(checker.checkedIds, ['enabled', 'disabled', 'broken', 'last']);
      expect(
        harness.container
            .read(musicSourceUpdatesProvider)
            .map((item) => item.sourceId),
        ['disabled', 'last'],
      );
      expect(harness.store.current, same(initial));
      expect(
        (harness.container.read(musicSourceRuntimeProvider)
                as _ValidationRuntime)
            .loadedIds,
        isEmpty,
      );
    },
  );

  test(
    'manual update reopens a dismissed notice for the same script',
    () async {
      final record = _updateRecord();
      final harness = await _Harness.forUpdate();
      addTearDown(harness.container.dispose);
      final updates = harness.container.read(
        musicSourceUpdatesProvider.notifier,
      );
      final notice = _notice(record);
      updates.receive(notice);
      updates.dismiss(notice);
      expect(harness.container.read(musicSourceUpdatesProvider), isEmpty);

      expect(
        await harness.container
            .read(musicSourceControllerProvider.notifier)
            .checkForUpdate(record.id, showAgain: true),
        isTrue,
      );
      expect(harness.container.read(musicSourceUpdatesProvider), [notice]);
      expect(
        updates.latestFor(record.copyWith(updatedAt: DateTime.utc(2030))),
        isNull,
      );
    },
  );

  test(
    'a script update notification takes priority over the original import URL',
    () async {
      final record = _updateRecord();
      final harness = await _Harness.forUpdate(
        checkUpdateUrls: {
          record.id: 'https://example.invalid/author-update.js',
        },
      );
      addTearDown(harness.container.dispose);

      expect(
        await harness.container
            .read(musicSourceControllerProvider.notifier)
            .checkForUpdate(record.id),
        isTrue,
      );
      final notice = harness.container.read(musicSourceUpdatesProvider).single;
      expect(notice.updateUrl, 'https://example.invalid/author-update.js');
      expect(notice.log, '作者提供的更新说明');
      expect(
        (harness.container.read(apiClientProvider).httpClientAdapter
                as _UpdateAdapter)
            .requested
            .isCompleted,
        isFalse,
      );
    },
  );

  for (final changed in [true, false]) {
    test(
      'URL update check compares content without applying it: changed=$changed',
      () async {
        final record = _updateRecord();
        final harness = await _Harness.forUpdate(
          downloadedScript: changed ? _newUpdateScript : _oldUpdateScript,
        );
        addTearDown(harness.container.dispose);

        expect(
          await harness.container
              .read(musicSourceControllerProvider.notifier)
              .checkForUpdate(record.id),
          changed,
        );
        expect(harness.store.scripts[record.id], _oldUpdateScript);
        expect(harness.store.current.records[1].version, '1.0');
        final notices = harness.container.read(musicSourceUpdatesProvider);
        if (changed) {
          expect(notices.single.updateUrl, record.origin);
          expect(notices.single.log, contains('2.0'));
        } else {
          expect(notices, isEmpty);
        }
      },
    );
  }

  test(
    'update checker waits for an asynchronous update response before disposal',
    () async {
      const channel = MethodChannel('test/async-source-update');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final record = _updateRecord();
      final responseGate = Completer<void>();
      final adapter = _UpdateAdapter('{}', 200, responseGate.future);
      final notices = <MusicSourceUpdateNotice>[];
      final runtime = MusicSourceRuntime(
        Dio()..httpClientAdapter = adapter,
        channel: channel,
        onUpdate: notices.add,
      );
      var disposed = false;
      Future<void> event(Map<String, dynamic> data) async {
        await messenger.handlePlatformMessage(
          channel.name,
          channel.codec.encodeMethodCall(MethodCall('event', data)),
          null,
        );
      }

      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'load') {
          await event({
            'type': 'httpRequest',
            'requestId': 'update-1',
            'url': 'https://example.invalid/check',
            'options': {'method': 'GET'},
          });
          return {
            'sources': {
              'kw': {
                'actions': ['musicUrl'],
                'qualitys': ['128k'],
              },
            },
          };
        }
        if (call.method == 'httpResponse') {
          await event({
            'type': 'updateAlert',
            'sourceId': record.id,
            'sourceKey': record.runtimeKey,
            'log': 'Async update notes',
            'updateUrl': 'https://example.invalid/update.js',
          });
        }
        if (call.method == 'dispose') disposed = true;
        return null;
      });
      addTearDown(() {
        if (!responseGate.isCompleted) responseGate.complete();
        messenger.setMockMethodCallHandler(channel, null);
        channel.setMethodCallHandler(null);
      });
      var checked = false;
      final checking = runtime.checkForUpdates(record, _oldUpdateScript).then((
        _,
      ) {
        checked = true;
      });
      await adapter.requested.future;
      await Future<void>.delayed(const Duration(milliseconds: 350));
      expect(checked, isFalse);
      expect(disposed, isFalse);
      responseGate.complete();
      await checking;
      expect(notices.single.log, 'Async update notes');
      expect(disposed, isTrue);
    },
  );

  for (final enabled in [true, false]) {
    test('script update preserves priority and enabled=$enabled', () async {
      final record = _updateRecord();
      final harness = await _Harness.forUpdate(enabled: enabled);
      addTearDown(harness.container.dispose);
      final previous = harness.store.current;

      expect(
        await harness.container
            .read(musicSourceControllerProvider.notifier)
            .updateScript(_notice(record)),
        isTrue,
      );

      final updated = harness.store.current;
      expect(updated.enabledIds, previous.enabledIds);
      expect(
        updated.records.map((item) => item.id),
        previous.records.map((item) => item.id),
      );
      final replacement = updated.records[1];
      expect(replacement.version, '2.0');
      expect(replacement.origin, record.origin);
      expect(replacement.importedAt, record.importedAt);
      expect(harness.store.scripts[record.id], _newUpdateScript);
      expect(updated.activatingId, isNull);
    });
  }

  test('failed update initialization keeps old script and state', () async {
    final record = _updateRecord();
    final harness = await _Harness.forUpdate(failValidation: true);
    addTearDown(harness.container.dispose);
    final previous = harness.store.current;

    await expectLater(
      harness.container
          .read(musicSourceControllerProvider.notifier)
          .updateScript(_notice(record)),
      throwsA(isA<MusicSourceRuntimeException>()),
    );

    expect(harness.store.scripts[record.id], _oldUpdateScript);
    expect(harness.store.current, same(previous));
    expect(
      harness.container.read(musicSourceControllerProvider).requireValue,
      same(previous),
    );
  });

  test('failed index commit restores the previous script', () async {
    final record = _updateRecord();
    final harness = await _Harness.forUpdate();
    addTearDown(harness.container.dispose);
    final previous = harness.store.current;
    harness.store.failNextSave = true;

    await expectLater(
      harness.container
          .read(musicSourceControllerProvider.notifier)
          .updateScript(_notice(record)),
      throwsStateError,
    );

    expect(harness.store.scripts[record.id], _oldUpdateScript);
    expect(harness.store.current, same(previous));
    expect(
      harness.container.read(musicSourceControllerProvider).requireValue,
      same(previous),
    );
  });

  test(
    'cloud export waits for the script and metadata to commit together',
    () async {
      final record = _updateRecord();
      final responseGate = Completer<void>();
      final harness = await _Harness.forUpdate(
        beforeResponse: responseGate.future,
      );
      addTearDown(harness.container.dispose);
      final controller = harness.container.read(
        musicSourceControllerProvider.notifier,
      );
      final updating = controller.updateScript(_notice(record));
      final adapter =
          harness.container.read(apiClientProvider).httpClientAdapter
              as _UpdateAdapter;
      await adapter.requested.future;
      var exported = false;
      final exporting = controller.exportForSync().then((snapshot) {
        exported = true;
        return snapshot;
      });
      await Future<void>.delayed(Duration.zero);
      expect(exported, isFalse);
      responseGate.complete();
      await updating;

      final snapshot = await exporting;
      final records = snapshot['records'] as List<Map<String, dynamic>>;
      final updated = records.firstWhere((item) => item['id'] == record.id);
      expect(updated['version'], '2.0');
      expect((snapshot['scripts'] as Map)[record.id], _newUpdateScript);
    },
  );

  test(
    'HTTP error does not expose a credential URL or overwrite the script',
    () async {
      final record = _updateRecord();
      final harness = await _Harness.forUpdate(httpStatus: 403);
      addTearDown(harness.container.dispose);

      await expectLater(
        harness.container
            .read(musicSourceControllerProvider.notifier)
            .updateScript(_notice(record)),
        throwsA(
          isA<MusicSourceRuntimeException>()
              .having((error) => error.message, 'status', contains('403'))
              .having(
                (error) => error.message,
                'credential',
                isNot(contains('fixture-secret')),
              ),
        ),
      );
      expect(harness.store.scripts[record.id], _oldUpdateScript);
      expect(harness.store.current.records[1].version, '1.0');
    },
  );

  test('unchanged download keeps the original script revision', () async {
    final record = _updateRecord();
    final harness = await _Harness.forUpdate(
      downloadedScript: _oldUpdateScript,
    );
    addTearDown(harness.container.dispose);

    expect(
      await harness.container
          .read(musicSourceControllerProvider.notifier)
          .updateScript(_notice(record)),
      isFalse,
    );
    expect(harness.store.current.records[1].runtimeKey, record.runtimeKey);
    expect(harness.store.scripts[record.id], _oldUpdateScript);
  });

  test(
    'a different source from the update URL is not allowed to replace the original',
    () async {
      final record = _updateRecord();
      final harness = await _Harness.forUpdate(
        downloadedScript: '// @name Other source\n// @author other\n',
      );
      addTearDown(harness.container.dispose);

      await expectLater(
        harness.container
            .read(musicSourceControllerProvider.notifier)
            .updateScript(_notice(record)),
        throwsA(isA<MusicSourceRuntimeException>()),
      );
      expect(harness.store.scripts[record.id], _oldUpdateScript);
      expect(harness.store.current.records[1].runtimeKey, record.runtimeKey);
    },
  );
}

class _Harness {
  _Harness(this.container);

  final ProviderContainer container;
  _MemoryStore get store =>
      container.read(musicSourceStoreProvider) as _MemoryStore;

  static Future<_Harness> forUpdate({
    bool enabled = true,
    bool failValidation = false,
    String downloadedScript = _newUpdateScript,
    int httpStatus = 200,
    Future<void>? beforeResponse,
    Map<String, String> checkUpdateUrls = const {},
  }) async {
    final record = _updateRecord();
    final harness = await create(
      MusicSourceState(
        records: [_record('first'), record, _record('third')],
        enabledIds: ['first', if (enabled) record.id, 'third'],
      ),
      failingIds: {if (failValidation) record.id},
      downloadedScript: downloadedScript,
      httpStatus: httpStatus,
      beforeResponse: beforeResponse,
      checkUpdateUrls: checkUpdateUrls,
    );
    harness.store.scripts[record.id] = _oldUpdateScript;
    return harness;
  }

  static Future<_Harness> create(
    MusicSourceState initialState, {
    Set<String> failingIds = const <String>{},
    String downloadedScript = '',
    int httpStatus = 200,
    Future<void>? beforeResponse,
    Set<String> checkFailedIds = const {},
    Map<String, String> checkUpdateUrls = const {},
  }) async {
    final preferences = await SharedPreferences.getInstance();
    final store = _MemoryStore(preferences, initialState);
    final runtime = _ValidationRuntime(failingIds);
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        musicSourceStoreProvider.overrideWithValue(store),
        musicSourceRuntimeProvider.overrideWithValue(runtime),
        musicSourceUpdateRuntimeProvider.overrideWith(
          (ref) => _CheckingRuntime(
            checkFailedIds,
            checkUpdateUrls,
            ref.read(musicSourceUpdatesProvider.notifier).receive,
          ),
        ),
        apiClientProvider.overrideWithValue(
          Dio()
            ..httpClientAdapter = _UpdateAdapter(
              downloadedScript,
              httpStatus,
              beforeResponse,
            ),
        ),
      ],
    );
    await container.read(musicSourceControllerProvider.future);
    return _Harness(container);
  }
}

class _MemoryStore extends MusicSourceStore {
  _MemoryStore(super.preferences, this.current);

  MusicSourceState current;
  Map<String, String> scripts = <String, String>{};
  bool failNextSave = false;

  @override
  Future<MusicSourceState> load() async => current;

  @override
  Future<void> save(MusicSourceState state) async {
    if (failNextSave) {
      failNextSave = false;
      throw StateError('Failed to save update index');
    }
    current = state;
  }

  @override
  Future<void> writeScript(String id, String script) async {
    scripts[id] = script;
  }

  @override
  Future<String> readScript(String id) async => scripts[id] ?? 'script:$id';

  @override
  Future<void> replaceAll(
    MusicSourceState state,
    Map<String, String> nextScripts,
  ) async {
    current = state;
    scripts = Map<String, String>.from(nextScripts);
  }
}

class _ValidationRuntime extends MusicSourceRuntime {
  _ValidationRuntime(this.failingIds)
    : super(Dio(), channel: const MethodChannel('test/controller-runtime'));

  final Set<String> failingIds;
  final List<String> loadedIds = [];

  @override
  Future<Map<MusicSource, List<Quality>>> load(
    MusicSourceRecord record,
    String script,
  ) async {
    loadedIds.add(record.id);
    if (failingIds.contains(record.id)) {
      throw const MusicSourceRuntimeException('初始化失败');
    }
    return const {
      MusicSource.kw: [Quality.k128],
    };
  }

  @override
  Future<void> disposeRuntime() async {}
}

class _CheckingRuntime extends MusicSourceRuntime {
  _CheckingRuntime(this.failedIds, this.updateUrls, this.onNotice)
    : super(Dio(), channel: const MethodChannel('test/source-update-runtime'));

  final Set<String> failedIds;
  final Map<String, String> updateUrls;
  final void Function(MusicSourceUpdateNotice) onNotice;
  final List<String> checkedIds = [];

  @override
  Future<void> checkForUpdates(MusicSourceRecord record, String script) async {
    checkedIds.add(record.id);
    if (failedIds.contains(record.id)) {
      throw const MusicSourceRuntimeException('测试检查失败');
    }
    final url = updateUrls[record.id];
    if (url != null) {
      onNotice(
        MusicSourceUpdateNotice(
          sourceId: record.id,
          sourceKey: record.runtimeKey,
          log: '作者提供的更新说明',
          updateUrl: url,
        ),
      );
    }
  }

  @override
  Future<void> disposeRuntime() async {}
}

class _UpdateAdapter implements HttpClientAdapter {
  _UpdateAdapter(this.script, this.status, this.beforeResponse);

  final String script;
  final int status;
  final Future<void>? beforeResponse;
  final Completer<void> requested = Completer<void>();

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (!requested.isCompleted) requested.complete();
    await beforeResponse;
    return ResponseBody.fromString(script, status);
  }

  @override
  void close({bool force = false}) {}
}

const _oldUpdateScript =
    '// @name Update Source\n// @author tester\n// @version 1.0\n';
const _newUpdateScript =
    '// @name Update Source\n// @author tester\n// @version 2.0\n';

MusicSourceRecord _updateRecord() {
  final id = musicSourceId(parseMusicSourceMetadata(_oldUpdateScript));
  return MusicSourceRecord(
    id: id,
    name: 'Update Source',
    description: '',
    author: 'tester',
    homepage: '',
    version: '1.0',
    origin: 'https://example.invalid/original.js',
    importedAt: DateTime.utc(2026, 7, 31),
    updatedAt: DateTime.utc(2026, 7, 31),
    capabilities: const {
      MusicSource.kw: [Quality.k128],
    },
  );
}

MusicSourceUpdateNotice _notice(MusicSourceRecord record) =>
    MusicSourceUpdateNotice(
      sourceId: record.id,
      sourceKey: record.runtimeKey,
      log: 'Update fixture',
      updateUrl: 'https://example.invalid/update.js?key=fixture-secret',
    );

MusicSourceRecord _record(String id, {String? name, String author = 'test'}) {
  return MusicSourceRecord(
    id: id,
    name: name ?? id,
    description: '',
    author: author,
    homepage: '',
    version: '1',
    origin: 'test',
    importedAt: DateTime.utc(2026, 7, 31),
    updatedAt: DateTime.utc(2026, 7, 31),
    capabilities: const {
      MusicSource.kw: [Quality.k128],
    },
  );
}
