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

  Future<String> thumbnailPath(String fileName) async =>
      '${(await _dir()).path}${Platform.pathSeparator}thumbs${Platform.pathSeparator}$fileName';

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

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
