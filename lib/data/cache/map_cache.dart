import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// On-device store of parsed captures so restyling and re-exporting a place
/// never needs the network again.
class MapCache {
  MapCache({this.folder = 'osm', this.maxEntries = 60, this.maxBytes = 220 * 1024 * 1024});

  final String folder;
  final int maxEntries;
  final int maxBytes;

  Directory? _dir;

  Future<Directory> _directory() async {
    if (_dir != null) return _dir!;
    final base = await getApplicationSupportDirectory();
    final d = Directory('${base.path}${Platform.pathSeparator}$folder');
    if (!await d.exists()) await d.create(recursive: true);
    _dir = d;
    return d;
  }

  static String keyFor(double lat, double lon, double radius, int detail) {
    final la = lat.toStringAsFixed(5).replaceAll('-', 'm').replaceAll('.', '');
    final lo = lon.toStringAsFixed(5).replaceAll('-', 'm').replaceAll('.', '');
    return '${la}_${lo}_${radius.round()}_$detail';
  }

  Future<File> _file(String key) async =>
      File('${(await _directory()).path}${Platform.pathSeparator}$key.carta');

  Future<Uint8List?> read(String key) async {
    try {
      final f = await _file(key);
      if (!await f.exists()) return null;
      return await f.readAsBytes();
    } catch (_) {
      return null;
    }
  }

  Future<void> write(String key, Uint8List bytes) async {
    try {
      final f = await _file(key);
      await f.writeAsBytes(bytes, flush: true);
      await prune();
    } catch (_) {
      // A failed cache write must never break rendering.
    }
  }

  Future<List<File>> _entries() async {
    final d = await _directory();
    final files = <File>[];
    await for (final e in d.list()) {
      if (e is File && e.path.endsWith('.carta')) files.add(e);
    }
    return files;
  }

  Future<int> totalBytes() async {
    try {
      var sum = 0;
      for (final f in await _entries()) {
        sum += await f.length();
      }
      return sum;
    } catch (_) {
      return 0;
    }
  }

  Future<int> entryCount() async {
    try {
      return (await _entries()).length;
    } catch (_) {
      return 0;
    }
  }

  Future<void> prune() async {
    try {
      final files = await _entries();
      if (files.length <= maxEntries) {
        var sum = 0;
        for (final f in files) {
          sum += await f.length();
        }
        if (sum <= maxBytes) return;
      }
      final stamped = <MapEntry<File, DateTime>>[];
      for (final f in files) {
        stamped.add(MapEntry(f, (await f.stat()).modified));
      }
      stamped.sort((a, b) => b.value.compareTo(a.value));
      var kept = 0;
      var bytes = 0;
      for (final e in stamped) {
        final len = await e.key.length();
        kept++;
        bytes += len;
        if (kept > maxEntries || bytes > maxBytes) {
          await e.key.delete();
        }
      }
    } catch (_) {
      // ignore
    }
  }

  Future<void> clear() async {
    try {
      for (final f in await _entries()) {
        await f.delete();
      }
    } catch (_) {
      // ignore
    }
  }
}
