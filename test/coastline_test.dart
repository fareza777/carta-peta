import 'dart:typed_data';

import 'package:carta/data/osm/coastline.dart';
import 'package:flutter_test/flutter_test.dart';

/// Coordinates here are window-local: 0..1 across the poster, y pointing south.
Float32List _way(List<double> xy) => Float32List.fromList(xy);

double _area(Float32List ring) {
  var a = 0.0;
  for (var i = 0; i + 3 < ring.length; i += 2) {
    a += ring[i] * ring[i + 3] - ring[i + 2] * ring[i + 1];
  }
  return a.abs() / 2;
}

void main() {
  test('no coastline produces no rings', () {
    expect(CoastlineBuilder.build([]), isEmpty);
  });

  test('a single crossing coastline closes into a sea polygon', () {
    // Runs west to east across the middle. Land on the left of travel means
    // land is to the north (smaller y), so the sea is the southern half.
    final rings = CoastlineBuilder.build([
      _way([-0.2, 0.5, 0.5, 0.5, 1.2, 0.5]),
    ]);
    expect(rings, isNotEmpty);
    final total = rings.fold<double>(0, (sum, r) => sum + _area(r));
    expect(total, closeTo(0.5, 0.08));
  });

  test('the sea sits on the correct side of the shoreline', () {
    final rings = CoastlineBuilder.build([
      _way([-0.2, 0.5, 1.2, 0.5]),
    ]);
    expect(rings, isNotEmpty);
    var minY = double.infinity;
    var maxY = -double.infinity;
    for (final r in rings) {
      for (var i = 1; i < r.length; i += 2) {
        if (r[i] < minY) minY = r[i];
        if (r[i] > maxY) maxY = r[i];
      }
    }
    // Southern half only: y from 0.5 down to 1.0.
    expect(minY, closeTo(0.5, 0.02));
    expect(maxY, closeTo(1.0, 0.02));
  });

  test('stitches split coastline ways before closing', () {
    final rings = CoastlineBuilder.build([
      _way([-0.2, 0.5, 0.4, 0.5]),
      _way([0.4, 0.5, 1.2, 0.5]),
    ]);
    expect(rings, isNotEmpty);
    final total = rings.fold<double>(0, (sum, r) => sum + _area(r));
    expect(total, closeTo(0.5, 0.08));
  });

  test('an island fully inside open water becomes a hole', () {
    // A closed counter-clockwise ring in y-up space is an island.
    final rings = CoastlineBuilder.build([
      _way([0.4, 0.4, 0.4, 0.6, 0.6, 0.6, 0.6, 0.4, 0.4, 0.4]),
    ]);
    expect(rings.length, 2, reason: 'full-window sea plus the island ring');
    expect(_area(rings.first), closeTo(1.0, 0.001));
    expect(_area(rings.last), closeTo(0.04, 0.005));
  });

  test('bails out rather than guessing on absurd input', () {
    final many = List.generate(4100, (i) => _way([0.0, i / 4100, 1.0, i / 4100]));
    expect(CoastlineBuilder.build(many), isEmpty);
  });
}
