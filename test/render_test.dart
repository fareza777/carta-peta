import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:carta/core/geo.dart';
import 'package:carta/model/layer.dart';
import 'package:carta/model/map_data.dart';
import 'package:carta/model/poster_config.dart';
import 'package:carta/presets/format_presets.dart';
import 'package:carta/presets/style_presets.dart';
import 'package:carta/render/exporter.dart';
import 'package:carta/render/path_cache.dart';
import 'package:carta/render/poster_renderer.dart';
import 'package:flutter_test/flutter_test.dart';

MapDataSet _dataset() {
  // ~3 km across at the equator, i.e. a typical city capture.
  const window = MapWindow(0.5, 0.5, 7.5e-5);
  return MapDataSet(
    window: window,
    bbox: const BBox(-0.001, -0.001, 0.001, 0.001),
    capturedAt: DateTime(2024),
    features: [
      // A park filling the left half.
      MapFeature(LayerId.green, true, [
        Float32List.fromList([0.0, 0.0, 0.5, 0.0, 0.5, 1.0, 0.0, 1.0, 0.0, 0.0])
      ]),
      // A road straight across the middle.
      MapFeature(LayerId.roadMajor, false, [
        Float32List.fromList([0.0, 0.5, 1.0, 0.5])
      ]),
    ],
  );
}

PosterScene _scene({ShapeMask shape = ShapeMask.fill, double margin = 0}) => PosterScene(
      paths: MapPathCache(_dataset()),
      style: kStylePresets.firstWhere((s) => s.id == 'oled'),
      poster: PosterConfig(enabled: false, shape: shape, margin: margin),
      format: kFormats.first,
      showAttribution: false,
    );

Future<ByteData> _pixels(PosterScene scene, int w, int h) async {
  final image = await PosterExporter.renderImage(scene, w, h);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return data!;
}

int _at(ByteData px, int w, int x, int y) {
  final o = (y * w + x) * 4;
  return (px.getUint8(o) << 16) | (px.getUint8(o + 1) << 8) | px.getUint8(o + 2);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('renders the style background', () async {
    const w = 600, h = 900;
    final px = await _pixels(_scene(), w, h);
    // The right half of the window has no features: pure OLED black.
    expect(_at(px, w, w - 4, 4), 0x000000);
  });

  test('draws roads over the background', () async {
    const w = 600, h = 900;
    final px = await _pixels(_scene(), w, h);
    // The road runs through the middle of the map window, which a full-bleed
    // square window places at the centre of the canvas.
    var found = false;
    for (var y = h ~/ 2 - 6; y <= h ~/ 2 + 6; y++) {
      if (_at(px, w, w ~/ 2, y) > 0x666666) found = true;
    }
    expect(found, isTrue, reason: 'expected a bright road pixel near the centre');
  });

  test('fills area layers', () async {
    const w = 600, h = 900;
    final px = await _pixels(_scene(), w, h);
    final left = _at(px, w, 12, h ~/ 4);
    final right = _at(px, w, w - 12, h ~/ 4);
    expect(left, isNot(right), reason: 'the park half should differ from bare background');
  });

  test('margins paint the paper colour outside the map', () async {
    const w = 200, h = 300;
    final scene = _scene(shape: ShapeMask.rectangle, margin: 0.12);
    final px = await _pixels(scene, w, h);
    // The corner sits outside the map rectangle: bare background.
    expect(_at(px, w, 2, 2), 0x000000);
  });

  test('every bundled preset renders without throwing', () async {
    for (final preset in kStylePresets) {
      final scene = PosterScene(
        paths: MapPathCache(_dataset()),
        style: preset,
        poster: const PosterConfig(enabled: false, shape: ShapeMask.fill, margin: 0),
        format: kFormats.first,
        showAttribution: false,
      );
      final image = await PosterExporter.renderImage(scene, 60, 90);
      expect(image.width, 60);
      image.dispose();
    }
  });

  test('every shape mask renders', () async {
    for (final shape in ShapeMask.values) {
      final image = await PosterExporter.renderImage(
          _scene(shape: shape, margin: 0.08), 60, 90);
      expect(image.height, 90);
      image.dispose();
    }
  });

  test('exports a real PNG at high resolution', () async {
    final bytes = await PosterExporter.renderPngBytes(_scene(), 1200, 1800);
    expect(bytes.length, greaterThan(1000));
    // PNG magic number.
    expect(bytes.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
  });

  test('preset ids are unique', () {
    final ids = kStylePresets.map((s) => s.id).toSet();
    expect(ids.length, kStylePresets.length);
  });
}
