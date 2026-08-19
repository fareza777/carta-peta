import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../model/layer.dart';
import '../model/map_data.dart';

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

  bool get hasAnything => data.features.isNotEmpty;

  /// Every feature of a layer, ignoring its vertical band.
  Path solid(LayerId layer) =>
      _paths.putIfAbsent('s${layer.index}', () => _build((f) => f.layer == layer));

  /// One band of a road layer, so bridges can be drawn over every ground road.
  Path road(LayerId layer, RoadBand band) => _paths.putIfAbsent(
      'r${layer.index}.${band.index}',
      () => _build((f) => f.layer == layer && f.band == band));

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
