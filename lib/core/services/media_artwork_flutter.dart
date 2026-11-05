import 'dart:io';
import 'dart:typed_data';

import 'media_library.dart';

Future<Uint8List?> mediaArtwork(String path) async {
  if (!Platform.isAndroid || Uri.tryParse(path)?.authority != 'media') {
    return null;
  }
  try {
    return await MediaLibrary.artwork(path);
  } catch (_) {
    return null;
  }
}
