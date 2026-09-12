import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:carta/core/geo.dart';
import 'package:carta/model/area_boundary.dart';
import 'package:carta/model/layer.dart';
import 'package:carta/model/map_data.dart';
import 'package:carta/model/map_style.dart';
import 'package:carta/model/place.dart';
import 'package:carta/model/poster_config.dart';
import 'package:carta/presets/format_presets.dart';
import 'package:carta/render/exporter.dart';
import 'package:carta/render/path_cache.dart';
import 'package:carta/render/poster_renderer.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

const _black = Color(0xFF000000);
const _white = Color(0xFFFFFFFF);
const _amber = Color(0xFFFFC400);

/// ~3 km across, so stroke widths behave like a normal city capture.
const _window = MapWindow(0.5, 0.5, 7.5e-5);

/// A white grid covering the whole window: any dimming is then obvious.
MapDataSet _grid() {
  final features = <MapFeature>[];
  for (var i = 1; i < 10; i++) {
    final t = i / 10;
    features.add(MapFeature(LayerId.roadMajor, false, [
      Float32List.fromList([0.0, t, 1.0, t])
    ]));
    features.add(MapFeature(LayerId.roadMajor, false, [
      Float32List.fromList([t, 0.0, t, 1.0])
    ]));
  }
  return MapDataSet(
    window: _window,
    bbox: const BBox(-0.001, -0.001, 0.001, 0.001),
    capturedAt: DateTime(2024),
    features: features,
  );
}

MapStyle _style({double dim = 0.8, double tint = 0, double outline = 0}) => MapStyle(
      id: 'test',
      name: 'Test',
      background: _black,
      textColor: _white,
      accentColor: _amber,
      highlightDim: dim,
      highlightTint: tint,
      highlightWidth: outline,
      layers: const {
        LayerId.roadMajor: LayerStyle(stroke: _white, width: 24),
      },
    );

/// A square ring occupying the middle half of the window.
AreaBoundary _centreSquare() {
  // The window's origin is its top-left corner, so the middle half runs from a
  // quarter to three quarters of the span. Converting back to lat/lon keeps the
  // test honest about the projection.
  const span = 7.5e-5;
  final x0 = 0.5 + span * 0.25, x1 = 0.5 + span * 0.75;
  final y0 = 0.5 + span * 0.25, y1 = 0.5 + span * 0.75;
  final north = Mercator.lat(y0), south = Mercator.lat(y1);
  final west = Mercator.lon(x0), east = Mercator.lon(x1);
  return AreaBoundary(name: 'Middle', rings: [
    [
      LatLng(south, west),
      LatLng(south, east),
      LatLng(north, east),
      LatLng(north, west),
      LatLng(south, west),
    ]
  ]);
}

Future<ByteData> _pixels(PosterScene scene, int size) async {
  final image = await PosterExporter.renderImage(scene, size, size);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return data!;
}

int _at(ByteData px, int size, int x, int y) {
  final o = (y * size + x) * 4;
  return (px.getUint8(o) << 16) | (px.getUint8(o + 1) << 8) | px.getUint8(o + 2);
}

int _luma(int rgb) =>
    (((rgb >> 16) & 0xFF) * 30 + ((rgb >> 8) & 0xFF) * 59 + (rgb & 0xFF) * 11) ~/ 100;

PosterScene _scene(MapDataSet data, MapStyle style, {AreaBoundary? highlight}) =>
    PosterScene(
      paths: MapPathCache(data),
      style: style,
      poster: const PosterConfig(enabled: false, shape: ShapeMask.fill, margin: 0),
      format: kFormats.firstWhere((f) => f.id == 'square'),
      highlight: highlight,
      showAttribution: false,
    );

/// The brightest pixel in a small box, so a test does not depend on landing
/// exactly on a one-pixel-wide stroke.
int _brightest(ByteData px, int size, int cx, int cy, int radius) {
  var best = 0;
  for (var y = cy - radius; y <= cy + radius; y++) {
    for (var x = cx - radius; x <= cx + radius; x++) {
      if (x < 0 || y < 0 || x >= size || y >= size) continue;
      final l = _luma(_at(px, size, x, y));
      if (l > best) best = l;
    }
  }
  return best;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AreaBoundary', () {
    test('reads a Polygon and keeps only its outer ring', () {
      final geometry = jsonDecode('''
        {"type":"Polygon","coordinates":[
          [[106.84,-6.24],[106.85,-6.24],[106.85,-6.22],[106.84,-6.22],[106.84,-6.24]],
          [[106.845,-6.235],[106.846,-6.235],[106.846,-6.234],[106.845,-6.235]]
        ]}''');
      final area = AreaBoundary.fromGeoJson('Tebet Barat', geometry);
      expect(area, isNotNull);
      expect(area!.rings, hasLength(1), reason: 'the hole must be dropped');
      expect(area.rings.first, hasLength(5));
      expect(area.name, 'Tebet Barat');
    });

    test('reads every part of a MultiPolygon', () {
      final geometry = jsonDecode('''
        {"type":"MultiPolygon","coordinates":[
          [[[0,0],[1,0],[1,1],[0,0]]],
          [[[5,5],[6,5],[6,6],[5,5]]]
        ]}''');
      final area = AreaBoundary.fromGeoJson('Split village', geometry);
      expect(area!.rings, hasLength(2));
    });

    test('refuses geometry that cannot be drawn', () {
      expect(AreaBoundary.fromGeoJson('x', null), isNull);
      expect(AreaBoundary.fromGeoJson('x', jsonDecode('{"type":"Point","coordinates":[1,2]}')),
          isNull);
      // A ring of two points is a line, not an area.
      expect(
          AreaBoundary.fromGeoJson(
              'x', jsonDecode('{"type":"Polygon","coordinates":[[[0,0],[1,1]]]}')),
          isNull);
    });

    test('suggests a radius that frames the whole area', () {
      // The real outline of Tebet Barat, Jakarta: roughly 1.06 x 2.13 km.
      final area = AreaBoundary(name: 'Tebet Barat', rings: [
        const [
          LatLng(-6.24330, 106.84388),
          LatLng(-6.24330, 106.85346),
          LatLng(-6.22414, 106.85346),
          LatLng(-6.22414, 106.84388),
          LatLng(-6.24330, 106.84388),
        ]
      ]);
      final r = area.suggestedRadius;
      expect(r, greaterThan(1060), reason: 'must cover the long axis');
      expect(r, lessThan(1800));
      expect(area.centre.lat, closeTo(-6.2337, 0.002));
    });

    test('survives a round trip through JSON', () {
      final area = _centreSquare();
      final back = AreaBoundary.fromJson(
          Map<String, dynamic>.from(jsonDecode(jsonEncode(area.toJson())) as Map));
      expect(back.name, area.name);
      expect(back.rings.first.length, area.rings.first.length);
      expect(back.rings.first.first.lat, closeTo(area.rings.first.first.lat, 1e-9));
    });

    test('projects into the window the renderer draws in', () {
      final rings = _centreSquare().project(_window);
      expect(rings, hasLength(1));
      final flat = rings.first;
      for (var i = 0; i < flat.length; i += 2) {
        expect(flat[i], closeTo(flat[i] < 0.5 ? 0.25 : 0.75, 0.01));
        expect(flat[i + 1], closeTo(flat[i + 1] < 0.5 ? 0.25 : 0.75, 0.01));
      }
    });
  });

  group('highlight rendering', () {
    test('dims the map outside the area and leaves the inside alone', () async {
      const size = 600;
      final data = _grid();
      final plain = await _pixels(_scene(data, _style()), size);
      final lifted =
          await _pixels(_scene(data, _style(), highlight: _centreSquare()), size);

      // A road crossing well outside the square, and one inside it.
      final outside = (size * 0.1).round();
      final inside = (size * 0.5).round();

      expect(_brightest(plain, size, outside, outside, 6), greaterThan(200),
          reason: 'the grid must be bright before any dimming');
      expect(_brightest(lifted, size, outside, outside, 6), lessThan(120),
          reason: 'outside the area the map should fade back');
      expect(_brightest(lifted, size, inside, inside, 6),
          closeTo(_brightest(plain, size, inside, inside, 6), 4),
          reason: 'inside the area nothing should change');
    });

    test('stronger dimming fades the surroundings further', () async {
      const size = 400;
      final data = _grid();
      final soft = await _pixels(
          _scene(data, _style(dim: 0.3), highlight: _centreSquare()), size);
      final hard = await _pixels(
          _scene(data, _style(dim: 1.0), highlight: _centreSquare()), size);
      final x = (size * 0.1).round();
      expect(_brightest(hard, size, x, x, 5),
          lessThan(_brightest(soft, size, x, x, 5)));
    });

    test('no highlight means no scrim at all', () async {
      const size = 300;
      final data = _grid();
      final a = await _pixels(_scene(data, _style(dim: 1.0)), size);
      final b = await _pixels(_scene(data, _style(dim: 0.0)), size);
      final x = (size * 0.1).round();
      expect(_brightest(a, size, x, x, 4), _brightest(b, size, x, x, 4));
    });

    test('the outline is drawn in the highlight colour', () async {
      const size = 600;
      final px = await _pixels(
        _scene(_grid(), _style(dim: 0.9, outline: 6), highlight: _centreSquare()),
        size,
      );
      // Walk down the left edge of the square looking for amber.
      final edge = (size * 0.25).round();
      var sawAmber = false;
      for (var y = (size * 0.3).round(); y < (size * 0.7).round(); y++) {
        for (var x = edge - 5; x <= edge + 5; x++) {
          final rgb = _at(px, size, x, y);
          final r = (rgb >> 16) & 0xFF, g = (rgb >> 8) & 0xFF, b = rgb & 0xFF;
          if (r > 180 && g > 120 && b < 90) sawAmber = true;
        }
      }
      expect(sawAmber, isTrue, reason: 'expected the amber outline on the ring');
    });

    test('the tint lifts the inside without touching the roads', () async {
      const size = 400;
      final data = _grid();
      final plain = await _pixels(_scene(data, _style(tint: 0)), size);
      final tinted = await _pixels(
          _scene(data, _style(tint: 1.0), highlight: _centreSquare()), size);
      // A point inside the square but between two grid roads.
      final x = (size * 0.45).round(), y = (size * 0.45).round();
      expect(_luma(_at(tinted, size, x, y)),
          greaterThan(_luma(_at(plain, size, x, y)) + 8));
    });
  });

  test('a highlighted design keeps its outline through the library', () {
    final area = _centreSquare();
    final scene = PosterScene(
      style: _style(),
      poster: const PosterConfig(),
      format: kFormats.first,
      highlight: area,
      place: const PlaceRef(
          name: 'Middle', context: '', country: '', centre: LatLng(0, 0)),
    );
    // Without map data there is nothing to project onto, which must be a null
    // path rather than a crash.
    expect(scene.highlightPath, isNull);
  });
}
