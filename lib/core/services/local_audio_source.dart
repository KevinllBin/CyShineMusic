import 'dart:io';

/// Native playback verifies content providers can be opened and randomly read.
/// A URI suffix cannot establish whether a local provider is playable.
bool isLocalAudioSourceAvailable(String path) {
  if (path.isEmpty) return false;
  final uri = Uri.tryParse(path);
  if (uri?.scheme == 'content') return true;
  if (uri?.scheme == 'file') return File.fromUri(uri!).existsSync();
  return File(path).existsSync();
}

Uri localAudioSourceUri(String path) {
  final uri = Uri.tryParse(path);
  if (uri?.scheme == 'content' || uri?.scheme == 'file') return uri!;
  return File(path).uri;
}
