import 'package:audio_service/audio_service.dart' show MediaItem;

import 'media_item_copy.dart';
import 'vivo_music_metadata.dart';

class VivoQueueBrowser {
  const VivoQueueBrowser._();

  static const pageSize = 50;
  static const emptyItemId = 'cyshine:vivo:empty-queue';

  static List<MediaItem> snapshot({
    required List<MediaItem> queue,
    required MediaItem? current,
    required int? currentIndex,
  }) {
    if (current == null) return queue;
    if (currentIndex != null &&
        currentIndex >= 0 &&
        currentIndex < queue.length) {
      if (queue[currentIndex].id == current.id) return queue;
      // A missing local file may have fallen back to its online version. Match
      // the active row's ID to the media session while retaining song labels.
      return List<MediaItem>.of(queue)
        ..[currentIndex] = preserveMediaItemArtHeaders(
          queue[currentIndex],
          queue[currentIndex].copyWith(id: current.id),
        );
    }
    if (queue.any((item) => item.id == current.id)) return queue;
    // Standalone search/file playback still has a current song, even when the
    // app queue is empty or only contains a subsequently enqueued song.
    return [current, ...queue];
  }

  static List<MediaItem> page(
    List<MediaItem> items,
    Map<String, dynamic>? options,
  ) {
    final value = options?[VivoMusicMetadata.pageKey] ?? 0;
    if (value is! num ||
        !value.isFinite ||
        value < 0 ||
        value != value.toInt()) {
      return const [];
    }
    final page = value.toInt();
    if (items.isEmpty && page == 0) {
      // Vivo retries an entirely empty first page. Return an inert row that
      // explicitly ends pagination; its reserved ID is never dispatched.
      return const [
        MediaItem(
          id: emptyItemId,
          title: '暂无播放队列',
          artist: '请先在栖弦播放歌曲',
          extras: {
            VivoMusicMetadata.pageKey: 1,
            VivoMusicMetadata.hasMoreKey: false,
          },
        ),
      ];
    }
    if (page > items.length ~/ pageSize) return const [];
    final start = page * pageSize;
    if (start >= items.length) return const [];
    final end = (start + pageSize).clamp(0, items.length);
    return List<MediaItem>.generate(end - start, (offset) {
      final item = items[start + offset];
      final title = item.extras?[VivoMusicMetadata.songTitleKey] as String?;
      final artist = item.extras?[VivoMusicMetadata.songArtistKey] as String?;
      final extras = <String, dynamic>{...?item.extras}
        ..remove(VivoMusicMetadata.lyricKey)
        ..remove(VivoMusicMetadata.pageKey)
        ..remove(VivoMusicMetadata.hasMoreKey);
      if (start + offset == end - 1) {
        extras[VivoMusicMetadata.pageKey] = page + 1;
        extras[VivoMusicMetadata.hasMoreKey] = end < items.length;
      }
      return preserveMediaItemArtHeaders(
        item,
        item.copyWith(
          title: title ?? item.title,
          artist: artist ?? item.artist ?? '',
          displayTitle: title ?? item.title,
          displaySubtitle: artist ?? item.artist ?? '',
          playable: true,
          extras: extras,
        ),
      );
    }, growable: false);
  }
}
