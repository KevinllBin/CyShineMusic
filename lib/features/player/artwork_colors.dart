import 'dart:async';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'flow_palette.dart';
import 'widgets/lyric_ink.dart';

/// All player colors derived from one cover, shared by its visual consumers.
class ArtworkColors {
  const ArtworkColors({
    required this.baseColor,
    required this.palette,
    required this.lyricInk,
  });

  final Color baseColor;
  final FlowPalette palette;
  final Color? lyricInk;

  Color? get accent =>
      palette == FlowPalette.fallback ? null : Color(palette.accentsArgb.first);
}

const _channel = MethodChannel('cy_shine_music/artwork_colors');
const _maxCachedColors = 12;
final _loads = <ImageProvider<Object>, Future<ArtworkColors?>>{};
final _nativeResults = <Object, Future<ArtworkColors?>>{};
ImageProvider<Object>? _requestedArtwork;

/// Android samples an existing cached file or encoded memory cover as a
/// software Bitmap. Only a few ARGB values come back through the channel.
/// Other platforms and custom ImageProviders retain the Flutter implementation.
Future<ArtworkColors?> loadArtworkColors(
  ImageProvider<Object> provider, {
  ImageConfiguration configuration = ImageConfiguration.empty,
}) {
  _requestedArtwork = provider;
  final pending = _loads[provider];
  if (pending != null) return pending;
  final future = _load(provider, configuration);
  _loads[provider] = future;
  unawaited(
    future.then<void>(
      (_) {
        _loads.remove(provider);
      },
      onError: (Object _, StackTrace _) {
        _loads.remove(provider);
      },
    ),
  );
  return future;
}

Future<ArtworkColors?> _load(
  ImageProvider<Object> provider,
  ImageConfiguration configuration,
) async {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    try {
      ImageProvider<Object> source = provider;
      while (source is ResizeImage) {
        source = source.imageProvider;
      }
      final Map<String, Object> arguments;
      final Object key;
      if (source is MemoryImage) {
        arguments = {'bytes': source.bytes};
        key = source;
      } else if (source is CachedNetworkImageProvider) {
        final manager =
            source.cacheManager ??
            CachedNetworkImageProvider.defaultCacheManager;
        // Match the display provider's first available image, including a
        // stale cached cover while its network refresh runs separately.
        final cached = await manager.getFileFromCache(
          source.cacheKey ?? source.url,
        );
        final file =
            cached?.file ??
            await manager.getSingleFile(
              source.url,
              key: source.cacheKey ?? source.url,
              headers: source.headers ?? const {},
            );
        final stat = await file.stat();
        arguments = {'path': file.path};
        key = (file.path, stat.modified, stat.size);
      } else if (source is FileImage) {
        final stat = await source.file.stat();
        arguments = {'path': source.file.path};
        key = (source.file.path, stat.modified, stat.size);
      } else {
        return _loadFlutter(provider, configuration);
      }
      // An older download can finish after a newer cover. Do not let it
      // replace the current cover's queued native job.
      if (_requestedArtwork != provider) return null;
      final cached = _nativeResults.remove(key);
      if (cached != null) {
        _nativeResults[key] = cached;
        return await cached ?? await _loadFlutter(provider, configuration);
      }
      final result = _extractNative(arguments);
      _nativeResults[key] = result;
      while (_nativeResults.length > _maxCachedColors) {
        _nativeResults.remove(_nativeResults.keys.first);
      }
      try {
        final colors = await result;
        if (colors == null && identical(_nativeResults[key], result)) {
          _nativeResults.remove(key);
        }
        return colors ?? await _loadFlutter(provider, configuration);
      } catch (_) {
        if (identical(_nativeResults[key], result)) _nativeResults.remove(key);
        rethrow;
      }
    } on _CancelledExtraction {
      // A -> B -> A can reuse A's pending Future just as Android cancels its
      // queued job. Restart it when A has become the current cover again.
      if (_requestedArtwork == provider) return _load(provider, configuration);
      return null;
    } on MissingPluginException {
      // A widget can start the audio engine before an Activity attaches the
      // app plugin. Retry native on a later request instead of caching failure.
      return _loadFlutter(provider, configuration);
    } catch (_) {
      return _loadFlutter(provider, configuration);
    }
  }
  return _loadFlutter(provider, configuration);
}

Future<ArtworkColors?> _extractNative(Map<String, Object> arguments) async {
  final result = await _channel.invokeMapMethod<String, Object?>(
    'extract',
    arguments,
  );
  if (result == null) return null;
  if (result['cancelled'] == true) throw const _CancelledExtraction();
  final base = result['baseArgb'] as int;
  final accents = (result['accentsArgb'] as List).cast<int>();
  if (accents.length != FlowPalette.accentCount) return null;
  final ink = result['lyricInkArgb'] as int?;
  return ArtworkColors(
    baseColor: Color(base),
    palette: result['hasPalette'] == false
        ? FlowPalette.fallback
        : FlowPalette(
            baseArgb: result['paletteBaseArgb'] as int,
            accentsArgb: List<int>.unmodifiable(accents),
          ),
    lyricInk: ink == null ? null : Color(ink),
  );
}

class _CancelledExtraction implements Exception {
  const _CancelledExtraction();
}

typedef _Pixels = ({Uint8List rgba, int width, int height});

ArtworkColors _extractFlutter(_Pixels pixels) {
  final bytes = pixels.rgba;
  var red = 0;
  var green = 0;
  var blue = 0;
  for (var row = 0; row < 5; row++) {
    final y = ((row + 0.5) * pixels.height / 5).floor().clamp(
      0,
      pixels.height - 1,
    );
    for (var column = 0; column < 5; column++) {
      final x = ((column + 0.5) * pixels.width / 5).floor().clamp(
        0,
        pixels.width - 1,
      );
      final offset = (y * pixels.width + x) * 4;
      final alpha = bytes[offset + 3];
      red += bytes[offset] * alpha ~/ 255;
      green += bytes[offset + 1] * alpha ~/ 255;
      blue += bytes[offset + 2] * alpha ~/ 255;
    }
  }
  return ArtworkColors(
    baseColor: Color.fromARGB(255, red ~/ 25, green ~/ 25, blue ~/ 25),
    palette: extractFlowPalette(bytes, pixels.width, pixels.height),
    lyricInk: extractLyricInk(bytes),
  );
}

Future<ArtworkColors?> _loadFlutter(
  ImageProvider<Object> provider,
  ImageConfiguration configuration,
) async {
  final result = Completer<ArtworkColors?>();
  final ImageStream stream;
  try {
    stream = provider.resolve(configuration);
  } catch (_) {
    return null;
  }
  var sampling = false;
  final listener = ImageStreamListener(
    (info, _) async {
      if (sampling || result.isCompleted) {
        info.dispose();
        return;
      }
      sampling = true;
      ArtworkColors? colors;
      try {
        final image = info.image;
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        if (data != null &&
            !result.isCompleted &&
            image.width > 0 &&
            image.height > 0) {
          final pixels = (
            rgba: data.buffer.asUint8List(
              data.offsetInBytes,
              data.lengthInBytes,
            ),
            width: image.width,
            height: image.height,
          );
          colors = pixels.rgba.length <= 32 * 32 * 4
              ? _extractFlutter(pixels)
              : await compute(
                  _extractFlutter,
                  pixels,
                  debugLabel: 'player-artwork-colors',
                );
        }
      } catch (_) {
        // A failed cover should leave the player usable with its theme colors.
      } finally {
        info.dispose();
        if (!result.isCompleted) result.complete(colors);
      }
    },
    onError: (Object _, StackTrace? _) {
      if (!result.isCompleted) result.complete(null);
    },
  );
  stream.addListener(listener);
  try {
    return await result.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        if (!result.isCompleted) result.complete(null);
        return null;
      },
    );
  } finally {
    stream.removeListener(listener);
  }
}
