import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/store/design_store.dart';
import '../model/design.dart';
import 'providers.dart';

class LibraryController extends StateNotifier<AsyncValue<List<Design>>> {
  LibraryController(this._store) : super(const AsyncValue.loading()) {
    refresh();
  }

  final DesignStore _store;

  Future<void> refresh() async {
    try {
      state = AsyncValue.data(await _store.loadAll());
    } catch (e, st) {
      state = AsyncValue.error(e, st);
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

  Future<String> thumbnailPath(String fileName) => _store.thumbnailPath(fileName);
}

final libraryControllerProvider =
    StateNotifierProvider<LibraryController, AsyncValue<List<Design>>>(
        (ref) => LibraryController(ref.watch(designStoreProvider)));
