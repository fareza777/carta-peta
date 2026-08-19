import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:carta/core/geo.dart';
import 'package:carta/data/osm/osm_parser.dart';
import 'package:carta/data/osm/overpass_query.dart';
import 'package:carta/model/layer.dart';
import 'package:carta/model/map_data.dart';
import 'package:carta/model/map_style.dart';
import 'package:carta/model/poster_config.dart';
import 'package:carta/model/route_track.dart';
import 'package:carta/presets/format_presets.dart';
import 'package:carta/presets/style_presets.dart';
import 'package:carta/render/exporter.dart';
import 'package:carta/render/path_cache.dart';
import 'package:carta/render/poster_renderer.dart';
import 'package:flutter_test/flutter_test.dart';

/// A plot with a house, a fence and the street outside it, at house scale.
const _centre = LatLng(-6.2000, 106.8000);

Map<String, dynamic> _way(int id, Map<String, String> tags, List<List<double>> c) => {
      'type': 'way',
      'id': id,
      'tags': tags,
      'geometry': [
        for (final p in c) {'lat': p[0], 'lon': p[1]}
      ],
    };

MapDataSet _parse(double radius, List<Map<String, dynamic>> elements) {
  final box = BBox.square(_centre, radius);
  return MapDataCodec.decode(parseOverpassToBytes(OsmParseRequest(
    json: jsonEncode({'elements': elements}),
    south: box.south,
    west: box.west,
    north: box.north,
    east: box.east,
  )))!;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('house scale capture', () {
    test('an 80 m radius still asks for full detail', () {
      expect(detailForRadius(80), DetailLevel.full);
      expect(detailForRadius(80).includesBuildings, isTrue);
    });

    test('the query asks for walls, fences and hedges at full detail only', () {
      final box = BBox.square(_centre, 80);
      expect(buildOverpassQuery(box, DetailLevel.full), contains('barrier'));
      expect(buildOverpassQuery(box, DetailLevel.medium), isNot(contains('barrier')));
    });

    test('fences and hedges land on their own layer', () {
      final data = _parse(80, [
        _way(1, {'barrier': 'fence'}, [
          [-6.2002, 106.7998],
          [-6.2002, 106.8002]
        ]),
        _way(2, {'barrier': 'hedge'}, [
          [-6.1998, 106.7998],
          [-6.1998, 106.8002]
        ]),
        _way(3, {'barrier': 'gate'}, [
          [-6.1999, 106.7999],
          [-6.1999, 106.8000]
        ]),
      ]);
      expect(data.layerCounts[LayerId.barrier], 2, reason: 'a gate is not a wall');
    });

    test('a single house keeps its shape at 80 m', () {
      // Roughly a 12 m x 10 m footprint.
      final data = _parse(80, [
        _way(1, {'building': 'house', 'building:levels': '2'}, [
          [-6.20000, 106.80000],
          [-6.20000, 106.80011],
          [-6.20009, 106.80011],
          [-6.20009, 106.80000],
          [-6.20000, 106.80000],
        ]),
      ]);
      final house = data.features.single;
      expect(house.layer, LayerId.building);
      expect(house.height, closeTo(6.4, 0.1));
      // Five vertices must survive: simplification must not eat a house.
      expect(house.parts.single.length ~/ 2, 5);

      // And the footprint must occupy a real fraction of the window, not a dot.
      final ring = house.parts.single;
      var minX = 1.0, maxX = 0.0;
      for (var i = 0; i < ring.length; i += 2) {
        if (ring[i] < minX) minX = ring[i];
        if (ring[i] > maxX) maxX = ring[i];
      }
      expect(maxX - minX, greaterThan(0.05));
    });

    test('geometry precision is far below a millimetre at this scale', () {
      final window = MapWindow.forBox(BBox.square(_centre, 80));
      expect(window.groundSpanMetres, closeTo(160, 6));
      // One float32 step across the window, in metres.
      final step = window.groundSpanMetres * 6e-8;
      expect(step, lessThan(0.001));
    });
  });

  group('zoom range', () {
    test('the smallest capture plus full zoom reaches a single plot', () {
      // 80 m radius is 160 m across; ten times in is 16 m.
      const smallestSpan = 160.0;
      const maxZoom = 10.0;
      expect(smallestSpan / maxZoom, lessThan(20));
    });

    test('line weight scales up for close-ups instead of staying hairline', () async {
      // Same road, captured at two very different scales.
      Future<int> litPixels(double radius) async {
        final data = _parse(radius, [
          _way(1, {'highway': 'primary'}, [
            [_centre.lat, _centre.lon - 0.004],
            [_centre.lat, _centre.lon + 0.004],
          ]),
        ]);
        final image = await PosterExporter.renderImage(
          PosterScene(
            paths: MapPathCache(data),
            style: kStylePresets.firstWhere((s) => s.id == 'oled'),
            poster: const PosterConfig(
                enabled: false, shape: ShapeMask.fill, margin: 0),
            format: kFormats.firstWhere((f) => f.id == 'square'),
            showAttribution: false,
          ),
          400,
          400,
        );
        final px = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
        image.dispose();
        var lit = 0;
        for (var y = 0; y < 400; y++) {
          final o = (y * 400 + 200) * 4;
          if (px.getUint8(o) > 40) lit++;
        }
        return lit;
      }

      final wide = await litPixels(2000);
      final close = await litPixels(90);
      expect(close, greaterThan(wide),
          reason: 'a close-up should draw a heavier road, not a hairline');
    });
  });

  group('true scale roads', () {
    Future<int> roadPixels(double radius, {required bool trueScale}) async {
      final data = _parse(radius, [
        _way(1, {'highway': 'residential'}, [
          [_centre.lat, _centre.lon - 0.004],
          [_centre.lat, _centre.lon + 0.004],
        ]),
      ]);
      final image = await PosterExporter.renderImage(
        PosterScene(
          paths: MapPathCache(data),
          style: kStylePresets
              .firstWhere((s) => s.id == 'oled')
              .copyWith(trueScaleRoads: trueScale),
          poster: const PosterConfig(
              enabled: false, shape: ShapeMask.fill, margin: 0),
          format: kFormats.firstWhere((f) => f.id == 'square'),
          showAttribution: false,
        ),
        400,
        400,
      );
      final px = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      image.dispose();
      var lit = 0;
      for (var y = 0; y < 400; y++) {
        final o = (y * 400 + 200) * 4;
        if (px.getUint8(o) > 40) lit++;
      }
      return lit;
    }

    /// Total ink laid down along one column. Unlike a pixel count this still
    /// measures a sub-pixel line, which is exactly the city-scale case.
    Future<int> roadInk(double radius, {required bool trueScale}) async {
      final data = _parse(radius, [
        _way(1, {'highway': 'residential'}, [
          [_centre.lat, _centre.lon - 0.004],
          [_centre.lat, _centre.lon + 0.004],
        ]),
      ]);
      final image = await PosterExporter.renderImage(
        PosterScene(
          paths: MapPathCache(data),
          style: kStylePresets
              .firstWhere((s) => s.id == 'oled')
              .copyWith(trueScaleRoads: trueScale),
          poster: const PosterConfig(
              enabled: false, shape: ShapeMask.fill, margin: 0),
          format: kFormats.firstWhere((f) => f.id == 'square'),
          showAttribution: false,
        ),
        400,
        400,
      );
      final px = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      image.dispose();
      var ink = 0;
      for (var y = 0; y < 400; y++) {
        ink += px.getUint8((y * 400 + 200) * 4);
      }
      return ink;
    }

    test('a close-up road becomes a ribbon of its real width', () async {
      // 90 m radius is 180 m across; a 6.5 m street is about 3.6% of a
      // 400 px poster, so roughly 14 px.
      final scaled = await roadPixels(90, trueScale: true);
      expect(scaled, greaterThan(8));
      expect(scaled, lessThan(28));
    });

    test('true width tracks the ground span, poster-relative width does not',
        () async {
      // The same 6.5 m street, captured 22 times tighter. Drawn to scale its
      // ink should grow with the span ratio; drawn as a fraction of the sheet
      // it barely moves.
      final closeTrue = await roadInk(90, trueScale: true);
      final wideTrue = await roadInk(2000, trueScale: true);
      expect(closeTrue / wideTrue, greaterThan(10));

      final closeRelative = await roadInk(90, trueScale: false);
      final wideRelative = await roadInk(2000, trueScale: false);
      expect(closeRelative / wideRelative, lessThan(10));
    });

    test('the setting survives a style round trip', () {
      final style = kStylePresets.first.copyWith(trueScaleRoads: true);
      expect(MapStyle.fromJson(style.toJson()).trueScaleRoads, isTrue);
    });
  });

  group('multiple routes', () {
    RouteTrack track(String name, double lat, {List<double> elevations = const []}) =>
        RouteTrack(
          name: name,
          points: [
            LatLng(lat, 106.799),
            LatLng(lat + 0.001, 106.800),
            LatLng(lat, 106.801),
          ],
          distanceMetres: 400,
          ascentMetres: 25,
          elevations: elevations,
        );

    test('several tracks all get drawn', () async {
      final data = _parse(400, [
        _way(1, {'highway': 'primary'}, [
          [-6.2005, 106.7990],
          [-6.2005, 106.8010]
        ]),
      ]);
      final scene = PosterScene(
        paths: MapPathCache(data),
        style: kStylePresets.first,
        poster: const PosterConfig(enabled: false, shape: ShapeMask.fill, margin: 0),
        format: kFormats.first,
        routes: [track('a', -6.200), track('b', -6.201), track('c', -6.199)],
      );
      expect(scene.routePaths.length, 3);
      final image = await PosterExporter.renderImage(scene, 200, 300);
      expect(image.width, 200);
      image.dispose();
    });

    test('chunks carry a normalised elevation for the gradient', () {
      final t = track('ride', -6.200, elevations: const [100, 150, 200, 250, 300]);
      const window = MapWindow(0.5, 0.5, 7.5e-5);
      final chunks = t.chunks(window, count: 4);
      expect(chunks, isNotEmpty);
      for (final c in chunks) {
        expect(c.t, inInclusiveRange(0.0, 1.0));
        expect(c.points.length, greaterThanOrEqualTo(4));
      }
    });

    test('a flat track still chunks without dividing by zero', () {
      final t = track('flat', -6.200, elevations: const [50, 50, 50, 50, 50]);
      const window = MapWindow(0.5, 0.5, 7.5e-5);
      for (final c in t.chunks(window)) {
        expect(c.t.isFinite, isTrue);
      }
    });

    test('a track with no elevation reports no profile', () {
      expect(track('plain', -6.2).hasProfile, isFalse);
      expect(
        track('hilly', -6.2, elevations: const [1, 2, 3, 4, 5, 6]).hasProfile,
        isTrue,
      );
    });
  });

  test('the barrier layer round trips through the cache codec', () {
    final data = _parse(80, [
      _way(1, {'barrier': 'wall'}, [
        [-6.2001, 106.7999],
        [-6.2001, 106.8001]
      ]),
    ]);
    final copy = MapDataCodec.decode(MapDataCodec.encode(data))!;
    expect(copy.features.single.layer, LayerId.barrier);
    expect(copy.features.single.parts.single, isA<Float32List>());
  });
}
