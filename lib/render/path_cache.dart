import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../model/layer.dart';
import '../model/map_data.dart';

/// A place on the map worth lettering, resolved once per capture.
class MapLabel {
  const MapLabel({
    required this.text,
    required this.x,
    required this.y,
    required this.angle,
    required this.span,
    required this.area,
    required this.layer,
  });

  final String text;

  /// Anchor in window-local coordinates.
  final double x;
  final double y;

  /// Baseline rotation in radians; always upright-ish.
  final double angle;

  /// Length of the road segment, or extent of the area, in local units.
  /// The renderer uses it to drop labels that would not fit.
  final double span;
  final bool area;
  final LayerId layer;
}

/// Builds and caches `Path` objects in window-local space (0..1).
///
/// Painting then only needs a canvas transform, so panning, zooming and
/// restyling never rebuild geometry — which is what keeps the live preview
/// smooth on a phone.
class MapPathCache {
  MapPathCache(this.data);

  /// How many tint steps buildings are grouped into when height shading is on.
  static const int heightBuckets = 6;

  final MapDataSet data;
  final Map<String, Path> _paths = {};
  final Map<String, Path> _dashed = {};

  double? _contourInterval;
  double? _tallest;
  List<MapLabel>? _labels;

  Picture? _cachedMap;
  String? _cachedMapKey;

  bool get hasAnything => data.features.isNotEmpty;

  /// Every feature of a layer, ignoring its vertical band.
  Path solid(LayerId layer) =>
      _paths.putIfAbsent('s${layer.index}', () => _build((f) => f.layer == layer));

  /// One band of a road layer, so bridges can be drawn over every ground road.
  Path road(LayerId layer, RoadBand band) => _paths.putIfAbsent(
        'r${layer.index}.${band.index}',
        () => _build((f) => f.layer == layer && f.band == band),
      );

  double get tallestBuilding => _tallest ??= data.tallestBuilding;

  bool get hasBuildingHeights => tallestBuilding > 3;

  /// Buildings whose height falls in bucket [index] of [heightBuckets].
  Path buildingBucket(int index) => _paths.putIfAbsent('b$index', () {
        final top = tallestBuilding;
        return _build((f) {
          if (f.layer != LayerId.building) return false;
          return bucketOf(f.height, top) == index;
        });
      });

  static int bucketOf(double height, double tallest) {
    if (tallest <= 0 || height <= 0) return 0;
    final t = (height / tallest).clamp(0.0, 1.0);
    // Heights are heavily skewed towards low-rise, so spread them on a curve.
    final eased = math.pow(t, 0.6).toDouble();
    return (eased * (heightBuckets - 1)).round().clamp(0, heightBuckets - 1);
  }

  // ------------------------------------------------------------- map picture

  /// The recorded map layer for a given view, or null if the key moved on.
  ///
  /// Poster text changes far more often than geometry does — every keystroke in
  /// the title field used to re-rasterise every street. Replaying one display
  /// list instead costs nothing.
  Picture? cachedMap(String key) => _cachedMapKey == key ? _cachedMap : null;

  /// Which view is currently recorded, exposed so tests can assert that a
  /// poster-text edit did not invalidate the geometry.
  String? get mapCacheKey => _cachedMapKey;

  void storeMap(String key, Picture picture) {
    if (identical(_cachedMap, picture)) return;
    _cachedMap?.dispose();
    _cachedMap = picture;
    _cachedMapKey = key;
  }

  void dispose() {
    _cachedMap?.dispose();
    _cachedMap = null;
    _cachedMapKey = null;
  }

  // ------------------------------------------------------------------ labels

  /// Candidate map labels, one per distinct name, biggest instance wins.
  List<MapLabel> get labels => _labels ??= _buildLabels();

  List<MapLabel> _buildLabels() {
    final best = <String, MapLabel>{};
    for (final f in data.features) {
      final name = f.name;
      if (name == null || f.parts.isEmpty) continue;
      final label = f.closed ? _areaLabel(f, name) : _lineLabel(f, name);
      if (label == null) continue;
      final existing = best[name];
      if (existing == null || label.span > existing.span) best[name] = label;
    }
    final list = best.values.toList()
      ..sort((a, b) => b.span.compareTo(a.span));
    return list;
  }

  static MapLabel? _lineLabel(MapFeature f, String name) {
    var bestLength = 0.0;
    var bx = 0.0, by = 0.0, angle = 0.0;
    for (final p in f.parts) {
      for (var i = 0; i + 3 < p.length; i += 2) {
        final dx = p[i + 2] - p[i];
        final dy = p[i + 3] - p[i + 1];
        final length = math.sqrt(dx * dx + dy * dy);
        if (length <= bestLength) continue;
        bestLength = length;
        bx = (p[i] + p[i + 2]) / 2;
        by = (p[i + 1] + p[i + 3]) / 2;
        angle = math.atan2(dy, dx);
      }
    }
    if (bestLength <= 0) return null;
    // Keep the text the right way up.
    if (angle > math.pi / 2) {
      angle -= math.pi;
    } else if (angle < -math.pi / 2) {
      angle += math.pi;
    }
    return MapLabel(
      text: name,
      x: bx,
      y: by,
      angle: angle,
      span: bestLength,
      area: false,
      layer: f.layer,
    );
  }

  static MapLabel? _areaLabel(MapFeature f, String name) {
    final ring = f.parts.first;
    if (ring.length < 6) return null;
    var sumX = 0.0, sumY = 0.0;
    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    // A closed ring repeats its first vertex; counting it twice pulls the
    // centroid towards that corner.
    final closed = (ring[0] - ring[ring.length - 2]).abs() < 1e-9 &&
        (ring[1] - ring[ring.length - 1]).abs() < 1e-9;
    final last = closed ? ring.length - 2 : ring.length;
    final count = last ~/ 2;
    for (var i = 0; i < last; i += 2) {
      sumX += ring[i];
      sumY += ring[i + 1];
      if (ring[i] < minX) minX = ring[i];
      if (ring[i] > maxX) maxX = ring[i];
      if (ring[i + 1] < minY) minY = ring[i + 1];
      if (ring[i + 1] > maxY) maxY = ring[i + 1];
    }
    final extent = math.min(maxX - minX, maxY - minY);
    if (extent <= 0) return null;
    return MapLabel(
      text: name,
      x: sumX / count,
      y: sumY / count,
      angle: 0,
      span: extent,
      area: true,
      layer: f.layer,
    );
  }

  // ---------------------------------------------------------------- contours

  /// Spacing between contour levels, inferred from the data.
  double get contourInterval {
    if (_contourInterval != null) return _contourInterval!;
    final levels = <double>{};
    for (final f in data.features) {
      if (f.layer == LayerId.contour) levels.add(f.height);
    }
    if (levels.length < 2) return _contourInterval = 0;
    final sorted = levels.toList()..sort();
    var best = double.infinity;
    for (var i = 1; i < sorted.length; i++) {
      final d = sorted[i] - sorted[i - 1];
      if (d > 0.01 && d < best) best = d;
    }
    return _contourInterval = best.isFinite ? best : 0;
  }

  /// Every fifth contour, drawn heavier the way printed topo maps do.
  Path contour({required bool index}) {
    final interval = contourInterval;
    return _paths.putIfAbsent('c${index ? 1 : 0}', () => _build((f) {
          if (f.layer != LayerId.contour) return false;
          if (interval <= 0) return !index;
          final step = (f.height / interval).round();
          return index ? step % 5 == 0 : step % 5 != 0;
        }));
  }

  /// Dash lengths are expressed in local units so they survive the canvas
  /// transform; the caller converts from poster units.
  Path dashed(String key, Path source, double on, double off) {
    final id = '$key:${on.toStringAsFixed(5)}:${off.toStringAsFixed(5)}';
    final hit = _dashed[id];
    if (hit != null) return hit;
    // Dash length depends on zoom, so drop stale entries instead of growing
    // without bound while the user pinches around.
    if (_dashed.length > 24) _dashed.clear();
    return _dashed[id] = _dashify(source, on, off);
  }

  Path _build(bool Function(MapFeature) accept) {
    final path = Path()..fillType = PathFillType.nonZero;
    for (final f in data.features) {
      if (!accept(f)) continue;
      if (f.closed) {
        for (var i = 0; i < f.parts.length; i++) {
          final ring = f.parts[i];
          if (ring.length < 6) continue;
          _addRing(path, ring, i == 0);
        }
      } else {
        for (final p in f.parts) {
          _addLine(path, p);
        }
      }
    }
    return path;
  }

  static void _addLine(Path path, Float32List p) {
    if (p.length < 4) return;
    path.moveTo(p[0], p[1]);
    for (var i = 2; i < p.length; i += 2) {
      path.lineTo(p[i], p[i + 1]);
    }
  }

  /// Adds a closed ring, reversing it when needed so outer rings and holes wind
  /// consistently and a single non-zero path can fill a whole layer correctly.
  static void _addRing(Path path, Float32List p, bool wantPositive) {
    final positive = _signedArea(p) > 0;
    if (positive == wantPositive) {
      path.moveTo(p[0], p[1]);
      for (var i = 2; i < p.length; i += 2) {
        path.lineTo(p[i], p[i + 1]);
      }
    } else {
      final last = p.length - 2;
      path.moveTo(p[last], p[last + 1]);
      for (var i = last - 2; i >= 0; i -= 2) {
        path.lineTo(p[i], p[i + 1]);
      }
    }
    path.close();
  }

  static double _signedArea(Float32List p) {
    var a = 0.0;
    for (var i = 0; i + 3 < p.length; i += 2) {
      a += p[i] * p[i + 3] - p[i + 2] * p[i + 1];
    }
    return a;
  }

  static Path _dashify(Path source, double on, double off) {
    if (on <= 0 || off <= 0) return source;
    final out = Path();
    for (final metric in source.computeMetrics()) {
      var distance = 0.0;
      var draw = true;
      final total = metric.length;
      var guard = 0;
      while (distance < total && guard++ < 20000) {
        final step = draw ? on : off;
        final end = (distance + step).clamp(0.0, total);
        if (draw) {
          out.addPath(metric.extractPath(distance, end), Offset.zero);
        }
        distance = end;
        draw = !draw;
      }
    }
    return out;
  }
}
