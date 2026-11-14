import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
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
import 'package:cy_shine_music/core/storage/settings_backup_service.dart';
import 'package:cy_shine_music/core/storage/settings_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'JSON restores all scripts and source priority on a fresh install',
    () async {
      final original = await _Harness.create(
        names: ['first', 'second', 'disabled'],
      );
      final ids = original.store.current.records
          .map((record) => record.id)
          .toList();
      original.store.current = original.store.current.copyWith(
        enabledIds: [ids[1], ids[0]],
      );
      await original.settings.setThemeMode(ThemeMode.dark);
      final backup = jsonDecode(
        jsonEncode(await original.service.exportBackup()),
      );
      original.container.dispose();

      final target = await _Harness.create();
      addTearDown(target.container.dispose);
      await target.service.importBackup(backup);

      final restored = target.container
          .read(musicSourceControllerProvider)
          .requireValue;
      expect(restored.records.map((record) => record.id), ids);
      expect(restored.enabledIds, [ids[1], ids[0]]);
      expect(restored.primary?.id, ids[1]);
      expect(restored.isEnabled(ids[2]), isFalse);
      expect(target.store.scripts, original.store.scripts);
      expect(restored.records.first.origin, '配置导入');
      expect(
        restored.records[1].origin,
        'https://example.com/source.js?key=fixture',
      );
      expect(target.container.read(settingsProvider).themeMode, ThemeMode.dark);
      expect(target.preferences.getString('theme_mode'), 'dark');
      target.container.invalidate(musicSourceControllerProvider);
      final reloaded = await target.container.read(
        musicSourceControllerProvider.future,
      );
      expect(reloaded.enabledIds, [ids[1], ids[0]]);
      expect(reloaded.records.length, 3);
    },
  );

  test('old settings backup preserves every local source', () async {
    final harness = await _Harness.create(names: ['existing']);
    addTearDown(harness.container.dispose);
    final previous = harness.store.current;
    final backup = harness.settings.exportForBackup();
    (backup['settings'] as Map)['themeMode'] = 'dark';

    await harness.service.importBackup(backup);

    expect(harness.container.read(settingsProvider).themeMode, ThemeMode.dark);
    expect(harness.store.current, same(previous));
    expect(harness.store.replacements, 0);
    expect(harness.runtime.loadedIds, isEmpty);
  });

  test('invalid settings are rejected before touching source files', () async {
    final harness = await _Harness.create(names: ['existing']);
    addTearDown(harness.container.dispose);
    final backup = await harness.service.exportBackup();
    (backup['settings'] as Map)['themeMode'] = 123;

    await expectLater(
      harness.service.importBackup(backup),
      throwsFormatException,
    );

    expect(harness.store.replacements, 0);
    expect(harness.runtime.loadedIds, isEmpty);
    expect(harness.preferences.getString('theme_mode'), isNull);
  });

  for (final failure in [
    'missing-script',
    'wrong-id',
    'bad-priority',
    'runtime',
  ]) {
    test('$failure leaves settings and source files intact', () async {
      final harness = await _Harness.create(names: ['existing']);
      addTearDown(harness.container.dispose);
      final previous = harness.store.current;
      final previousScripts = Map<String, String>.from(harness.store.scripts);
      final backup = await harness.service.exportBackup();
      (backup['settings'] as Map)['themeMode'] = 'dark';
      final sources = backup['musicSources'] as Map;
      switch (failure) {
        case 'missing-script':
          (sources['scripts'] as Map).clear();
        case 'wrong-id':
          (sources['scripts'] as Map)[previous.records.single.id] =
              '// @name Different source\n// @author fixture\n';
        case 'bad-priority':
          sources['enabledIds'] = ['missing'];
        case 'runtime':
          harness.runtime.fail = true;
      }

      await expectLater(
        harness.service.importBackup(backup),
        throwsA(isA<MusicSourceRuntimeException>()),
      );

      expect(harness.store.current, same(previous));
      expect(harness.store.scripts, previousScripts);
      expect(harness.store.replacements, 0);
      expect(harness.preferences.getString('theme_mode'), isNull);
    });
  }

  test('new backup must contain a source snapshot', () async {
    final harness = await _Harness.create(names: ['existing']);
    addTearDown(harness.container.dispose);
    final backup = await harness.service.exportBackup();
    backup.remove('musicSources');

    await expectLater(
      harness.service.importBackup(backup),
      throwsFormatException,
    );
    expect(harness.store.replacements, 0);
  });

  test('an explicitly empty source snapshot clears local sources', () async {
    final harness = await _Harness.create(names: ['existing']);
    addTearDown(harness.container.dispose);
    final backup = await harness.service.exportBackup();
    backup['musicSources'] = {'records': [], 'enabledIds': [], 'scripts': {}};

    await harness.service.importBackup(backup);

    expect(harness.store.current.records, isEmpty);
    expect(harness.store.current.enabledIds, isEmpty);
    expect(harness.store.scripts, isEmpty);
  });
}

class _Harness {
  _Harness(this.container, this.preferences, this.store, this.runtime);

  final ProviderContainer container;
  final SharedPreferences preferences;
  final _MemoryStore store;
  final _Runtime runtime;

  SettingsNotifier get settings => container.read(settingsProvider.notifier);
  SettingsBackupService get service =>
      container.read(settingsBackupServiceProvider);

  static Future<_Harness> create({List<String> names = const []}) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final scripts = <String, String>{};
    final records = <MusicSourceRecord>[];
    for (final name in names) {
      final script = '// @name $name\n// @author fixture\n// @version 1.0\n';
      final id = musicSourceId(parseMusicSourceMetadata(script));
      scripts[id] = script;
      records.add(
        MusicSourceRecord(
          id: id,
          name: name,
          description: '',
          author: 'fixture',
          homepage: '',
          version: '1.0',
          origin: name == 'second'
              ? 'https://example.com/source.js?key=fixture'
              : '/storage/emulated/0/Download/$name.js',
          importedAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
          capabilities: const {
            MusicSource.kw: [Quality.k128],
          },
        ),
      );
    }
    final store = _MemoryStore(
      preferences,
      MusicSourceState(
        records: records,
        enabledIds: records.take(2).map((record) => record.id).toList(),
      ),
      scripts,
    );
    final runtime = _Runtime();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        musicSourceStoreProvider.overrideWithValue(store),
        musicSourceRuntimeProvider.overrideWithValue(runtime),
      ],
    );
    return _Harness(container, preferences, store, runtime);
  }
}

class _MemoryStore extends MusicSourceStore {
  _MemoryStore(super.preferences, this.current, this.scripts);

  MusicSourceState current;
  Map<String, String> scripts;
  int replacements = 0;

  @override
  Future<MusicSourceState> load() async => current;

  @override
  Future<String> readScript(String id) async => scripts[id]!;

  @override
  Future<void> replaceAll(
    MusicSourceState state,
    Map<String, String> scripts,
  ) async {
    replacements++;
    current = state;
    this.scripts = Map<String, String>.from(scripts);
  }
}

class _Runtime extends MusicSourceRuntime {
  _Runtime()
    : super(Dio(), channel: const MethodChannel('test/settings-backup'));

  bool fail = false;
  final loadedIds = <String>[];

  @override
  Future<Map<MusicSource, List<Quality>>> load(
    MusicSourceRecord record,
    String script,
  ) async {
    loadedIds.add(record.id);
    if (fail) throw const MusicSourceRuntimeException('初始化失败');
    return record.capabilities;
  }

  @override
  Future<void> disposeRuntime() async {}
}
