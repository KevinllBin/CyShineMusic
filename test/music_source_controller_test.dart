import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cy_shine_music/core/models/enums.dart';
import 'package:cy_shine_music/core/music_sources/music_source_controller.dart';
import 'package:cy_shine_music/core/music_sources/music_source_metadata_parser.dart';
import 'package:cy_shine_music/core/music_sources/music_source_models.dart';
import 'package:cy_shine_music/core/music_sources/music_source_runtime.dart';
import 'package:cy_shine_music/core/music_sources/music_source_store.dart';
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
}

class _Harness {
  _Harness(this.container);

  final ProviderContainer container;

  static Future<_Harness> create(
    MusicSourceState initialState, {
    Set<String> failingIds = const <String>{},
  }) async {
    final preferences = await SharedPreferences.getInstance();
    final store = _MemoryStore(preferences, initialState);
    final runtime = _ValidationRuntime(failingIds);
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        musicSourceStoreProvider.overrideWithValue(store),
        musicSourceRuntimeProvider.overrideWithValue(runtime),
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

  @override
  Future<MusicSourceState> load() async => current;

  @override
  Future<void> save(MusicSourceState state) async {
    current = state;
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

  @override
  Future<Map<MusicSource, List<Quality>>> load(
    MusicSourceRecord record,
    String script,
  ) async {
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
