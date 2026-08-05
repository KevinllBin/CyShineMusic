import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/dio_factory.dart';
import '../../core/api/music_api.dart';
import '../../core/models/enums.dart';
import '../../core/models/search_response.dart';
import '../../core/services/app_logger.dart';
import '../../core/storage/settings_store.dart';

class SearchQuery {
  const SearchQuery({
    required this.keyword,
    required this.source,
    required this.page,
  });

  final String keyword;
  final MusicSource source;
  final int page;

  SearchQuery copyWith({String? keyword, MusicSource? source, int? page}) =>
      SearchQuery(
        keyword: keyword ?? this.keyword,
        source: source ?? this.source,
        page: page ?? this.page,
      );
}

class SearchState {
  const SearchState({
    this.keyword = '',
    this.source = MusicSource.all,
    this.page = 1,
    this.loading = false,
    this.error,
    this.response,
    this.searchActive = false,
  });

  final String keyword;
  final MusicSource source;
  final int page;
  final bool loading;
  final String? error;
  final SearchResponse? response;
  final bool searchActive;

  bool get isSearchActive =>
      searchActive || loading || response != null || keyword.trim().isNotEmpty;

  SearchState copyWith({
    String? keyword,
    MusicSource? source,
    int? page,
    bool? loading,
    Object? error = _sentinel,
    Object? response = _sentinel,
    bool? searchActive,
  }) => SearchState(
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

  @override
  SearchState build() {
    ref.onDispose(() => _activeRequest = null);
    ref.listen<Set<MusicSource>>(
      settingsProvider.select((settings) => settings.enabledSearchSources),
      (previous, next) {
        _activeRequest = Object();
        final activeSource =
            state.source != MusicSource.all && !next.contains(state.source)
            ? MusicSource.all
            : state.source;
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
    return const SearchState();
  }

  void setSource(MusicSource source) {
    final enabled = ref.read(settingsProvider).enabledSearchSources;
    if (source != MusicSource.all && !enabled.contains(source)) return;
    if (source == state.source) return;
    state = state.copyWith(source: source);
    if (state.keyword.trim().isNotEmpty) {
      search(keyword: state.keyword, source: source, page: 1);
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

    // Identity-only marker: the underlying SDK fan-out doesn't accept a
    // CancelToken, so we just stamp each call with a fresh Object() and
    // discard the result if a newer call has started since.
    final request = Object();
    _activeRequest = request;

    state = state.copyWith(
      keyword: cleaned,
      source: source ?? state.source,
      page: page,
      loading: true,
      error: null,
      searchActive: true,
    );

    final activeSource = source ?? state.source;
    await AppLogger.write(
      'search',
      'START keyword="$cleaned" source=${activeSource.code} page=$page '
          'adapter=${currentNetworkAdapterLabel()}',
    );
    try {
      final api = ref.read(musicApiProvider);
      final result = await api.searchMusic(
        keyword: cleaned,
        source: activeSource,
        page: page,
      );
      if (!identical(request, _activeRequest)) return;
      await AppLogger.write(
        'search',
        'OK keyword="$cleaned" source=${activeSource.code} '
            'page=$page count=${result.list.length}',
      );
      state = state.copyWith(loading: false, response: result, error: null);
    } on DioException catch (e) {
      if (!identical(request, _activeRequest)) return;
      await AppLogger.write(
        'search',
        'FAIL keyword="$cleaned" source=${activeSource.code} '
            'page=$page error=$e',
      );
      state = state.copyWith(loading: false, error: describeDioError(e));
    } catch (e) {
      if (!identical(request, _activeRequest)) return;
      await AppLogger.write(
        'search',
        'FAIL keyword="$cleaned" source=${activeSource.code} '
            'page=$page error=$e',
      );
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  void clearError() {
    if (state.error != null) state = state.copyWith(error: null);
  }

  void resetToDiscovery() {
    _activeRequest = Object();
    state = SearchState(source: state.source);
  }
}

final searchControllerProvider =
    NotifierProvider<SearchController, SearchState>(SearchController.new);
