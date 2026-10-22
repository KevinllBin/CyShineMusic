import 'enums.dart';
import 'music_info.dart';
import 'catalog_result.dart';
import 'search_category.dart';

class SearchResponse {
  const SearchResponse({
    required this.list,
    required this.page,
    required this.limit,
    required this.allPage,
    required this.total,
    required this.source,
    this.catalog = const {},
    this.notices = const [],
  });

  final List<MusicInfo> list;
  final int page;
  final int limit;
  final int allPage;
  final int total;
  final MusicSource source;
  final Map<SearchCategory, List<CatalogItem>> catalog;
  final List<String> notices;
  bool get hasResults =>
      list.isNotEmpty || catalog.values.any((items) => items.isNotEmpty);
  int get visibleCount =>
      list.length + catalog.values.fold(0, (sum, items) => sum + items.length);

  factory SearchResponse.fromJson(Map<String, dynamic> json) {
    final listRaw = json['list'];
    final items = <MusicInfo>[];
    if (listRaw is List) {
      for (final item in listRaw) {
        if (item is Map<String, dynamic>) {
          items.add(MusicInfo.fromJson(item));
        } else if (item is Map) {
          items.add(MusicInfo.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }
    return SearchResponse(
      list: items,
      page: (json['page'] as num?)?.toInt() ?? 1,
      limit: (json['limit'] as num?)?.toInt() ?? 30,
      allPage: (json['allPage'] as num?)?.toInt() ?? 1,
      total: (json['total'] as num?)?.toInt() ?? items.length,
      source: MusicSource.fromCode((json['source'] as String?) ?? 'all'),
    );
  }
}
