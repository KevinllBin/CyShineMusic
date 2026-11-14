import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../music_sources/music_source_controller.dart';
import 'settings_store.dart';

/// Combines portable settings with the existing validated source snapshot.
class SettingsBackupService {
  SettingsBackupService(this._ref);

  final Ref _ref;
  bool _busy = false;

  Future<Map<String, dynamic>> exportBackup() => _run(() async {
    final sources = await _ref
        .read(musicSourceControllerProvider.notifier)
        .exportForBackup();
    return {
      ..._ref.read(settingsProvider.notifier).exportForBackup(),
      'version': 2,
      'musicSources': sources,
    };
  });

  /// Validates settings and the source envelope without running any scripts.
  /// The source controller validates script identities and initializes all
  /// scripts after the user confirms the import, before replacing local files.
  Map<String, dynamic> validateBackup(Object? value) {
    _ref.read(settingsProvider.notifier).parseBackup(value);
    final backup = Map<String, dynamic>.from(value as Map);
    if (backup['version'] == 2 || backup.containsKey('musicSources')) {
      final sources = backup['musicSources'];
      if (sources is! Map ||
          sources['records'] is! List ||
          sources['enabledIds'] is! List ||
          sources['scripts'] is! Map) {
        throw const FormatException('配置中的音源数据不完整');
      }
    }
    return backup;
  }

  Future<void> importBackup(Object? value) => _run(() async {
    final backup = validateBackup(value);
    if (backup.containsKey('musicSources')) {
      // Apply sources first: a corrupt or unusable script must not cause
      // settings to be partially imported. replaceAll stages source files.
      await _ref.read(musicSourceControllerProvider.future);
      await _ref
          .read(musicSourceControllerProvider.notifier)
          .applyFromBackup(backup['musicSources'] as Map);
    }
    await _ref.read(settingsProvider.notifier).applyFromBackup(backup);
  });

  Future<T> _run<T>(Future<T> Function() action) async {
    if (_busy) throw StateError('正在处理配置，请稍候');
    _busy = true;
    try {
      return await action();
    } finally {
      _busy = false;
    }
  }
}

final settingsBackupServiceProvider = Provider<SettingsBackupService>((ref) {
  return SettingsBackupService(ref);
});
