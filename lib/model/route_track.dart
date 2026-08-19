import 'dart:typed_data';

import '../core/geo.dart';

/// An imported GPX activity drawn on top of the map.
class RouteTrack {
  final String name;
  final List<LatLng> points;
  final double distanceMetres;
  final double ascentMetres;
  final Duration? duration;
  final DateTime? recordedAt;

  /// Downsampled elevation series, used to draw the profile on the poster.
  /// Empty when the GPX carried no elevation.
  final List<double> elevations;

  const RouteTrack({
    required this.name,
    required this.points,
    required this.distanceMetres,
    this.ascentMetres = 0,
    this.duration,
    this.recordedAt,
    this.elevations = const [],
  });

  bool get hasProfile => elevations.length > 4;

  bool get isEmpty => points.length < 2;

  BBox get bounds {
    var s = 90.0, w = 180.0, n = -90.0, e = -180.0;
    for (final p in points) {
      if (p.lat < s) s = p.lat;
      if (p.lat > n) n = p.lat;
      if (p.lon < w) w = p.lon;
      if (p.lon > e) e = p.lon;
    }
    return BBox(s, w, n, e);
  }

  LatLng get centre => bounds.center;

  /// Radius in metres that comfortably contains the whole track.
  double get suggestedRadius {
    final b = bounds;
    final h = haversineMetres(LatLng(b.south, b.west), LatLng(b.north, b.west));
    final w = haversineMetres(LatLng(b.south, b.west), LatLng(b.south, b.east));
    final r = (h > w ? h : w) / 2;
    return (r * 1.3).clamp(400.0, 20000.0);
  }

  /// Projected polyline in window-local units.
  Float32List project(MapWindow window) {
    final out = Float32List(points.length * 2);
    for (var i = 0; i < points.length; i++) {
      out[i * 2] = window.localX(points[i].lon);
      out[i * 2 + 1] = window.localY(points[i].lat);
    }
    return out;
  }

  Map<String, dynamic> toJson() => {
        'n': name,
        'd': distanceMetres,
        'a': ascentMetres,
        if (duration != null) 'du': duration!.inSeconds,
        if (recordedAt != null) 'r': recordedAt!.millisecondsSinceEpoch,
        if (elevations.isNotEmpty) 'e': elevations,
        'p': points.expand((p) => [p.lat, p.lon]).toList(),
      };

  factory RouteTrack.fromJson(Map<String, dynamic> j) {
    final flat = (j['p'] as List).map((e) => (e as num).toDouble()).toList();
    final pts = <LatLng>[];
    for (var i = 0; i + 1 < flat.length; i += 2) {
      pts.add(LatLng(flat[i], flat[i + 1]));
    }
    return RouteTrack(
      name: j['n'] as String? ?? 'Route',
      points: pts,
      distanceMetres: (j['d'] as num?)?.toDouble() ?? 0,
      ascentMetres: (j['a'] as num?)?.toDouble() ?? 0,
      duration: j['du'] == null ? null : Duration(seconds: j['du'] as int),
      recordedAt: j['r'] == null ? null : DateTime.fromMillisecondsSinceEpoch(j['r'] as int),
      elevations:
          (j['e'] as List?)?.map((e) => (e as num).toDouble()).toList() ?? const [],
    );
  }
}
