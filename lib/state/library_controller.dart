import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/store/design_store.dart';
import '../model/design.dart';
import 'providers.dart';

enum LibrarySort { recent, oldest, name }

class LibraryState {
  const LibraryState({
    this.designs = const [],
    this.thumbDir,
    this.loading = true,
    this.error,
    this.favouritesOnly = false,
    this.sort = LibrarySort.recent,
  });

  final List<Design> designs;

  /// Resolved once per refresh so the grid never touches the platform channel
  /// or the filesystem while it is building.
  final String? thumbDir;
  final bool loading;
  final String? error;
  final bool favouritesOnly;
  final LibrarySort sort;

  int get favouriteCount => designs.where((d) => d.favorite).length;

  List<Design> get visible {
    final list = designs.where((d) => !favouritesOnly || d.favorite).toList();
    switch (sort) {
      case LibrarySort.recent:
        list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      case LibrarySort.oldest:
        list.sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
      case LibrarySort.name:
        list.sort((a, b) =>
            displayName(a).toLowerCase().compareTo(displayName(b).toLowerCase()));
    }
    return list;
  }

  static String displayName(Design d) =>
      d.poster.title.trim().isNotEmpty ? d.poster.title.trim() : d.place.name;

  String? thumbPathOf(Design d) {
    final dir = thumbDir;
    final name = d.thumbnail;
    if (dir == null || name == null) return null;
    return '$dir$name';
  }

  LibraryState copyWith({
    List<Design>? designs,
    String? thumbDir,
    bool? loading,
    String? error,
    bool clearError = false,
    bool? favouritesOnly,
    LibrarySort? sort,
  }) =>
      LibraryState(
        designs: designs ?? this.designs,
        thumbDir: thumbDir ?? this.thumbDir,
        loading: loading ?? this.loading,
        error: clearError ? null : (error ?? this.error),
        favouritesOnly: favouritesOnly ?? this.favouritesOnly,
        sort: sort ?? this.sort,
      );
}

class LibraryController extends StateNotifier<LibraryState> {
  LibraryController(this._store) : super(const LibraryState()) {
    refresh();
  }

  final DesignStore _store;

  Future<void> refresh() async {
    try {
      final designs = await _store.loadAll();
      final dir = await _store.thumbnailDirectory();
      if (!mounted) return;
      state = state.copyWith(
        designs: designs,
        thumbDir: dir,
        loading: false,
        clearError: true,
      );
    } catch (e) {
      if (mounted) state = state.copyWith(loading: false, error: '$e');
    }
  }

  Future<Design> save(Design design, {Uint8List? thumbnail}) async {
    final stored = await _store.save(design, thumbnail: thumbnail);
    await refresh();
    return stored;
  }

  Future<void> delete(String id) async {
    await _store.delete(id);
    await refresh();
  }

  Future<void> toggleFavorite(String id) async {
    await _store.toggleFavorite(id);
    await refresh();
  }

  Future<void> rename(String id, String title) async {
    await _store.rename(id, title);
    await refresh();
  }

  Future<void> duplicate(String id) async {
    await _store.duplicate(id);
    await refresh();
  }

  void setFavouritesOnly(bool value) =>
      state = state.copyWith(favouritesOnly: value);

  void setSort(LibrarySort sort) => state = state.copyWith(sort: sort);
}

final libraryControllerProvider =
    StateNotifierProvider<LibraryController, LibraryState>(
        (ref) => LibraryController(ref.watch(designStoreProvider)));
