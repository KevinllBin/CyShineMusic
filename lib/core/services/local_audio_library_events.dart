import 'dart:async';

import 'embedded_audio_tags.dart';

/// File operations publish their actual results, independently of open pages.
class LocalAudioLibraryEvents {
  static final _listeners = <Future<void> Function(LocalAudioLibraryChange)>{};

  static void Function() listen(
    Future<void> Function(LocalAudioLibraryChange) listener,
  ) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  static Future<void> saved(String path, {EmbeddedAudioTags? tags}) =>
      _publish(LocalAudioLibraryChange(path: path, tags: tags));

  static Future<void> deleted(Iterable<String> paths) =>
      _publish(LocalAudioLibraryChange(deletedPaths: paths.toList()));

  static Future<void> _publish(LocalAudioLibraryChange event) => Future.wait([
    for (final listener in _listeners.toList()) listener(event),
  ]);
}

class LocalAudioLibraryChange {
  const LocalAudioLibraryChange({
    this.path = '',
    this.tags,
    this.deletedPaths = const [],
  });

  final String path;
  final EmbeddedAudioTags? tags;
  final List<String> deletedPaths;
}
