import 'package:flutter/foundation.dart';

import '../../core/geo.dart';
import '../../model/map_data.dart';
import '../cache/map_cache.dart';
import 'marching_squares.dart';
import 'terrain_tiles.dart';

/// Fetches elevation tiles and turns them into contour lines, cached on device
/// so a Topographic poster restyles and re-exports offline.
class ContourRepository {
  ContourRepository({TerrainTileClient? client, MapCache? cache})
      : _client = client ?? TerrainTileClient(),
        _cache = cache ?? MapCache(folder: 'dem', maxEntries: 30, maxBytes: 40 * 1024 * 1024);

  final TerrainTileClient _client;
  final MapCache _cache;

  Future<List<MapFeature>> load({
    required BBox bbox,
    required MapWindow window,
    double preferredInterval = 10,
    void Function(String status)? onStatus,
  }) async {
    final centre = bbox.center;
    final key = 'c${MapCache.keyFor(centre.lat, centre.lon, window.groundSpanMetres, preferredInterval.round())}';

    final cached = await _cache.read(key);
    if (cached != null) {
      final decoded = MapDataCodec.decode(cached);
      if (decoded != null) return decoded.features;
    }

    onStatus?.call('Reading terrain...');
    final grid = await _client.load(bbox, window);
    final relief = grid.relief;
    final interval = chooseInterval(relief.max - relief.min, preferredInterval);

    onStatus?.call('Tracing contours...');
    final bytes = await compute(
      buildContoursToBytes,
      ContourRequest(
        grid: grid.values,
        width: grid.width,
        height: grid.height,
        originLocalX: grid.originLocalX,
        originLocalY: grid.originLocalY,
        stepLocal: grid.stepLocal,
        interval: interval,
        windowOriginX: window.originX,
        windowOriginY: window.originY,
        windowSpan: window.span,
        south: bbox.south,
        west: bbox.west,
        north: bbox.north,
        east: bbox.east,
      ),
    );

    final decoded = MapDataCodec.decode(bytes);
    if (decoded == null || decoded.features.isEmpty) {
      throw TerrainUnavailable('This area is too flat for contours.');
    }
    await _cache.write(key, bytes);
    return decoded.features;
  }

  Future<int> cacheBytes() => _cache.totalBytes();
  Future<void> clearCache() => _cache.clear();

  void dispose() => _client.close();
}
