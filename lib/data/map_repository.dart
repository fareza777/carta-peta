import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/geo.dart';
import '../model/map_data.dart';
import 'cache/map_cache.dart';
import 'dem/contour_repository.dart';
import 'osm/osm_parser.dart';
import 'osm/overpass_client.dart';
import 'osm/overpass_query.dart';

class MapLoadResult {
  final MapDataSet data;
  final bool fromCache;
  final DetailLevel detail;
  const MapLoadResult(this.data, this.fromCache, this.detail);
}

/// Fetches, parses and caches OpenStreetMap geometry for a poster window.
class MapRepository {
  MapRepository({OverpassClient? client, MapCache? cache, ContourRepository? contours})
      : _client = client ?? OverpassClient(),
        _cache = cache ?? MapCache(),
        _contours = contours ?? ContourRepository();

  final OverpassClient _client;
  final MapCache _cache;
  final ContourRepository _contours;

  /// Extra breathing room around the requested square so the poster can be
  /// zoomed out slightly or re-cropped without another download.
  static const double _margin = 1.18;

  Future<MapLoadResult> load({
    required LatLng centre,
    required double radiusMetres,
    bool forceRefresh = false,
    void Function(String status)? onStatus,
  }) async {
    final detail = detailForRadius(radiusMetres);
    final key = MapCache.keyFor(centre.lat, centre.lon, radiusMetres, detail.index);

    if (!forceRefresh) {
      onStatus?.call('Checking offline cache...');
      final cached = await _cache.read(key);
      if (cached != null) {
        final decoded = MapDataCodec.decode(cached);
        if (decoded != null && decoded.features.isNotEmpty) {
          return MapLoadResult(decoded, true, detail);
        }
      }
    }

    final square = BBox.square(centre, radiusMetres);
    final fetchBox = square.inflated(_margin);
    final query = buildOverpassQuery(fetchBox, detail);

    final body = await _client.fetch(query, onStatus: onStatus);

    onStatus?.call('Building artwork layers...');
    final bytes = await compute(
      parseOverpassToBytes,
      OsmParseRequest(
        json: body,
        south: square.south,
        west: square.west,
        north: square.north,
        east: square.east,
      ),
    );

    final data = MapDataCodec.decode(bytes);
    if (data == null || data.features.isEmpty) {
      throw OverpassFailure(
          'No map features here. Try a bigger radius or a different spot.');
    }
    unawaited(_cache.write(key, bytes));
    return MapLoadResult(data, false, detail);
  }

  /// Adds terrain contours to an already-loaded dataset. Kept separate from
  /// [load] so people who never pick a topographic look never pay for the
  /// elevation download.
  Future<MapDataSet> withContours(
    MapDataSet data, {
    double interval = 10,
    void Function(String status)? onStatus,
  }) async {
    if (data.hasContours) return data;
    final features = await _contours.load(
      bbox: data.bbox,
      window: data.window,
      preferredInterval: interval,
      onStatus: onStatus,
    );
    if (features.isEmpty) return data;
    return data.withExtra(features);
  }

  Future<int> cacheBytes() async =>
      (await _cache.totalBytes()) + (await _contours.cacheBytes());

  Future<int> cacheEntries() => _cache.entryCount();

  Future<void> clearCache() async {
    await _cache.clear();
    await _contours.clearCache();
  }

  void dispose() {
    _client.close();
    _contours.dispose();
  }
}
