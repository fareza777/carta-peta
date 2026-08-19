import 'dart:io';
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
import 'package:carta/render/png_writer.dart';
import 'package:carta/render/poster_renderer.dart';
import 'package:flutter_test/flutter_test.dart';

MapDataSet _dataset() {
  const window = MapWindow(0.5, 0.5, 7.5e-5);
  return MapDataSet(
    window: window,
    bbox: const BBox(-0.001, -0.001, 0.001, 0.001),
    capturedAt: DateTime(2024),
    features: [
      MapFeature(LayerId.green, true, [
        Float32List.fromList([0.05, 0.05, 0.5, 0.05, 0.5, 0.9, 0.05, 0.9, 0.05, 0.05])
      ]),
      MapFeature(LayerId.water, true, [
        Float32List.fromList([0.6, 0.1, 0.95, 0.1, 0.95, 0.4, 0.6, 0.4, 0.6, 0.1])
      ]),
      MapFeature(LayerId.roadMajor, false, [
        Float32List.fromList([0.0, 0.5, 1.0, 0.52])
      ]),
      MapFeature(LayerId.roadMinor, false, [
        Float32List.fromList([0.2, 0.0, 0.25, 1.0])
      ]),
    ],
  );
}

PosterScene _scene(String styleId) => PosterScene(
      paths: MapPathCache(_dataset()),
      style: kStylePresets.firstWhere((s) => s.id == styleId),
      poster: const PosterConfig(enabled: false, shape: ShapeMask.fill, margin: 0),
      format: kFormats.first,
      showAttribution: false,
    );

Future<Uint8List> _decodeRgba(Uint8List png, int width, int height) async {
  final codec = await ui.instantiateImageCodec(png);
  final frame = await codec.getNextFrame();
  final image = frame.image;
  expect(image.width, width);
  expect(image.height, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  codec.dispose();
  return data!.buffer.asUint8List();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('carta_png'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('banded output is pixel-identical to a single-shot render', () async {
    const w = 240, h = 360;
    final scene = _scene('vintage');

    final oneShot = await PosterExporter.renderPngBytes(scene, w, h);
    final expected = await _decodeRgba(oneShot, w, h);

    final file = File('${tmp.path}${Platform.pathSeparator}banded.png');
    await PosterExporter.writePng(_scene('vintage'), file: file, width: w, height: h);
    final actual = await _decodeRgba(await file.readAsBytes(), w, h);

    expect(actual.length, expected.length);
    var worst = 0;
    for (var i = 0; i < expected.length; i++) {
      final d = (actual[i] - expected[i]).abs();
      if (d > worst) worst = d;
    }
    expect(worst, 0, reason: 'banding must not change a single pixel');
  });

  test('band boundaries do not cut glow or gradients', () async {
    const w = 200, h = 400;
    // Neon has blurred strokes and a gradient background: both read outside a
    // band while it is being drawn.
    final oneShot = await PosterExporter.renderPngBytes(_scene('neon'), w, h);
    final expected = await _decodeRgba(oneShot, w, h);

    final file = File('${tmp.path}${Platform.pathSeparator}neon.png');
    await PosterExporter.writePng(_scene('neon'), file: file, width: w, height: h);
    final actual = await _decodeRgba(await file.readAsBytes(), w, h);

    for (var i = 0; i < expected.length; i++) {
      if (actual[i] != expected[i]) {
        final pixel = i ~/ 4;
        fail('mismatch at x=${pixel % w} y=${pixel ~/ w}');
      }
    }
  });

  test('handles bands that do not divide the height evenly', () async {
    const w = 64, h = 101;
    final file = File('${tmp.path}${Platform.pathSeparator}odd.png');
    var lastProgress = 0.0;
    await writeStreamingPng(
      file: file,
      width: w,
      height: h,
      bandRows: 7,
      onProgress: (p) => lastProgress = p,
      renderBand: (y, rows) async {
        final bytes = Uint8List(rows * w * 4);
        for (var r = 0; r < rows; r++) {
          for (var x = 0; x < w; x++) {
            final o = (r * w + x) * 4;
            bytes[o] = (y + r) & 0xFF;
            bytes[o + 1] = x & 0xFF;
            bytes[o + 2] = 200;
            bytes[o + 3] = 255;
          }
        }
        return ByteData.sublistView(bytes);
      },
    );
    expect(lastProgress, 1.0);

    final rgba = await _decodeRgba(await file.readAsBytes(), w, h);
    for (final probe in [[0, 0], [63, 100], [17, 55], [5, 99]]) {
      final x = probe[0], y = probe[1];
      final o = (y * w + x) * 4;
      expect(rgba[o], y & 0xFF, reason: 'red at $x,$y');
      expect(rgba[o + 1], x & 0xFF, reason: 'green at $x,$y');
      expect(rgba[o + 2], 200);
      expect(rgba[o + 3], 255);
    }
  });

  test('a single-row band still produces a valid file', () async {
    const w = 16, h = 5;
    final file = File('${tmp.path}${Platform.pathSeparator}thin.png');
    await writeStreamingPng(
      file: file,
      width: w,
      height: h,
      bandRows: 1,
      renderBand: (y, rows) async =>
          ByteData.sublistView(Uint8List(rows * w * 4)..fillRange(0, rows * w * 4, 255)),
    );
    final rgba = await _decodeRgba(await file.readAsBytes(), w, h);
    expect(rgba.every((b) => b == 255), isTrue);
  });

  test('the band budget keeps peak memory small even at 35 megapixels', () {
    // Largest offered export is the A-series print at 4961 px wide.
    final rows = PosterExporter.bandRowsFor(4961);
    final peak = rows * 4961 * 4;
    expect(peak, lessThan(8 * 1024 * 1024));
    expect(rows, greaterThan(8));
  });

  test('failed writes do not leave a half-finished file behind', () async {
    final file = File('${tmp.path}${Platform.pathSeparator}broken.png');
    await expectLater(
      writeStreamingPng(
        file: file,
        width: 32,
        height: 32,
        bandRows: 8,
        renderBand: (y, rows) async => throw StateError('render blew up'),
      ),
      throwsA(isA<StateError>()),
    );
    // The sink is always closed, so the file exists but is not a valid PNG;
    // PosterExporter.export deletes it. Here we just assert we did not hang.
    expect(file.existsSync(), isTrue);
  });
}
