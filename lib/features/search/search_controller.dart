import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/dio_factory.dart';
import '../../core/api/music_api.dart';
import '../../core/models/enums.dart';
import '../../core/models/search_response.dart';
import '../../core/models/search_category.dart';
import '../../core/services/app_logger.dart';
import '../../core/storage/settings_store.dart';
import '../discovery/discovery_controller.dart';

class SearchQuery {
  const SearchQuery({
    required this.keyword,
    required this.source,
    required this.page,
    this.category = SearchCategory.all,
  });

  final String keyword;
  final MusicSource source;
  final int page;
  final SearchCategory category;

  SearchQuery copyWith({
    String? keyword,
    MusicSource? source,
    int? page,
    SearchCategory? category,
  }) => SearchQuery(
    keyword: keyword ?? this.keyword,
    source: source ?? this.source,
    page: page ?? this.page,
    category: category ?? this.category,
  );

  @override
  bool operator ==(Object other) =>
      other is SearchQuery &&
      other.keyword == keyword &&
      other.source == source &&
      other.page == page &&
      other.category == category;

  @override
  int get hashCode => Object.hash(keyword, source, page, category);
}

class SearchState {
  const SearchState({
    this.keyword = '',
    this.category = SearchCategory.all,
    this.source = MusicSource.all,
    this.page = 1,
    this.loading = false,
    this.error,
    this.response,
    this.searchActive = false,
  });

  final String keyword;
  final SearchCategory category;
  final MusicSource source;
  final int page;
  final bool loading;
  final String? error;
  final SearchResponse? response;
  final bool searchActive;

  bool get isSearchActive =>
      searchActive || loading || response != null || keyword.trim().isNotEmpty;

  SearchState copyWith({
    SearchCategory? category,
    String? keyword,
    MusicSource? source,
    int? page,
    bool? loading,
    Object? error = _sentinel,
    Object? response = _sentinel,
    bool? searchActive,
  }) => SearchState(
    category: category ?? this.category,
    keyword: keyword ?? this.keyword,
    source: source ?? this.source,
    page: page ?? this.page,
    loading: loading ?? this.loading,
    error: identical(error, _sentinel) ? this.error : error as String?,
    response: identical(response, _sentinel)
        ? this.response
        : response as SearchResponse?,
    searchActive: searchActive ?? this.searchActive,
  );

  static const _sentinel = Object();
}

class SearchController extends Notifier<SearchState> {
  Object? _activeRequest;
  final Map<SearchQuery, SearchResponse> _responseCache =
      <SearchQuery, SearchResponse>{};
  int _settingsRevision = 0;
  final Map<SearchCategory, int> _categoryPages = {};
  final Map<SearchQuery, Future<SearchResponse>> _inFlight =
      <SearchQuery, Future<SearchResponse>>{};

  @override
  SearchState build() {
    ref.onDispose(() {
      _activeRequest = null;
      _settingsRevision++;
      _responseCache.clear();
      _inFlight.clear();
    });
    ref.listen<Set<MusicSource>>(
      settingsProvider.select((settings) => settings.enabledSearchSources),
      (previous, next) {
        _activeRequest = Object();
        _settingsRevision++;
        _categoryPages.clear();
        _inFlight.clear();
        _responseCache.removeWhere(
          (query, _) =>
              query.source == MusicSource.all ||
              (query.source != MusicSource.all && !next.contains(query.source)),
        );
        final activeSource = state.isSearchActive
            ? _sourceEnabled(state.source, next)
                  ? state.source
                  : _defaultSearchSource(next)
            : _defaultSearchSource(next);
        final keyword = state.keyword;
        state = state.copyWith(
          source: activeSource,
          page: 1,
          loading: false,
          error: null,
          response: null,
        );
        if (keyword.trim().isNotEmpty) {
          unawaited(search(keyword: keyword, source: activeSource));
        }
      },
    );
    ref.listen<MusicSource>(selectedDiscoverySourceProvider, (previous, next) {
      if (state.isSearchActive) return;
      final source = _defaultSearchSource();
      if (state.source == source) return;
      state = state.copyWith(source: source);
    });
    ref.listen<List<MusicSource>>(
      settingsProvider.select((settings) => settings.discoverySourceOrder),
      (previous, next) {
        if (state.source == MusicSource.all) _activeRequest = Object();
        _settingsRevision++;
        _categoryPages.clear();
        _inFlight.clear();
        _responseCache.removeWhere(
          (query, _) => query.source == MusicSource.all,
        );
        if (state.isSearchActive &&
            state.source == MusicSource.all &&
            state.keyword.trim().isNotEmpty) {
          unawaited(search(keyword: state.keyword, source: MusicSource.all));
        }
      },
    );
    return SearchState(source: _defaultSearchSource());
  }

  void setSource(MusicSource source) {
    final enabled = ref.read(settingsProvider).enabledSearchSources;
    if (source != MusicSource.all && !enabled.contains(source)) return;
    if (source == state.source) return;
    _categoryPages.clear();
    state = state.copyWith(source: source);
    if (state.keyword.trim().isNotEmpty) {
      search(keyword: state.keyword, source: source, page: 1);
    }
  }

  void setCategory(SearchCategory category) {
    if (category == state.category) return;
    _categoryPages[state.category] = state.page;
    final page = _categoryPages[category] ?? 1;
    state = state.copyWith(
      category: category,
      page: page,
      response: null,
      error: null,
    );
    if (state.keyword.isNotEmpty) {
      unawaited(search(keyword: state.keyword, page: page));
    }
  }

  Future<void> search({
    required String keyword,
    MusicSource? source,
    int page = 1,
  }) async {
    final cleaned = keyword.trim();
    if (cleaned.isEmpty) {
      state = state.copyWith(error: '请输入歌名、歌手或专辑');
      return;
    }

    final activeSource = source ?? state.source;
    if (cleaned != state.keyword || activeSource != state.source) {
      _categoryPages.clear();
    }
    final revision = _settingsRevision;
    final query = SearchQuery(
      keyword: cleaned,
      source: activeSource,
      page: page,
      category: state.category,
    );

    // Identity-only marker: the underlying SDK fan-out doesn't accept a
    // CancelToken, so we just stamp each call with a fresh Object() and
    // discard the result if a newer call has started since.
    final request = Object();
    _activeRequest = request;

    state = state.copyWith(
      keyword: cleaned,
      source: activeSource,
      page: page,
      loading: false,
      error: null,
      searchActive: true,
      response: null,
    );

    final cached = _responseCache[query];
    if (cached != null) {
      state = state.copyWith(response: cached);
      return;
    }

    state = state.copyWith(loading: true);
    final existing = _inFlight[query];
    final future =
        existing ??
        Future<SearchResponse>.sync(
          () => ref
              .read(musicApiProvider)
              .searchContent(
                keyword: cleaned,
                source: activeSource,
                category: query.category,
                page: page,
              ),
        );
    if (existing == null) {
      _inFlight[query] = future;
    }
    unawaited(
      AppLogger.write(
        'search',
        '${existing == null ? 'START' : 'JOIN'} keyword="$cleaned" '
            'source=${activeSource.code} page=$page '
            'adapter=${currentNetworkAdapterLabel()}',
      ),
    );
    try {
      final result = await future;
      // Catalog failures are returned as notices, not thrown. Keep them
      // retryable when a user switches categories or submits the query again.
      if (revision == _settingsRevision && result.notices.isEmpty) {
        if (_responseCache.length >= 48) {
          _responseCache.remove(_responseCache.keys.first);
        }
        _responseCache[query] = result;
      }
      if (!identical(request, _activeRequest)) return;
      unawaited(
        AppLogger.write(
          'search',
          'OK keyword="$cleaned" source=${activeSource.code} '
              'page=$page count=${result.list.length}',
        ),
      );
      state = state.copyWith(loading: false, response: result, error: null);
    } on DioException catch (e) {
      if (!identical(request, _activeRequest)) return;
      unawaited(
        AppLogger.write(
          'search',
          'FAIL keyword="$cleaned" source=${activeSource.code} '
              'page=$page error=$e',
        ),
      );
      state = state.copyWith(loading: false, error: describeDioError(e));
    } catch (e) {
      if (!identical(request, _activeRequest)) return;
      unawaited(
        AppLogger.write(
          'search',
          'FAIL keyword="$cleaned" source=${activeSource.code} '
              'page=$page error=$e',
        ),
      );
      state = state.copyWith(loading: false, error: e.toString());
    } finally {
      if (existing == null && identical(_inFlight[query], future)) {
        _inFlight.remove(query);
      }
    }
  }

  void retry() {
    _responseCache.remove(
      SearchQuery(
        keyword: state.keyword,
        source: state.source,
        page: state.page,
        category: state.category,
      ),
    );
    unawaited(search(keyword: state.keyword, page: state.page));
  }

  void clearError() {
    if (state.error != null) state = state.copyWith(error: null);
  }

  void resetToDiscovery() {
    _categoryPages.clear();
    _activeRequest = Object();
    state = SearchState(source: _defaultSearchSource());
  }

  bool _sourceEnabled(MusicSource source, Set<MusicSource> enabled) =>
      source == MusicSource.all || enabled.contains(source);

  MusicSource _defaultSearchSource([Set<MusicSource>? enabledSources]) {
    final enabled =
        enabledSources ?? ref.read(settingsProvider).enabledSearchSources;
    final discoverySource = ref.read(selectedDiscoverySourceProvider);
    return enabled.contains(discoverySource)
        ? discoverySource
        : MusicSource.all;
  }
}

final searchControllerProvider =
    NotifierProvider<SearchController, SearchState>(SearchController.new);
