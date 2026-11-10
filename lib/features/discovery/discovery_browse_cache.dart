import '../../core/models/enums.dart';
import '../../core/models/playlist_summary.dart';

/// Session-only data, without retaining widgets, controllers or decoded images.
/// Each platform keeps its latest category; oversized lists restart at the top.
class DiscoveryBrowseCache {
  static const maxItemsPerSource = 300;

  final _entries = <MusicSource, DiscoveryBrowseSnapshot>{};

  DiscoveryBrowseSnapshot? restore({
    required MusicSource source,
    required String categoryId,
    required List<PlaylistSummary>? firstPage,
  }) {
    final snapshot = _entries.remove(source);
    if (snapshot == null ||
        snapshot.categoryId != categoryId ||
        !identical(snapshot.firstPage, firstPage)) {
      return null;
    }
    return snapshot;
  }

  void save({
    required MusicSource source,
    required String categoryId,
    required List<PlaylistSummary>? firstPage,
    required List<PlaylistSummary> items,
    required int nextPage,
    required bool hasMore,
    required double scrollOffset,
  }) {
    _entries.remove(source);
    if (firstPage == null || items.length > maxItemsPerSource) return;
    _entries[source] = DiscoveryBrowseSnapshot(
      categoryId: categoryId,
      firstPage: firstPage,
      items: List.unmodifiable(items),
      nextPage: nextPage,
      hasMore: hasMore,
      scrollOffset: scrollOffset.isFinite && scrollOffset > 0
          ? scrollOffset
          : 0,
    );
  }
}

class DiscoveryBrowseSnapshot {
  const DiscoveryBrowseSnapshot({
    required this.categoryId,
    required this.firstPage,
    required this.items,
    required this.nextPage,
    required this.hasMore,
    required this.scrollOffset,
  });

  final String categoryId;
  // A refresh creates a new first-page list, invalidating the old pagination.
  final List<PlaylistSummary> firstPage;
  final List<PlaylistSummary> items;
  final int nextPage;
  final bool hasMore;
  final double scrollOffset;
}
