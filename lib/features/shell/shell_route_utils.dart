import 'package:flutter/material.dart';

// Pure route helpers shared by the AppShell state machine (app_shell.dart)
// and the extracted shell widgets (widgets/). Kept in their own file so
// widgets/ never has to import the page file.

ColorScheme shellSchemeFor(String location, ColorScheme fallback) {
  return fallback;
}

bool isPlaylistLocation(String location) {
  return location == '/playlists' || location.startsWith('/playlists/');
}

bool isPlaylistDetailLocation(String location) {
  return location.startsWith('/playlists/') && location != '/playlists/import';
}

bool isImmersivePlaylistDetailLocation(String location) {
  final leaderboardDetail =
      location.startsWith('/discover/leaderboards/') &&
      location.split('/').length > 4;
  return isPlaylistDetailLocation(location) ||
      location.startsWith('/discover/playlists/') ||
      leaderboardDetail;
}

bool isDiscoveryLocation(String location) =>
    location == '/' || location.startsWith('/discover/');

bool isSongsLibraryLocation(String location) {
  return location == '/songs' || location == '/songs/search';
}

String normalizedPlayerReturnLocation(String primary, String fallback) {
  if (isPlayerReturnLocation(primary)) return primary;
  if (isPlayerReturnLocation(fallback)) return fallback;
  return '/songs';
}

bool isPlayerReturnLocation(String location) {
  final uri = Uri.tryParse(location);
  if (uri == null || uri.hasScheme || uri.hasAuthority) return false;
  final path = uri.path;
  if (isDiscoveryLocation(path)) return true;
  if (isPlaylistLocation(path)) return true;
  return switch (path) {
    '/' ||
    '/downloads' ||
    '/songs' ||
    '/songs/search' ||
    '/settings' ||
    '/settings/sources' ||
    '/settings/webdav' ||
    '/settings/equalizer' ||
    '/debug' => true,
    _ => false,
  };
}
