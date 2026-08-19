import 'dart:typed_data';

import 'package:carta/core/geo.dart';
import 'package:carta/data/dem/marching_squares.dart';
import 'package:carta/data/dem/terrain_tiles.dart';
import 'package:carta/model/layer.dart';
import 'package:carta/model/map_data.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds a request over a synthetic elevation grid mapped 1:1 into the window.
ContourRequest _request(Float32List grid, int w, int h, double interval) => ContourRequest(
      grid: grid,
      width: w,
      height: h,
      originLocalX: 0,
      originLocalY: 0,
      stepLocal: 1 / (w - 1),
      interval: interval,
      windowOriginX: 0.5,
      windowOriginY: 0.5,
      windowSpan: 7.5e-5,
      south: -0.001,
      west: -0.001,
      north: 0.001,
      east: 0.001,
    );

List<MapFeature> _contours(Float32List grid, int w, int h, double interval) {
  final data = MapDataCodec.decode(buildContoursToBytes(_request(grid, w, h, interval)))!;
  return data.features;
}

void main() {
  group('chooseInterval', () {
    test('never returns less than the caller asked for', () {
      expect(chooseInterval(30, 10), greaterThanOrEqualTo(10));
      expect(chooseInterval(4000, 10), greaterThanOrEqualTo(10));
    });

    test('opens up as the terrain gets steeper', () {
      final flat = chooseInterval(40, 1);
      final alpine = chooseInterval(3000, 1);
      expect(alpine, greaterThan(flat));
    });

    test('keeps the line count in a readable range', () {
      for (final relief in [15.0, 120.0, 900.0, 4000.0]) {
        final interval = chooseInterval(relief, 1);
        final lines = relief / interval;
        expect(lines, lessThan(40), reason: 'relief $relief would draw $lines lines');
      }
    });
  });

  group('marching squares', () {
    test('a linear ramp produces one straight line per level', () {
      const w = 64, h = 64;
      final grid = Float32List(w * h);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          grid[y * w + x] = x.toDouble(); // 0..63 metres
        }
      }
      final features = _contours(grid, w, h, 10);
      expect(features, isNotEmpty);

      final levels = features.map((f) => f.height).toSet().toList()..sort();
      // 0 m counts: on real terrain that is the shoreline contour.
      expect(levels, [0.0, 10.0, 20.0, 30.0, 40.0, 50.0, 60.0]);

      for (final f in features) {
        expect(f.layer, LayerId.contour);
        expect(f.closed, isFalse);
        final pts = f.parts.single;
        // A ramp in x means every contour is vertical: constant x, spanning y.
        final firstX = pts[0];
        for (var i = 0; i < pts.length; i += 2) {
          expect(pts[i], closeTo(firstX, 1e-4));
        }
        expect(pts[1], closeTo(0.0, 0.05));
        expect(pts[pts.length - 1], closeTo(1.0, 0.05));
      }
    });

    test('contours land at the right place in window coordinates', () {
      const w = 41, h = 41;
      final grid = Float32List(w * h);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          grid[y * w + x] = x.toDouble();
        }
      }
      // The 20 m line must sit at x = 20/40 = 0.5 of the window.
      final twenty = _contours(grid, w, h, 20).where((f) => f.height == 20).single;
      expect(twenty.parts.single[0], closeTo(0.5, 0.01));
    });

    test('a cone produces closed rings', () {
      const w = 80, h = 80;
      final grid = Float32List(w * h);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final dx = x - 39.5, dy = y - 39.5;
          final d = (dx * dx + dy * dy) / 20;
          grid[y * w + x] = (200 - d).clamp(0.0, 200.0).toDouble();
        }
      }
      final features = _contours(grid, w, h, 25);
      expect(features, isNotEmpty);
      var checked = 0;
      for (final f in features) {
        final pts = f.parts.single;
        // Rings that run off the grid are legitimately open; only the ones
        // fully inside must close.
        var touchesEdge = false;
        for (var i = 0; i < pts.length; i += 2) {
          if (pts[i] < 0.03 || pts[i] > 0.97 || pts[i + 1] < 0.03 || pts[i + 1] > 0.97) {
            touchesEdge = true;
          }
        }
        if (touchesEdge) continue;
        checked++;
        final closed = (pts[0] - pts[pts.length - 2]).abs() < 1e-3 &&
            (pts[1] - pts[pts.length - 1]).abs() < 1e-3;
        expect(closed, isTrue, reason: 'ring at ${f.height} m should close');
      }
      expect(checked, greaterThan(0), reason: 'no fully enclosed rings to check');
    });

    test('flat ground produces nothing rather than noise', () {
      const w = 32, h = 32;
      final grid = Float32List(w * h)..fillRange(0, w * h, 12.0);
      expect(_contours(grid, w, h, 10), isEmpty);
    });

    test('chains join across cells instead of leaving loose segments', () {
      const w = 64, h = 64;
      final grid = Float32List(w * h);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          grid[y * w + x] = x.toDouble();
        }
      }
      final features = _contours(grid, w, h, 10);
      // One polyline per level, not 63 two-point stubs.
      expect(features.length, 7);
      expect(features.first.parts.single.length ~/ 2, greaterThan(50));
    });

    test('the inferred interval matches what was requested', () {
      const w = 48, h = 48;
      final grid = Float32List(w * h);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          grid[y * w + x] = x * 2.0;
        }
      }
      final data = MapDataCodec.decode(
          buildContoursToBytes(_request(grid, w, h, 20)))!;
      expect(data.hasContours, isTrue);
      final levels = data.features.map((f) => f.height).toSet().toList()..sort();
      expect(levels[1] - levels[0], 20);
    });
  });

  group('terrain tiles', () {
    test('zoom scales with how much ground the poster covers', () {
      final city = TerrainTileClient.zoomFor(BBox.square(const LatLng(0, 0), 1500));
      final region = TerrainTileClient.zoomFor(BBox.square(const LatLng(0, 0), 12000));
      expect(city, greaterThan(region));
      expect(city, inInclusiveRange(8, 14));
      expect(region, inInclusiveRange(8, 14));
    });

    test('relief reports the range of a grid', () {
      final grid = ElevationGrid(
        values: Float32List.fromList([5, 10, 200, -3]),
        width: 2,
        height: 2,
        originLocalX: 0,
        originLocalY: 0,
        stepLocal: 0.1,
      );
      expect(grid.relief.min, -3);
      expect(grid.relief.max, 200);
    });
  });
}
