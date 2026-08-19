import 'dart:math' as math;

/// A WGS84 coordinate.
class LatLng {
  final double lat;
  final double lon;
  const LatLng(this.lat, this.lon);

  Map<String, dynamic> toJson() => {'lat': lat, 'lon': lon};
  factory LatLng.fromJson(Map<String, dynamic> j) =>
      LatLng((j['lat'] as num).toDouble(), (j['lon'] as num).toDouble());

  @override
  String toString() => '$lat,$lon';
}

/// Metres per degree of latitude (spherical approximation).
const double kMetresPerDegLat = 111320.0;

/// Great-circle distance in metres.
double haversineMetres(LatLng a, LatLng b) {
  const r = 6371008.8;
  final dLat = _rad(b.lat - a.lat);
  final dLon = _rad(b.lon - a.lon);
  final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_rad(a.lat)) * math.cos(_rad(b.lat)) * math.sin(dLon / 2) * math.sin(dLon / 2);
  return 2 * r * math.asin(math.min(1.0, math.sqrt(h)));
}

double _rad(double d) => d * math.pi / 180.0;

/// Axis aligned geographic bounding box.
class BBox {
  final double south;
  final double west;
  final double north;
  final double east;
  const BBox(this.south, this.west, this.north, this.east);

  LatLng get center => LatLng((south + north) / 2, (west + east) / 2);

  /// A box whose half-height is [radiusMetres] and whose ground width matches
  /// its ground height (i.e. roughly square on the surface).
  factory BBox.square(LatLng centre, double radiusMetres) {
    final dLat = radiusMetres / kMetresPerDegLat;
    final cosLat = math.cos(_rad(centre.lat)).abs().clamp(0.02, 1.0);
    final dLon = radiusMetres / (kMetresPerDegLat * cosLat);
    return BBox(centre.lat - dLat, centre.lon - dLon, centre.lat + dLat, centre.lon + dLon);
  }

  BBox inflated(double factor) {
    final dLat = (north - south) * (factor - 1) / 2;
    final dLon = (east - west) * (factor - 1) / 2;
    return BBox(south - dLat, west - dLon, north + dLat, east + dLon);
  }

  /// Overpass bbox order: south,west,north,east.
  String get overpass => '${south.toStringAsFixed(6)},${west.toStringAsFixed(6)},'
      '${north.toStringAsFixed(6)},${east.toStringAsFixed(6)}';

  Map<String, dynamic> toJson() => {'s': south, 'w': west, 'n': north, 'e': east};
  factory BBox.fromJson(Map<String, dynamic> j) => BBox((j['s'] as num).toDouble(),
      (j['w'] as num).toDouble(), (j['n'] as num).toDouble(), (j['e'] as num).toDouble());
}

/// Normalised Web-Mercator helpers. Both axes span 0..1 for the whole world,
/// y increasing southwards.
class Mercator {
  static double x(double lon) => (lon + 180.0) / 360.0;

  static double y(double lat) {
    final clamped = lat.clamp(-85.05112878, 85.05112878);
    final s = math.sin(_rad(clamped));
    return 0.5 - math.log((1 + s) / (1 - s)) / (4 * math.pi);
  }

  static double lon(double x) => x * 360.0 - 180.0;

  static double lat(double y) {
    final n = math.pi - 2 * math.pi * y;
    return 180.0 / math.pi * math.atan(0.5 * (math.exp(n) - math.exp(-n)));
  }
}

/// The square Mercator window a dataset was captured in.
class MapWindow {
  /// Top-left corner in normalised Mercator units.
  final double originX;
  final double originY;

  /// Side length in normalised Mercator units.
  final double span;

  const MapWindow(this.originX, this.originY, this.span);

  /// Centres the window on the box's centre point rather than on the midpoint
  /// of its projected edges, so the place you searched for lands exactly in
  /// the middle of the poster even at high latitudes.
  factory MapWindow.forBox(BBox box) {
    final x0 = Mercator.x(box.west);
    final x1 = Mercator.x(box.east);
    final y0 = Mercator.y(box.north);
    final y1 = Mercator.y(box.south);
    final side = math.max(x1 - x0, y1 - y0);
    final centre = box.center;
    final cx = Mercator.x(centre.lon);
    final cy = Mercator.y(centre.lat);
    return MapWindow(cx - side / 2, cy - side / 2, side);
  }

  /// Local unit coordinate (0..1 inside the window) for a geographic point.
  double localX(double lon) => (Mercator.x(lon) - originX) / span;
  double localY(double lat) => (Mercator.y(lat) - originY) / span;

  LatLng get centre =>
      LatLng(Mercator.lat(originY + span / 2), Mercator.lon(originX + span / 2));

  /// Ground width of the window at its centre, in metres.
  double get groundSpanMetres {
    final c = centre;
    final west = Mercator.lon(originX);
    final east = Mercator.lon(originX + span);
    return haversineMetres(LatLng(c.lat, west), LatLng(c.lat, east));
  }

  Map<String, dynamic> toJson() => {'ox': originX, 'oy': originY, 'sp': span};
  factory MapWindow.fromJson(Map<String, dynamic> j) => MapWindow((j['ox'] as num).toDouble(),
      (j['oy'] as num).toDouble(), (j['sp'] as num).toDouble());
}
