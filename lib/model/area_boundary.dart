import 'dart:typed_data';

import '../core/geo.dart';

/// The outline of an administrative area — a neighbourhood, a village, a
/// district — used to lift one place out of the map around it.
class AreaBoundary {
  const AreaBoundary({
    required this.name,
    required this.rings,
  });

  final String name;

  /// One or more closed rings in lat/lon. A multipolygon (an area split by a
  /// river, say) arrives as several rings.
  final List<List<LatLng>> rings;

  bool get isEmpty => rings.isEmpty;

  LatLng get centre {
    var sumLat = 0.0, sumLon = 0.0, count = 0;
    for (final ring in rings) {
      for (final p in ring) {
        sumLat += p.lat;
        sumLon += p.lon;
        count++;
      }
    }
    if (count == 0) return const LatLng(0, 0);
    return LatLng(sumLat / count, sumLon / count);
  }

  BBox get bounds {
    var s = 90.0, w = 180.0, n = -90.0, e = -180.0;
    for (final ring in rings) {
      for (final p in ring) {
        if (p.lat < s) s = p.lat;
        if (p.lat > n) n = p.lat;
        if (p.lon < w) w = p.lon;
        if (p.lon > e) e = p.lon;
      }
    }
    return BBox(s, w, n, e);
  }

  /// Radius in metres that comfortably frames the whole area.
  double get suggestedRadius {
    final b = bounds;
    final height = haversineMetres(LatLng(b.south, b.west), LatLng(b.north, b.west));
    final width = haversineMetres(LatLng(b.south, b.west), LatLng(b.south, b.east));
    return ((height > width ? height : width) / 2 * 1.35).clamp(80.0, 20000.0);
  }

  /// Projected rings in window-local units, ready for a `Path`.
  List<Float32List> project(MapWindow window) {
    final out = <Float32List>[];
    for (final ring in rings) {
      if (ring.length < 3) continue;
      final flat = Float32List(ring.length * 2);
      for (var i = 0; i < ring.length; i++) {
        flat[i * 2] = window.localX(ring[i].lon);
        flat[i * 2 + 1] = window.localY(ring[i].lat);
      }
      out.add(flat);
    }
    return out;
  }

  Map<String, dynamic> toJson() => {
        'n': name,
        'r': rings
            .map((ring) => ring.expand((p) => [p.lat, p.lon]).toList())
            .toList(),
      };

  factory AreaBoundary.fromJson(Map<String, dynamic> j) {
    final rings = <List<LatLng>>[];
    for (final raw in (j['r'] as List? ?? const [])) {
      final flat = (raw as List).map((e) => (e as num).toDouble()).toList();
      final ring = <LatLng>[];
      for (var i = 0; i + 1 < flat.length; i += 2) {
        ring.add(LatLng(flat[i], flat[i + 1]));
      }
      rings.add(ring);
    }
    return AreaBoundary(name: j['n'] as String? ?? '', rings: rings);
  }

  /// Parses the `geojson` field Nominatim returns for a place.
  ///
  /// Only the outer rings are kept: a highlight reads better as one solid
  /// shape than as a shape with holes punched in it.
  static AreaBoundary? fromGeoJson(String name, Object? geometry) {
    if (geometry is! Map) return null;
    final type = geometry['type'];
    final coordinates = geometry['coordinates'];
    final rings = <List<LatLng>>[];

    List<LatLng>? ringOf(Object? raw) {
      if (raw is! List) return null;
      final ring = <LatLng>[];
      for (final pair in raw) {
        if (pair is! List || pair.length < 2) continue;
        final lon = (pair[0] as num).toDouble();
        final lat = (pair[1] as num).toDouble();
        ring.add(LatLng(lat, lon));
      }
      return ring.length >= 3 ? ring : null;
    }

    if (type == 'Polygon' && coordinates is List && coordinates.isNotEmpty) {
      final ring = ringOf(coordinates.first);
      if (ring != null) rings.add(ring);
    } else if (type == 'MultiPolygon' && coordinates is List) {
      for (final polygon in coordinates) {
        if (polygon is! List || polygon.isEmpty) continue;
        final ring = ringOf(polygon.first);
        if (ring != null) rings.add(ring);
      }
    }

    if (rings.isEmpty) return null;
    return AreaBoundary(name: name, rings: rings);
  }
}
