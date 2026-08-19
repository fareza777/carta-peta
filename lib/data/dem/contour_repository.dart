import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../../core/geo.dart';
import '../../model/map_data.dart';
import '../../model/terrain_relief.dart';
import '../cache/map_cache.dart';
import 'marching_squares.dart';
import 'terrain_tiles.dart';

class TerrainResult {
  const TerrainResult(this.contours, this.relief);
  final List<MapFeature> contours;
  final TerrainRelief? relief;
}

/// Fetches elevation tiles and turns them into contour lines and a shaded
/// relief raster, cached on device so a topographic poster restyles and
/// re-exports offline.
class ContourRepository {
  ContourRepository({TerrainTileClient? client, MapCache? cache})
      : _client = client ?? TerrainTileClient(),
        _cache = cache ??
            MapCache(folder: 'dem', maxEntries: 30, maxBytes: 60 * 1024 * 1024);

  final TerrainTileClient _client;
  final MapCache _cache;

  Future<TerrainResult> load({
    required BBox bbox,
    required MapWindow window,
    double preferredInterval = 10,
    void Function(String status)? onStatus,
  }) async {
    final centre = bbox.center;
    final key = 'c${MapCache.keyFor(
      centre.lat,
      centre.lon,
      window.groundSpanMetres,
      preferredInterval.round(),
    )}';

    final cached = await _cache.read(key);
    if (cached != null) {
      final decoded = MapDataCodec.decode(cached);
      if (decoded != null) {
        final relief = await _readRelief('${key}_r');
        return TerrainResult(decoded.features, relief);
      }
    }

    onStatus?.call('Reading terrain...');
    final grid = await _client.load(bbox, window);
    final relief = grid.relief;
    final interval = chooseInterval(relief.max - relief.min, preferredInterval);
    final metresPerSample =
        window.groundSpanMetres * grid.stepLocal.abs().clamp(1e-9, 1);

    onStatus?.call('Tracing contours...');
    final result = await compute(
      buildTerrainToBytes,
      ContourRequest(
        grid: grid.values,
        width: grid.width,
        height: grid.height,
        originLocalX: grid.originLocalX,
        originLocalY: grid.originLocalY,
        stepLocal: grid.stepLocal,
        interval: interval,
        metresPerSample: metresPerSample,
        windowOriginX: window.originX,
        windowOriginY: window.originY,
        windowSpan: window.span,
        south: bbox.south,
        west: bbox.west,
        north: bbox.north,
        east: bbox.east,
      ),
    );

    final bytes = result['contours'] as Uint8List;
    final decoded = MapDataCodec.decode(bytes);
    if (decoded == null || decoded.features.isEmpty) {
      throw TerrainUnavailable('This area is too flat for contours.');
    }

    final shade = result['shade'] as Uint8List;
    final w = result['w'] as int;
    final h = result['h'] as int;
    unawaited(_cache.write(key, bytes));
    unawaited(_writeRelief(
      '${key}_r',
      shade,
      w,
      h,
      grid.originLocalX,
      grid.originLocalY,
      grid.stepLocal,
    ));

    final image = await _decode(shade, w, h);
    return TerrainResult(
      decoded.features,
      TerrainRelief(
        image: image,
        originLocalX: grid.originLocalX,
        originLocalY: grid.originLocalY,
        stepLocal: grid.stepLocal,
      ),
    );
  }

  static Future<ui.Image> _decode(Uint8List rgba, int w, int h) {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(rgba, w, h, ui.PixelFormat.rgba8888, completer.complete);
    return completer.future;
  }

  // Relief raster is stored raw: a tiny header plus one grey byte per sample.
  static const int _reliefMagic = 0x524C4631; // 'RLF1'

  Future<void> _writeRelief(
    String key,
    Uint8List rgba,
    int w,
    int h,
    double ox,
    double oy,
    double step,
  ) async {
    final header = ByteData(4 + 4 + 4 + 8 * 3);
    header.setUint32(0, _reliefMagic);
    header.setUint32(4, w);
    header.setUint32(8, h);
    header.setFloat64(12, ox);
    header.setFloat64(20, oy);
    header.setFloat64(28, step);
    final grey = Uint8List(w * h);
    for (var i = 0; i < grey.length; i++) {
      grey[i] = rgba[i * 4];
    }
    final out = Uint8List(header.lengthInBytes + grey.length)
      ..setRange(0, header.lengthInBytes, header.buffer.asUint8List())
      ..setRange(header.lengthInBytes, header.lengthInBytes + grey.length, grey);
    await _cache.write(key, out);
  }

  Future<TerrainRelief?> _readRelief(String key) async {
    try {
      final raw = await _cache.read(key);
      if (raw == null || raw.length < 36) return null;
      final head = ByteData.sublistView(raw, 0, 36);
      if (head.getUint32(0) != _reliefMagic) return null;
      final w = head.getUint32(4);
      final h = head.getUint32(8);
      if (raw.length < 36 + w * h) return null;
      final rgba = Uint8List(w * h * 4);
      for (var i = 0; i < w * h; i++) {
        final v = raw[36 + i];
        rgba[i * 4] = v;
        rgba[i * 4 + 1] = v;
        rgba[i * 4 + 2] = v;
        rgba[i * 4 + 3] = 255;
      }
      return TerrainRelief(
        image: await _decode(rgba, w, h),
        originLocalX: head.getFloat64(12),
        originLocalY: head.getFloat64(20),
        stepLocal: head.getFloat64(28),
      );
    } catch (_) {
      return null;
    }
  }

  Future<int> cacheBytes() => _cache.totalBytes();
  Future<void> clearCache() => _cache.clear();

  void dispose() => _client.close();
}
