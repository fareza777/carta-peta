import 'dart:math' as math;
import 'dart:typed_data';

import '../../core/geo.dart';
import '../../model/layer.dart';
import '../../model/map_data.dart';

/// Isolate payload for contour extraction. Plain values only.
class ContourRequest {
  final Float32List grid;
  final int width;
  final int height;
  final double originLocalX;
  final double originLocalY;
  final double stepLocal;
  final double interval;

  /// Ground size of one grid sample, used by the hillshade gradient.
  final double metresPerSample;
  final double windowOriginX;
  final double windowOriginY;
  final double windowSpan;
  final double south;
  final double west;
  final double north;
  final double east;

  const ContourRequest({
    required this.grid,
    required this.width,
    required this.height,
    required this.originLocalX,
    required this.originLocalY,
    required this.stepLocal,
    required this.interval,
    this.metresPerSample = 30,
    required this.windowOriginX,
    required this.windowOriginY,
    required this.windowSpan,
    required this.south,
    required this.west,
    required this.north,
    required this.east,
  });
}

/// Picks a contour spacing that yields a readable number of lines whatever the
/// terrain: a flat delta and an alpine valley should both look deliberate.
double chooseInterval(double relief, double preferred) {
  const steps = <double>[1, 2, 5, 10, 20, 25, 50, 100, 200, 250, 500];
  final target = relief / 28.0;
  for (final s in steps) {
    if (s >= target && s >= preferred) return s;
  }
  return steps.last;
}

/// Top-level entry point for `compute`. Traces contours and shades the relief
/// in one pass over the grid, returning both as plain typed data so nothing
/// custom crosses the isolate boundary.
Map<String, dynamic> buildTerrainToBytes(ContourRequest req) => {
      'contours': buildContoursToBytes(req),
      'shade': buildHillshade(req),
      'w': req.width,
      'h': req.height,
      'ox': req.originLocalX,
      'oy': req.originLocalY,
      'step': req.stepLocal,
    };

/// Classic Horn hillshade: sun at 315 degrees, 45 degrees up. Output is RGBA
/// centred on mid grey so it can be composited with an overlay blend, which
/// darkens slopes on pale paper and lifts them on dark paper without either
/// turning to mud.
Uint8List buildHillshade(ContourRequest req) {
  final w = req.width;
  final h = req.height;
  final grid = req.grid;
  final out = Uint8List(w * h * 4);

  // Ground size of one sample, needed so slope is a real gradient and not an
  // arbitrary number that changes with zoom.
  final metres = req.metresPerSample <= 0 ? 30.0 : req.metresPerSample;
  const azimuth = 315.0 * math.pi / 180.0;
  const zenith = 45.0 * math.pi / 180.0;
  final cosZenith = math.cos(zenith);
  final sinZenith = math.sin(zenith);

  double at(int x, int y) => grid[y.clamp(0, h - 1) * w + x.clamp(0, w - 1)];

  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final a = at(x - 1, y - 1), b = at(x, y - 1), c = at(x + 1, y - 1);
      final d = at(x - 1, y), f = at(x + 1, y);
      final g = at(x - 1, y + 1), i = at(x, y + 1), j = at(x + 1, y + 1);

      final dzdx = ((c + 2 * f + j) - (a + 2 * d + g)) / (8 * metres);
      final dzdy = ((g + 2 * i + j) - (a + 2 * b + c)) / (8 * metres);

      final slope = math.atan(math.sqrt(dzdx * dzdx + dzdy * dzdy));
      final aspect = math.atan2(dzdy, -dzdx);
      var shade = cosZenith * math.cos(slope) +
          sinZenith * math.sin(slope) * math.cos(azimuth - aspect);
      shade = shade.clamp(0.0, 1.0);

      // Flat ground sits at cos(zenith); rebase it to neutral grey so the
      // overlay blend leaves plains untouched.
      final value = (128 + (shade - cosZenith) * 300).clamp(0.0, 255.0).toInt();
      final o = (y * w + x) * 4;
      out[o] = value;
      out[o + 1] = value;
      out[o + 2] = value;
      out[o + 3] = 255;
    }
  }
  return out;
}

/// Contours only. Kept separate so it can be exercised on its own.
Uint8List buildContoursToBytes(ContourRequest req) {
  final features = <MapFeature>[];
  final w = req.width;
  final h = req.height;
  final grid = req.grid;
  final interval = req.interval <= 0 ? 10.0 : req.interval;

  // Group the segments produced for each level, then chain them into
  // polylines. Every crossing lies on a known cell edge, so edges can be used
  // as exact integer join keys - no floating point matching.
  final byLevel = <int, _LevelBuilder>{};

  double at(int x, int y) => grid[y * w + x];

  for (var y = 0; y < h - 1; y++) {
    for (var x = 0; x < w - 1; x++) {
      final tl = at(x, y);
      final tr = at(x + 1, y);
      final br = at(x + 1, y + 1);
      final bl = at(x, y + 1);
      if (tl.isNaN || tr.isNaN || br.isNaN || bl.isNaN) continue;

      var lo = tl, hi = tl;
      for (final v in [tr, br, bl]) {
        if (v < lo) lo = v;
        if (v > hi) hi = v;
      }
      if (hi - lo <= 0) continue;

      // Levels in [lo, hi). A corner sitting exactly on a level counts as
      // below it (the `>` tests further down), so the lower bound is
      // inclusive - dropping it loses every contour on flat integer terrain.
      final first = (lo / interval).ceil();
      final last = (hi / interval).ceil() - 1;
      if (last < first) continue;
      // A pathological cell (a data spike) would otherwise emit thousands of
      // levels; clamp rather than hang.
      final upper = (last - first) > 64 ? first + 64 : last;

      for (var k = first; k <= upper; k++) {
        final level = k * interval;
        final builder = byLevel.putIfAbsent(k, () => _LevelBuilder(level));
        _cell(builder, x, y, tl, tr, br, bl, level, w);
      }
    }
  }

  final sorted = byLevel.keys.toList()..sort();
  for (final k in sorted) {
    final builder = byLevel[k]!;
    for (final line in builder.chains()) {
      final pts = Float32List(line.length);
      for (var i = 0; i < line.length; i += 2) {
        pts[i] = req.originLocalX + line[i] * req.stepLocal;
        pts[i + 1] = req.originLocalY + line[i + 1] * req.stepLocal;
      }
      features.add(MapFeature(LayerId.contour, false, [pts], height: builder.level));
    }
  }

  return MapDataCodec.encode(MapDataSet(
    window: MapWindow(req.windowOriginX, req.windowOriginY, req.windowSpan),
    bbox: BBox(req.south, req.west, req.north, req.east),
    features: features,
    capturedAt: DateTime.now(),
  ));
}

/// Edge ids: horizontal edges get even ids, vertical edges odd ones, so a
/// crossing point shared by two neighbouring cells resolves to one key.
int _hEdge(int x, int y, int w) => (y * w + x) << 1;
int _vEdge(int x, int y, int w) => ((y * w + x) << 1) | 1;

void _cell(_LevelBuilder b, int x, int y, double tl, double tr, double br,
    double bl, double level, int w) {
  var code = 0;
  if (tl > level) code |= 8;
  if (tr > level) code |= 4;
  if (br > level) code |= 2;
  if (bl > level) code |= 1;
  if (code == 0 || code == 15) return;

  // Crossing points on the four cell edges.
  ({int id, double x, double y}) top() => (
        id: _hEdge(x, y, w),
        x: x + _t(tl, tr, level),
        y: y.toDouble(),
      );
  ({int id, double x, double y}) bottom() => (
        id: _hEdge(x, y + 1, w),
        x: x + _t(bl, br, level),
        y: (y + 1).toDouble(),
      );
  ({int id, double x, double y}) left() => (
        id: _vEdge(x, y, w),
        x: x.toDouble(),
        y: y + _t(tl, bl, level),
      );
  ({int id, double x, double y}) right() => (
        id: _vEdge(x + 1, y, w),
        x: (x + 1).toDouble(),
        y: y + _t(tr, br, level),
      );

  switch (code) {
    case 1:
    case 14:
      b.addSegment(left(), bottom());
    case 2:
    case 13:
      b.addSegment(bottom(), right());
    case 3:
    case 12:
      b.addSegment(left(), right());
    case 4:
    case 11:
      b.addSegment(top(), right());
    case 5:
      b.addSegment(left(), top());
      b.addSegment(bottom(), right());
    case 6:
    case 9:
      b.addSegment(top(), bottom());
    case 7:
    case 8:
      b.addSegment(left(), top());
    case 10:
      b.addSegment(left(), bottom());
      b.addSegment(top(), right());
  }
}

double _t(double a, double b, double level) {
  final d = b - a;
  if (d.abs() < 1e-9) return 0.5;
  return ((level - a) / d).clamp(0.0, 1.0);
}

class _LevelBuilder {
  _LevelBuilder(this.level);

  final double level;

  /// Segment endpoints stored as edge ids, plus their positions.
  final List<int> _a = [];
  final List<int> _b = [];
  final Map<int, double> _px = {};
  final Map<int, double> _py = {};
  final Map<int, List<int>> _incident = {};

  void addSegment(({int id, double x, double y}) p, ({int id, double x, double y}) q) {
    if (p.id == q.id) return;
    final index = _a.length;
    _a.add(p.id);
    _b.add(q.id);
    _px[p.id] = p.x;
    _py[p.id] = p.y;
    _px[q.id] = q.x;
    _py[q.id] = q.y;
    (_incident[p.id] ??= []).add(index);
    (_incident[q.id] ??= []).add(index);
  }

  /// Walks the segment graph into the longest possible polylines.
  List<List<double>> chains() {
    final used = List<bool>.filled(_a.length, false);
    final out = <List<double>>[];

    void walk(int start, int firstSegment) {
      final points = <double>[_px[start]!, _py[start]!];
      var node = start;
      var segment = firstSegment;
      var guard = 0;
      while (guard++ < 200000) {
        if (used[segment]) break;
        used[segment] = true;
        final next = _a[segment] == node ? _b[segment] : _a[segment];
        points..add(_px[next]!)..add(_py[next]!);
        node = next;
        final candidates = _incident[node];
        if (candidates == null) break;
        var found = -1;
        for (final c in candidates) {
          if (!used[c]) {
            found = c;
            break;
          }
        }
        if (found < 0) break;
        segment = found;
      }
      if (points.length >= 6) out.add(points);
    }

    // Open chains first so they are not cut in the middle, then closed loops.
    for (final entry in _incident.entries) {
      if (entry.value.length != 1) continue;
      final segment = entry.value.first;
      if (!used[segment]) walk(entry.key, segment);
    }
    for (var i = 0; i < _a.length; i++) {
      if (!used[i]) walk(_a[i], i);
    }
    return out;
  }
}
