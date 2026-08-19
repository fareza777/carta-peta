import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:http/http.dart' as http;

import '../../core/geo.dart';

/// An elevation grid stitched from Terrarium DEM tiles.
///
/// The grid is uniform in Web Mercator, which is the same space the poster
/// window lives in, so grid coordinates map to window-local coordinates with a
/// scale and an offset and no trigonometry at all.
class ElevationGrid {
  final Float32List values;
  final int width;
  final int height;

  /// Window-local position of the grid's top-left sample.
  final double originLocalX;
  final double originLocalY;

  /// Window-local size of one grid step.
  final double stepLocal;

  const ElevationGrid({
    required this.values,
    required this.width,
    required this.height,
    required this.originLocalX,
    required this.originLocalY,
    required this.stepLocal,
  });

  ({double min, double max}) get relief {
    var lo = double.infinity;
    var hi = -double.infinity;
    for (final v in values) {
      if (v.isNaN) continue;
      if (v < lo) lo = v;
      if (v > hi) hi = v;
    }
    if (lo > hi) return (min: 0, max: 0);
    return (min: lo, max: hi);
  }
}

class TerrainUnavailable implements Exception {
  final String message;
  TerrainUnavailable(this.message);
  @override
  String toString() => message;
}

/// Downloads and decodes public-domain Terrarium elevation tiles.
///
/// Terrarium encodes height as `(R * 256 + G + B / 256) - 32768` metres. The
/// tiles are served without an API key, which keeps the app free of paid
/// infrastructure.
class TerrainTileClient {
  TerrainTileClient({http.Client? client}) : _client = client ?? http.Client();

  static const _base = 'https://s3.amazonaws.com/elevation-tiles-prod/terrarium';
  static const _userAgent = 'CARTA-MapArtStudio/1.0 (Android)';
  static const int tileSize = 256;
  static const int maxTiles = 16;

  final http.Client _client;

  /// Picks a zoom that covers the box with roughly two tiles across.
  static int zoomFor(BBox box) {
    final widthDeg = (box.east - box.west).abs().clamp(1e-6, 360.0);
    final z = (math.log(2 * 360 / widthDeg) / math.ln2).round();
    return z.clamp(8, 14);
  }

  Future<ElevationGrid> load(BBox box, MapWindow window) async {
    final z = zoomFor(box);
    final scale = tileSize * (1 << z);

    final x0 = (Mercator.x(box.west) * (1 << z)).floor();
    final x1 = (Mercator.x(box.east) * (1 << z)).floor();
    final y0 = (Mercator.y(box.north) * (1 << z)).floor();
    final y1 = (Mercator.y(box.south) * (1 << z)).floor();

    final cols = x1 - x0 + 1;
    final rows = y1 - y0 + 1;
    if (cols <= 0 || rows <= 0 || cols * rows > maxTiles) {
      throw TerrainUnavailable('Terrain area too large at this zoom.');
    }

    final width = cols * tileSize;
    final height = rows * tileSize;
    final values = Float32List(width * height);
    var loaded = 0;

    for (var ty = 0; ty < rows; ty++) {
      for (var tx = 0; tx < cols; tx++) {
        final tile = await _tile(z, x0 + tx, y0 + ty);
        if (tile == null) continue;
        loaded++;
        for (var py = 0; py < tileSize; py++) {
          final dst = (ty * tileSize + py) * width + tx * tileSize;
          final src = py * tileSize * 4;
          for (var px = 0; px < tileSize; px++) {
            final o = src + px * 4;
            values[dst + px] =
                (tile[o] * 256.0 + tile[o + 1] + tile[o + 2] / 256.0) - 32768.0;
          }
        }
      }
    }

    if (loaded == 0) {
      throw TerrainUnavailable('No elevation data available here.');
    }

    return ElevationGrid(
      values: values,
      width: width,
      height: height,
      originLocalX: (x0 * tileSize / scale - window.originX) / window.span,
      originLocalY: (y0 * tileSize / scale - window.originY) / window.span,
      stepLocal: 1.0 / scale / window.span,
    );
  }

  Future<Uint8List?> _tile(int z, int x, int y) async {
    final max = 1 << z;
    if (x < 0 || y < 0 || x >= max || y >= max) return null;
    try {
      final res = await _client
          .get(Uri.parse('$_base/$z/$x/$y.png'),
              headers: const {'User-Agent': _userAgent})
          .timeout(const Duration(seconds: 25));
      if (res.statusCode != 200 || res.bodyBytes.length < 100) return null;
      final codec = await ui.instantiateImageCodec(res.bodyBytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      try {
        if (image.width != tileSize || image.height != tileSize) return null;
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        return data?.buffer.asUint8List();
      } finally {
        image.dispose();
        codec.dispose();
      }
    } catch (_) {
      return null;
    }
  }

  void close() => _client.close();
}
