import 'dart:math' as math;
import 'dart:typed_data';

import '../core/geo.dart';
import '../model/layer.dart';
import '../model/map_data.dart';

/// A procedurally generated city used by the splash and onboarding screens.
///
/// It goes through the real renderer, so what a new user sees on first launch
/// is the actual engine rather than a screenshot — and it needs no network,
/// which matters because onboarding runs before anything has been downloaded.
MapDataSet buildDemoMap({int seed = 7, bool withContours = true}) {
  final rnd = math.Random(seed);
  final features = <MapFeature>[];

  Float32List line(List<double> xy) => Float32List.fromList(xy);

  void add(
    LayerId layer,
    bool closed,
    List<double> xy, {
    double height = 0,
    RoadBand band = RoadBand.ground,
    String? name,
  }) {
    features.add(MapFeature(layer, closed, [line(xy)],
        height: height, band: band, name: name));
  }

  // ---------------------------------------------------------------- greenery
  final park = <double>[];
  for (var a = 0.0; a <= math.pi * 2 + 0.01; a += math.pi / 18) {
    final r = 0.105 + math.sin(a * 3) * 0.014;
    park..add(0.29 + math.cos(a) * r)..add(0.30 + math.sin(a) * r * 0.86);
  }
  add(LayerId.green, true, park, name: 'Central Park');

  final wood = <double>[];
  for (var a = 0.0; a <= math.pi * 2 + 0.01; a += math.pi / 14) {
    final r = 0.075 + math.cos(a * 4) * 0.012;
    wood..add(0.80 + math.cos(a) * r)..add(0.24 + math.sin(a) * r);
  }
  add(LayerId.green, true, wood);

  // ------------------------------------------------------------------- river
  final top = <double>[];
  final bottom = <double>[];
  for (var t = -0.05; t <= 1.06; t += 0.025) {
    final y = 0.70 + math.sin(t * 5.4) * 0.055 + math.sin(t * 11) * 0.012;
    top..add(t)..add(y - 0.021);
    bottom..add(t)..add(y + 0.021);
  }
  final river = <double>[...top];
  for (var i = bottom.length - 2; i >= 0; i -= 2) {
    river..add(bottom[i])..add(bottom[i + 1]);
  }
  river..add(top[0])..add(top[1]);
  add(LayerId.water, true, river, name: 'River');

  // ------------------------------------------------------------------- roads
  // A ring road plus radial avenues reads as a city at a glance.
  final ring = <double>[];
  for (var a = 0.0; a <= math.pi * 2 + 0.01; a += math.pi / 40) {
    ring..add(0.5 + math.cos(a) * 0.315)..add(0.5 + math.sin(a) * 0.315);
  }
  add(LayerId.roadMajor, false, ring, name: 'Ring Road');

  for (var i = 0; i < 6; i++) {
    final a = i * math.pi / 3 + 0.22;
    add(LayerId.roadMajor, false, [
      0.5 + math.cos(a) * 0.03,
      0.5 + math.sin(a) * 0.03,
      0.5 + math.cos(a) * 0.95,
      0.5 + math.sin(a) * 0.95,
    ], name: i == 0 ? 'Grand Avenue' : null);
  }

  for (var i = 1; i < 9; i++) {
    final v = i / 9;
    final jitter = (rnd.nextDouble() - 0.5) * 0.012;
    add(LayerId.roadMedium, false, [-0.05, v + jitter, 1.05, v - jitter]);
    add(LayerId.roadMedium, false, [v + jitter, -0.05, v - jitter, 1.05]);
  }

  for (var i = 0; i < 34; i++) {
    final v = rnd.nextDouble();
    final horizontal = rnd.nextBool();
    final a = rnd.nextDouble() * 0.5;
    final b = a + 0.3 + rnd.nextDouble() * 0.5;
    add(
      LayerId.roadMinor,
      false,
      horizontal ? [a, v, b, v + (rnd.nextDouble() - 0.5) * 0.02] : [v, a, v + (rnd.nextDouble() - 0.5) * 0.02, b],
    );
  }

  for (var i = 0; i < 14; i++) {
    final v = rnd.nextDouble();
    add(LayerId.roadPath, false, [
      v,
      rnd.nextDouble() * 0.4,
      v + (rnd.nextDouble() - 0.5) * 0.18,
      0.4 + rnd.nextDouble() * 0.5,
    ]);
  }

  // A flyover, so the band ordering shows up in the demo too.
  add(LayerId.roadMedium, false, [0.18, 0.86, 0.92, 0.58], band: RoadBand.bridge);

  // --------------------------------------------------------------- buildings
  for (var i = 0; i < 190; i++) {
    final cx = rnd.nextDouble();
    final cy = rnd.nextDouble();
    // Keep the park and the river clear.
    if ((cx - 0.29).abs() < 0.13 && (cy - 0.30).abs() < 0.12) continue;
    if ((cy - (0.70 + math.sin(cx * 5.4) * 0.055)).abs() < 0.035) continue;
    final w = 0.010 + rnd.nextDouble() * 0.026;
    final h = 0.010 + rnd.nextDouble() * 0.026;
    final distance = math.sqrt(math.pow(cx - 0.5, 2) + math.pow(cy - 0.5, 2));
    // Taller towers cluster in the middle, the way most cities work.
    final height = (90 * math.exp(-distance * 5) + rnd.nextDouble() * 22).toDouble();
    add(LayerId.building, true, [
      cx, cy, //
      cx + w, cy, //
      cx + w, cy + h, //
      cx, cy + h, //
      cx, cy, //
    ], height: height);
  }

  // ---------------------------------------------------------------- contours
  if (withContours) {
    for (var level = 1; level <= 7; level++) {
      final ring = <double>[];
      final r = 0.06 + level * 0.035;
      for (var a = 0.0; a <= math.pi * 2 + 0.01; a += math.pi / 24) {
        final wobble = 1 + math.sin(a * 3 + level) * 0.09;
        ring
          ..add(0.86 + math.cos(a) * r * wobble)
          ..add(0.86 + math.sin(a) * r * wobble * 0.8);
      }
      add(LayerId.contour, false, ring, height: level * 10.0);
    }
  }

  features.sort((a, b) => a.layer.index.compareTo(b.layer.index));

  return MapDataSet(
    window: const MapWindow(0.5, 0.5, 7.5e-5),
    bbox: const BBox(-0.0135, -0.0135, 0.0135, 0.0135),
    features: features,
    capturedAt: DateTime(2026),
  );
}
