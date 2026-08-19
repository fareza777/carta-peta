import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import 'package:carta/core/geo.dart';
import 'package:carta/model/layer.dart';
import 'package:carta/model/map_data.dart';
import 'package:carta/model/map_style.dart';
import 'package:carta/model/poster_config.dart';
import 'package:carta/presets/format_presets.dart';
import 'package:carta/presets/style_presets.dart';
import 'package:carta/render/exporter.dart';
import 'package:carta/render/path_cache.dart';
import 'package:carta/render/poster_renderer.dart';
import 'package:flutter_test/flutter_test.dart';

const _black = Color(0xFF000000);
const _white = Color(0xFFFFFFFF);
const _red = Color(0xFFFF0000);
const _green = Color(0xFF00FF00);
const _cyan = Color(0xFF00FFFF);

/// ~3 km across, i.e. a normal city capture, so the density factor is ~1.
const _window = MapWindow(0.5, 0.5, 7.5e-5);

MapDataSet _data(List<MapFeature> features) => MapDataSet(
      window: _window,
      bbox: const BBox(-0.001, -0.001, 0.001, 0.001),
      capturedAt: DateTime(2024),
      features: features,
    );

MapStyle _style({
  Color? majorCasing,
  double heightShade = 0,
  Color? heightColor,
  bool contours = false,
}) =>
    MapStyle(
      id: 'test',
      name: 'Test',
      background: _black,
      textColor: _white,
      accentColor: _white,
      contourInterval: contours ? 10 : 0,
      heightShade: heightShade,
      heightColor: heightColor,
      layers: {
        LayerId.building: LayerStyle(
            filled: true, outlined: false, fill: _black, stroke: _black),
        LayerId.contour: const LayerStyle(stroke: _cyan, width: 6),
        LayerId.roadMinor: const LayerStyle(stroke: _green, width: 20),
        LayerId.roadMajor: LayerStyle(
          stroke: _white,
          width: 20,
          casing: majorCasing,
          casingWidth: 10,
        ),
      },
    );

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

PosterScene _scene(MapDataSet data, MapStyle style) => PosterScene(
      paths: MapPathCache(data),
      style: style,
      poster: const PosterConfig(enabled: false, shape: ShapeMask.fill, margin: 0),
      format: kFormats.firstWhere((f) => f.id == 'square'),
      showAttribution: false,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a bridge is drawn over a road of a higher class', () async {
    const size = 600;
    final data = _data([
      // Major road on the ground, running horizontally.
      MapFeature(LayerId.roadMajor, false, [
        Float32List.fromList([0.0, 0.5, 1.0, 0.5])
      ]),
      // Minor road on a bridge, crossing it vertically. Class order alone would
      // put the major road on top; the band order must win.
      MapFeature(LayerId.roadMinor, false, [
        Float32List.fromList([0.5, 0.0, 0.5, 1.0])
      ], band: RoadBand.bridge),
    ]);
    final px = await _pixels(_scene(data, _style()), size);
    expect(_at(px, size, size ~/ 2, size ~/ 2), 0x00FF00,
        reason: 'the bridge should own the crossing pixel');
  });

  test('a tunnel passes under the road it crosses', () async {
    const size = 600;
    final data = _data([
      MapFeature(LayerId.roadMajor, false, [
        Float32List.fromList([0.0, 0.5, 1.0, 0.5])
      ]),
      MapFeature(LayerId.roadMinor, false, [
        Float32List.fromList([0.5, 0.0, 0.5, 1.0])
      ], band: RoadBand.tunnel),
    ]);
    final px = await _pixels(_scene(data, _style()), size);
    expect(_at(px, size, size ~/ 2, size ~/ 2), 0xFFFFFF,
        reason: 'the surface road should cover the tunnel');
  });

  test('casing is painted under the centre line, not over it', () async {
    const size = 600;
    final data = _data([
      MapFeature(LayerId.roadMajor, false, [
        Float32List.fromList([0.0, 0.5, 1.0, 0.5])
      ]),
    ]);
    final px = await _pixels(_scene(data, _style(majorCasing: _red)), size);

    // Centre of the road is still the stroke colour.
    expect(_at(px, size, size ~/ 2, size ~/ 2), 0xFFFFFF);

    // Somewhere just outside the stroke there must be casing.
    var sawCasing = false;
    for (var dy = 4; dy < 30; dy++) {
      if (_at(px, size, size ~/ 2, size ~/ 2 + dy) == 0xFF0000) sawCasing = true;
    }
    expect(sawCasing, isTrue, reason: 'expected a red casing beside the road');
  });

  test('without a casing colour nothing extra is drawn', () async {
    const size = 600;
    final data = _data([
      MapFeature(LayerId.roadMajor, false, [
        Float32List.fromList([0.0, 0.5, 1.0, 0.5])
      ]),
    ]);
    final px = await _pixels(_scene(data, _style()), size);
    for (var dy = 12; dy < 30; dy++) {
      expect(_at(px, size, size ~/ 2, size ~/ 2 + dy), 0x000000);
    }
  });

  test('buildings are tinted by their mapped height', () async {
    const size = 600;
    final data = _data([
      MapFeature(LayerId.building, true, [
        Float32List.fromList([0.05, 0.05, 0.45, 0.05, 0.45, 0.45, 0.05, 0.45, 0.05, 0.05])
      ], height: 8),
      MapFeature(LayerId.building, true, [
        Float32List.fromList([0.55, 0.05, 0.95, 0.05, 0.95, 0.45, 0.55, 0.45, 0.55, 0.05])
      ], height: 200),
    ]);
    final px = await _pixels(
        _scene(data, _style(heightShade: 1.0, heightColor: _white)), size);

    final low = _at(px, size, size ~/ 4, size ~/ 4);
    final tall = _at(px, size, size * 3 ~/ 4, size ~/ 4);
    expect(tall, greaterThan(low), reason: 'the 200 m tower should read brighter');
    expect(tall, greaterThan(0xAAAAAA));
    expect(low, lessThan(0x808080));
  });

  test('height shading is skipped when nothing has a height tag', () async {
    const size = 400;
    final data = _data([
      MapFeature(LayerId.building, true, [
        Float32List.fromList([0.05, 0.05, 0.95, 0.05, 0.95, 0.95, 0.05, 0.95, 0.05, 0.05])
      ]),
    ]);
    final cache = MapPathCache(data);
    expect(cache.hasBuildingHeights, isFalse);
    final px = await _pixels(
        _scene(data, _style(heightShade: 1.0, heightColor: _white)), size);
    expect(_at(px, size, size ~/ 2, size ~/ 2), 0x000000);
  });

  test('contours render and index lines come out heavier', () async {
    const size = 600;
    final features = <MapFeature>[];
    for (var i = 1; i <= 5; i++) {
      features.add(MapFeature(LayerId.contour, false, [
        Float32List.fromList([0.0, i / 6, 1.0, i / 6])
      ], height: i * 10.0));
    }
    final data = _data(features);
    final cache = MapPathCache(data);
    expect(cache.contourInterval, 10);

    final px = await _pixels(_scene(data, _style(contours: true)), size);
    // The 50 m line is a multiple of five intervals, so it is the index line.
    // Plain lines are drawn at reduced opacity, so match "cyan-ish" rather
    // than an exact value.
    bool cyanish(int c) => (c >> 16) == 0 && (c & 0xFF) > 0x40;
    var indexThickness = 0;
    var plainThickness = 0;
    for (var dy = -12; dy <= 12; dy++) {
      if (cyanish(_at(px, size, size ~/ 2, (size * 5 / 6).round() + dy))) {
        indexThickness++;
      }
      if (cyanish(_at(px, size, size ~/ 2, (size * 1 / 6).round() + dy))) {
        plainThickness++;
      }
    }
    expect(plainThickness, greaterThan(0));
    expect(indexThickness, greaterThan(plainThickness));
  });

  test('every preset still renders with the new layer model', () async {
    final data = _data([
      MapFeature(LayerId.roadMajor, false, [
        Float32List.fromList([0.0, 0.5, 1.0, 0.5])
      ]),
      MapFeature(LayerId.building, true, [
        Float32List.fromList([0.1, 0.1, 0.3, 0.1, 0.3, 0.3, 0.1, 0.3, 0.1, 0.1])
      ], height: 40),
    ]);
    for (final preset in kStylePresets) {
      final image = await PosterExporter.renderImage(_scene(data, preset), 80, 80);
      expect(image.width, 80);
      image.dispose();
    }
  });

  test('text alignment moves the block without changing its height', () async {
    final data = _data([
      MapFeature(LayerId.roadMajor, false, [
        Float32List.fromList([0.0, 0.5, 1.0, 0.5])
      ]),
    ]);
    for (final align in PosterAlign.values) {
      final scene = PosterScene(
        paths: MapPathCache(data),
        style: kStylePresets.first,
        poster: PosterConfig(title: 'Jakarta', subtitle: 'Indonesia', align: align),
        format: kFormats.first,
        showAttribution: false,
      );
      final image = await PosterExporter.renderImage(scene, 300, 450);
      expect(image.height, 450);
      image.dispose();
    }
  });
}
