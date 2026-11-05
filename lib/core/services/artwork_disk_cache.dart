import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Application-support storage: thumbnails survive both process and LRU eviction.
/// An empty file records a successful read with no embedded picture.
class ArtworkDiskCache {
  static Directory? _directory;

  static void configure(String supportDirectory) {
    _directory = Directory('$supportDirectory/local_artwork_v1');
  }

  static String _name(String key) => '${sha256.convert(utf8.encode(key))}.png';

  static Future<({bool hit, Uint8List? bytes})> read(String key) async {
    final directory = _directory;
    if (directory == null) return (hit: false, bytes: null);
    try {
      final bytes = await File('${directory.path}/${_name(key)}').readAsBytes();
      return (hit: true, bytes: bytes.isEmpty ? null : bytes);
    } catch (_) {
      return (hit: false, bytes: null);
    }
  }

  static Future<void> write(String key, Uint8List? bytes) async {
    final directory = _directory;
    if (directory == null) return;
    try {
      await directory.create(recursive: true);
      final file = File('${directory.path}/${_name(key)}');
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsBytes(bytes ?? const [], flush: true);
      await temporary.rename(file.path);
    } catch (_) {
      // The in-memory cover remains available if persistence fails.
    }
  }

  static Future<void> remove(String key) async {
    final directory = _directory;
    if (directory == null) return;
    try {
      await File('${directory.path}/${_name(key)}').delete();
    } catch (_) {}
  }
}
