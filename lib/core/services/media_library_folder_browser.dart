import 'package:path/path.dart' as p;

import 'media_library.dart';
import 'storage_browser_service.dart';

/// Browses the hierarchy already recorded in MediaStore, with no directory I/O.
class MediaLibraryFolderBrowser extends StorageBrowserService {
  Future<List<String>>? _folders;
  Future<List<String>> get _paths => _folders ??= MediaLibrary.folders();

  String _root(String path) =>
      RegExp(r'^/storage/emulated/\d+').firstMatch(path)?.group(0) ??
      RegExp(r'^/storage/[^/]+').firstMatch(path)?.group(0) ??
      '/';

  StorageBrowserEntry _entry(String path, {bool root = false}) =>
      StorageBrowserEntry(
        path: path,
        name: root && path.startsWith('/storage/emulated/')
            ? '内部存储'
            : p.posix.basename(path),
        isDirectory: true,
        isRoot: root,
        canRead: true,
        canWrite: false,
        totalBytes: 0,
        freeBytes: 0,
      );

  @override
  Future<List<StorageBrowserEntry>> listRoots() async => [
    for (final root in {for (final path in await _paths) _root(path)})
      _entry(root, root: true),
  ];

  @override
  Future<List<StorageBrowserEntry>> listChildren(
    String path, {
    Set<String>? fileExtensions,
  }) async {
    final prefix = path.endsWith('/') ? path : '$path/';
    final children = <String>{};
    for (final folder in await _paths) {
      if (!folder.startsWith(prefix)) continue;
      final suffix = folder.substring(prefix.length);
      if (suffix.isNotEmpty) children.add('$prefix${suffix.split('/').first}');
    }
    return [for (final child in children.toList()..sort()) _entry(child)];
  }
}
