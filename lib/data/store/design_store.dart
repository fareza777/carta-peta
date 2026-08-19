import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../../model/design.dart';

/// Local library of saved artworks. Everything lives in the app's documents
/// directory as one JSON index plus one PNG thumbnail per design.
class DesignStore {
  static const _indexName = 'library.json';

  Directory? _root;

  Future<Directory> _dir() async {
    if (_root != null) return _root!;
    final base = await getApplicationDocumentsDirectory();
    final d = Directory('${base.path}${Platform.pathSeparator}carta');
    if (!await d.exists()) await d.create(recursive: true);
    final t = Directory('${d.path}${Platform.pathSeparator}thumbs');
    if (!await t.exists()) await t.create(recursive: true);
    _root = d;
    return d;
  }

  Future<File> _index() async =>
      File('${(await _dir()).path}${Platform.pathSeparator}$_indexName');

  /// Directory that holds thumbnails, with a trailing separator so callers can
  /// build a path without another async hop.
  Future<String> thumbnailDirectory() async =>
      '${(await _dir()).path}${Platform.pathSeparator}thumbs${Platform.pathSeparator}';

  Future<String> thumbnailPath(String fileName) async =>
      '${await thumbnailDirectory()}$fileName';

  Future<List<Design>> loadAll() async {
    try {
      final f = await _index();
      if (!await f.exists()) return [];
      final raw = jsonDecode(await f.readAsString());
      if (raw is! List) return [];
      final out = <Design>[];
      for (final e in raw) {
        try {
          out.add(Design.fromJson(Map<String, dynamic>.from(e as Map)));
        } catch (_) {
          // skip malformed entries rather than losing the whole library
        }
      }
      out.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return out;
    } catch (_) {
      return [];
    }
  }

  Future<void> _writeAll(List<Design> designs) async {
    final f = await _index();
    await f.writeAsString(jsonEncode(designs.map((d) => d.toJson()).toList()), flush: true);
  }

  /// Inserts or replaces [design]; returns the stored copy.
  Future<Design> save(Design design, {Uint8List? thumbnail}) async {
    final all = await loadAll();
    var stored = design;
    if (thumbnail != null) {
      final name = '${design.id}.png';
      final file = File(await thumbnailPath(name));
      await file.writeAsBytes(thumbnail, flush: true);
      stored = design.copyWith(thumbnail: name, updatedAt: DateTime.now());
    } else {
      stored = design.copyWith(updatedAt: DateTime.now());
    }
    final idx = all.indexWhere((d) => d.id == design.id);
    if (idx >= 0) {
      all[idx] = stored;
    } else {
      all.insert(0, stored);
    }
    await _writeAll(all);
    return stored;
  }

  Future<void> delete(String id) async {
    final all = await loadAll();
    final target = all.where((d) => d.id == id).firstOrNull;
    all.removeWhere((d) => d.id == id);
    await _writeAll(all);
    if (target?.thumbnail != null) {
      try {
        await File(await thumbnailPath(target!.thumbnail!)).delete();
      } catch (_) {
        // ignore
      }
    }
  }

  Future<void> rename(String id, String title) async {
    final all = await loadAll();
    final idx = all.indexWhere((d) => d.id == id);
    if (idx < 0) return;
    all[idx] = all[idx].copyWith(
      poster: all[idx].poster.copyWith(title: title.trim()),
    );
    await _writeAll(all);
  }

  /// Copies a design, thumbnail included, under a fresh id.
  Future<Design?> duplicate(String id) async {
    final all = await loadAll();
    final source = all.where((d) => d.id == id).firstOrNull;
    if (source == null) return null;
    final now = DateTime.now();
    final newId = 'd${now.microsecondsSinceEpoch.toRadixString(36)}';
    String? thumb;
    if (source.thumbnail != null) {
      try {
        final from = File(await thumbnailPath(source.thumbnail!));
        if (await from.exists()) {
          thumb = '$newId.png';
          await from.copy(await thumbnailPath(thumb));
        }
      } catch (_) {
        thumb = null;
      }
    }
    final copy = Design(
      id: newId,
      place: source.place,
      radiusMetres: source.radiusMetres,
      style: source.style,
      poster: source.poster.copyWith(
        title: '${LibraryNaming.of(source)} copy',
      ),
      formatId: source.formatId,
      route: source.route,
      zoom: source.zoom,
      favorite: false,
      createdAt: now,
      updatedAt: now,
      thumbnail: thumb,
    );
    all.insert(0, copy);
    await _writeAll(all);
    return copy;
  }

  Future<Design?> toggleFavorite(String id) async {
    final all = await loadAll();
    final idx = all.indexWhere((d) => d.id == id);
    if (idx < 0) return null;
    final next = all[idx].copyWith(favorite: !all[idx].favorite);
    all[idx] = next;
    await _writeAll(all);
    return next;
  }
}

/// How a design is labelled in the library: an explicit poster title if the
/// user set one, otherwise the place it was made from.
class LibraryNaming {
  static String of(Design d) =>
      d.poster.title.trim().isNotEmpty ? d.poster.title.trim() : d.place.name;
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
