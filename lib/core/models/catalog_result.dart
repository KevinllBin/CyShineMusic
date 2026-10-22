import 'playlist_summary.dart';
import 'search_category.dart';

/// A navigable search result. The platform ID is kept separate from its name.
class CatalogItem {
  const CatalogItem({
    required this.category,
    required this.summary,
    this.subtitle = '',
  });
  final SearchCategory category;
  final PlaylistSummary summary;
  final String subtitle;
  String get key => '${category.name}:${summary.key}';
}

class CatalogResult {
  const CatalogResult({
    required this.items,
    required this.total,
    required this.hasMore,
  });
  final List<CatalogItem> items;
  final int total;
  final bool hasMore;
}
