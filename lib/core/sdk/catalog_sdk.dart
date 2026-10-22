import '../models/catalog_result.dart';
import '../models/enums.dart';
import '../models/playlist_info.dart';
import '../models/search_category.dart';
import 'catalog/kw_catalog.dart';
import 'catalog/tx_catalog.dart';
import 'catalog/wy_catalog.dart';

class CatalogSdk {
  static bool supports(MusicSource source, SearchCategory category) =>
      category == SearchCategory.songs ||
      category == SearchCategory.all ||
      const {MusicSource.wy, MusicSource.tx, MusicSource.kw}.contains(source);

  static Future<CatalogResult> search(
    String keyword,
    MusicSource source,
    SearchCategory category,
    int page,
    int limit,
  ) => switch (source) {
    MusicSource.wy => WyCatalog.search(keyword, category, page, limit),
    MusicSource.kw => KwCatalog.search(keyword, category, page, limit),
    MusicSource.tx => TxCatalog.search(keyword, category, page, limit),
    _ => throw UnsupportedError('${source.label}暂不支持${category.label}搜索'),
  };

  static Future<PlaylistInfo> detail(
    MusicSource source,
    String id, {
    required bool artist,
    int? maxTracks,
  }) => switch (source) {
    MusicSource.wy => WyCatalog.detail(
      id,
      artist: artist,
      maxTracks: maxTracks,
    ),
    MusicSource.kw => KwCatalog.detail(
      id,
      artist: artist,
      maxTracks: maxTracks,
    ),
    MusicSource.tx => TxCatalog.detail(
      id,
      artist: artist,
      maxTracks: maxTracks,
    ),
    _ => throw UnsupportedError('${source.label}暂不支持此类详情'),
  };
}
