import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/osm/nominatim_client.dart';
import '../data/store/prefs_store.dart';
import '../model/place.dart';
import 'providers.dart';

class SearchState {
  final String query;
  final bool loading;
  final List<PlaceRef> results;
  final List<PlaceRef> recent;
  final String? error;

  const SearchState({
    this.query = '',
    this.loading = false,
    this.results = const [],
    this.recent = const [],
    this.error,
  });

  SearchState copyWith({
    String? query,
    bool? loading,
    List<PlaceRef>? results,
    List<PlaceRef>? recent,
    String? error,
    bool clearError = false,
  }) =>
      SearchState(
        query: query ?? this.query,
        loading: loading ?? this.loading,
        results: results ?? this.results,
        recent: recent ?? this.recent,
        error: clearError ? null : (error ?? this.error),
      );
}

class SearchController extends StateNotifier<SearchState> {
  SearchController(this._client, this._prefs) : super(const SearchState()) {
    _loadRecent();
  }

  final NominatimClient _client;
  final PrefsStore _prefs;
  Timer? _debounce;
  int _seq = 0;

  Future<void> _loadRecent() async {
    final recent = await _prefs.recentPlaces();
    if (mounted) state = state.copyWith(recent: recent);
  }

  void onQueryChanged(String q) {
    state = state.copyWith(query: q, clearError: true);
    _debounce?.cancel();
    if (q.trim().length < 2) {
      state = state.copyWith(results: const [], loading: false);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 420), () => _run(q));
  }

  Future<void> submit() async {
    _debounce?.cancel();
    await _run(state.query);
  }

  Future<void> _run(String q) async {
    final id = ++_seq;
    state = state.copyWith(loading: true, clearError: true);
    try {
      final results = await _client.search(q);
      if (!mounted || id != _seq) return;
      state = state.copyWith(
        loading: false,
        results: results,
        error: results.isEmpty ? 'Nothing found for "${q.trim()}"' : null,
        clearError: results.isNotEmpty,
      );
    } catch (e) {
      if (!mounted || id != _seq) return;
      state = state.copyWith(loading: false, error: '$e');
    }
  }

  Future<void> remember(PlaceRef place) async {
    await _prefs.pushRecent(place);
    await _loadRecent();
  }

  void clear() {
    _debounce?.cancel();
    state = state.copyWith(query: '', results: const [], loading: false, clearError: true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}

final searchControllerProvider =
    StateNotifierProvider<SearchController, SearchState>((ref) => SearchController(
          ref.watch(nominatimProvider),
          ref.watch(prefsStoreProvider),
        ));
