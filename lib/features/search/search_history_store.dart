import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/settings_store.dart';

const _searchHistoryStorageKey = 'search_history_v1';
const _searchHistoryLimit = 20;

class SearchHistoryNotifier extends Notifier<List<String>> {
  late final _prefs = ref.read(sharedPreferencesProvider);

  @override
  List<String> build() {
    final seen = <String>{};
    final saved = _prefs.getStringList(_searchHistoryStorageKey) ?? const [];
    return List<String>.unmodifiable(
      saved
          .map((keyword) => keyword.trim())
          .where((keyword) => keyword.isNotEmpty && seen.add(keyword))
          .take(_searchHistoryLimit),
    );
  }

  void add(String keyword) {
    final cleaned = keyword.trim();
    if (cleaned.isEmpty || state.firstOrNull == cleaned) return;
    _save(
      [
        cleaned,
        ...state.where((entry) => entry != cleaned),
      ].take(_searchHistoryLimit),
    );
  }

  void remove(String keyword) {
    _save(state.where((entry) => entry != keyword));
  }

  void clear() {
    _save(const []);
  }

  void _save(Iterable<String> entries) {
    state = List<String>.unmodifiable(entries);
    unawaited(_prefs.setStringList(_searchHistoryStorageKey, state));
  }
}

final searchHistoryProvider =
    NotifierProvider<SearchHistoryNotifier, List<String>>(
      SearchHistoryNotifier.new,
    );
