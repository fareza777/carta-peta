import 'dart:typed_data';

/// Turns `natural=coastline` ways into fillable sea polygons.
///
/// OSM draws coastlines as open lines with land on the left of the direction of
/// travel. To paint the sea we stitch the ways into long chains, clip them to
/// the poster window and close each chain by walking clockwise along the window
/// border (which is exactly the water side).
///
/// Input and output are window-local coordinates (0..1, y pointing south).
class CoastlineBuilder {
  static const double _eps = 1e-6;

  /// Returns rings to be filled with an even-odd rule, or an empty list when
  /// the data is too broken to be trusted.
  static List<Float32List> build(List<Float32List> ways) {
    if (ways.isEmpty || ways.length > 4000) return const [];

    final chains = _stitch(ways);
    final islands = <List<double>>[];
    final crossing = <_Chain>[];

    for (final chain in chains) {
      final uv = _toUpwards(chain);
      if (_isClosed(uv)) {
        // Fully closed ring: an island (counter-clockwise) or an inland sea.
        islands.add(uv);
        continue;
      }
      for (final piece in _clipToSquare(uv)) {
        if (piece.length < 4) continue;
        final tStart = _boundaryParam(piece[0], piece[1]);
        final tEnd = _boundaryParam(piece[piece.length - 2], piece[piece.length - 1]);
        if (tStart == null || tEnd == null) continue;
        crossing.add(_Chain(piece, tStart, tEnd));
      }
    }

    final rings = <Float32List>[];

    if (crossing.isEmpty) {
      // Nothing crosses the frame. Only meaningful when the window sits in open
      // water around one or more islands.
      final ccw = islands.where(_isCounterClockwise).toList();
      if (ccw.isEmpty || ccw.length != islands.length) return const [];
      rings.add(_downFloat([0, 0, 1, 0, 1, 1, 0, 1]));
      for (final isle in islands) {
        rings.add(_downFloat(isle));
      }
      return rings;
    }

    if (crossing.length > 400) return const [];

    crossing.sort((a, b) => a.tStart.compareTo(b.tStart));
    final used = List<bool>.filled(crossing.length, false);

    for (var i = 0; i < crossing.length; i++) {
      if (used[i]) continue;
      final poly = <double>[];
      var index = i;
      var guard = 0;
      while (guard++ < crossing.length * 2 + 8) {
        if (used[index]) break;
        used[index] = true;
        poly.addAll(crossing[index].points);
        final next = _nextChain(crossing, crossing[index].tEnd);
        if (next < 0) break;
        _walkBorder(poly, crossing[index].tEnd, crossing[next].tStart);
        if (next == i) break;
        index = next;
      }
      if (poly.length >= 8) rings.add(_downFloat(poly));
    }

    for (final isle in islands) {
      rings.add(_downFloat(isle));
    }
    return rings;
  }

  // ------------------------------------------------------------------ helpers

  /// Joins ways that share endpoints into the longest possible chains.
  static List<Float32List> _stitch(List<Float32List> ways) {
    final open = <List<double>>[];
    for (final w in ways) {
      if (w.length >= 4) open.add(List<double>.from(w));
    }
    final result = <Float32List>[];
    while (open.isNotEmpty) {
      var chain = open.removeLast();
      var extended = true;
      var guard = 0;
      while (extended && guard++ < 5000) {
        extended = false;
        for (var i = 0; i < open.length; i++) {
          final other = open[i];
          if (_same(chain[chain.length - 2], chain[chain.length - 1], other[0], other[1])) {
            chain.addAll(other.sublist(2));
            open.removeAt(i);
            extended = true;
            break;
          }
          if (_same(chain[0], chain[1], other[other.length - 2], other[other.length - 1])) {
            chain = [...other.sublist(0, other.length - 2), ...chain];
            open.removeAt(i);
            extended = true;
            break;
          }
        }
      }
      result.add(Float32List.fromList(chain));
    }
    return result;
  }

  static bool _same(double ax, double ay, double bx, double by) =>
      (ax - bx).abs() < 1e-7 && (ay - by).abs() < 1e-7;

  /// Flip to y-up so the OSM left-hand rule keeps its usual orientation.
  static List<double> _toUpwards(Float32List src) {
    final out = List<double>.filled(src.length, 0);
    for (var i = 0; i < src.length; i += 2) {
      out[i] = src[i];
      out[i + 1] = 1.0 - src[i + 1];
    }
    return out;
  }

  static Float32List _downFloat(List<double> uv) {
    final out = Float32List(uv.length);
    for (var i = 0; i < uv.length; i += 2) {
      out[i] = uv[i];
      out[i + 1] = 1.0 - uv[i + 1];
    }
    return out;
  }

  static bool _isClosed(List<double> uv) =>
      uv.length >= 6 && _same(uv[0], uv[1], uv[uv.length - 2], uv[uv.length - 1]);

  static bool _isCounterClockwise(List<double> uv) {
    var area = 0.0;
    for (var i = 0; i + 3 < uv.length; i += 2) {
      area += uv[i] * uv[i + 3] - uv[i + 2] * uv[i + 1];
    }
    return area > 0;
  }

  /// Liang-Barsky clip of every segment against the unit square.
  static List<List<double>> _clipToSquare(List<double> uv) {
    final pieces = <List<double>>[];
    List<double>? current;
    for (var i = 0; i + 3 < uv.length; i += 2) {
      final x0 = uv[i], y0 = uv[i + 1], x1 = uv[i + 2], y1 = uv[i + 3];
      final seg = _clipSegment(x0, y0, x1, y1);
      if (seg == null) {
        if (current != null && current.length >= 4) pieces.add(current);
        current = null;
        continue;
      }
      final enteredMidway = seg[4] > _eps;
      final exitsMidway = seg[5] < 1 - _eps;
      if (current == null || enteredMidway) {
        if (current != null && current.length >= 4) pieces.add(current);
        current = [seg[0], seg[1]];
      }
      current.add(seg[2]);
      current.add(seg[3]);
      if (exitsMidway) {
        if (current.length >= 4) pieces.add(current);
        current = null;
      }
    }
    if (current != null && current.length >= 4) pieces.add(current);
    return pieces;
  }

  /// Returns [x0, y0, x1, y1, t0, t1] of the visible part, or null.
  static List<double>? _clipSegment(double x0, double y0, double x1, double y1) {
    final dx = x1 - x0, dy = y1 - y0;
    var t0 = 0.0, t1 = 1.0;
    final p = [-dx, dx, -dy, dy];
    final q = [x0, 1 - x0, y0, 1 - y0];
    for (var i = 0; i < 4; i++) {
      if (p[i].abs() < 1e-12) {
        if (q[i] < 0) return null;
        continue;
      }
      final r = q[i] / p[i];
      if (p[i] < 0) {
        if (r > t1) return null;
        if (r > t0) t0 = r;
      } else {
        if (r < t0) return null;
        if (r < t1) t1 = r;
      }
    }
    return [x0 + t0 * dx, y0 + t0 * dy, x0 + t1 * dx, y0 + t1 * dy, t0, t1];
  }

  /// Perimeter parameter in [0,4), running clockwise in y-up space.
  static double? _boundaryParam(double u, double v) {
    const t = 1e-4;
    if (u <= t) return v.clamp(0.0, 1.0);
    if (v >= 1 - t) return 1.0 + u.clamp(0.0, 1.0);
    if (u >= 1 - t) return 2.0 + (1 - v).clamp(0.0, 1.0);
    if (v <= t) return 3.0 + (1 - u).clamp(0.0, 1.0);
    return null;
  }

  static int _nextChain(List<_Chain> chains, double from) {
    var best = -1;
    var bestDelta = double.infinity;
    for (var i = 0; i < chains.length; i++) {
      var d = chains[i].tStart - from;
      if (d < 1e-9) d += 4.0;
      if (d < bestDelta) {
        bestDelta = d;
        best = i;
      }
    }
    return best;
  }

  /// Appends the window corners passed while travelling clockwise from [from]
  /// to [to] along the border.
  static void _walkBorder(List<double> poly, double from, double to) {
    final t = from;
    var target = to;
    if (target < t) target += 4.0;
    var corner = t.floorToDouble() + 1.0;
    var guard = 0;
    while (corner < target && guard++ < 8) {
      final c = _pointAt(corner % 4.0);
      poly..add(c[0])..add(c[1]);
      corner += 1.0;
    }
    final end = _pointAt(to % 4.0);
    poly..add(end[0])..add(end[1]);
  }

  static List<double> _pointAt(double t) {
    if (t < 1) return [0.0, t];
    if (t < 2) return [t - 1, 1.0];
    if (t < 3) return [1.0, 1 - (t - 2)];
    return [1 - (t - 3), 0.0];
  }
}

class _Chain {
  final List<double> points;
  final double tStart;
  final double tEnd;
  _Chain(this.points, this.tStart, this.tEnd);
}
