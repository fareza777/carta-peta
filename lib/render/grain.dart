import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

/// A tileable film-grain bitmap, generated once at launch and reused by both
/// the live preview and the full-resolution export.
///
/// Three octaves of value noise rather than raw white noise: a smooth low
/// frequency gives the blotchy unevenness of real paper, the high frequency
/// gives the speckle. Straight `Random()` per pixel looks like TV static.
class GrainTexture {
  static ui.Image? _image;
  static Future<void>? _pending;
  static const int size = 512;

  static ui.Image? get image => _image;

  static Future<void> ensureLoaded() {
    if (_image != null) return Future.value();
    return _pending ??= _generate();
  }

  /// Bilinear value noise from a wrapping lattice of [cells] x [cells].
  static Float32List _octave(int cells, Random rnd) {
    final lattice = Float32List(cells * cells);
    for (var i = 0; i < lattice.length; i++) {
      lattice[i] = rnd.nextDouble();
    }
    final out = Float32List(size * size);
    final step = cells / size;
    for (var y = 0; y < size; y++) {
      final fy = y * step;
      final y0 = fy.floor();
      final ty = fy - y0;
      final ry0 = (y0 % cells) * cells;
      final ry1 = ((y0 + 1) % cells) * cells;
      for (var x = 0; x < size; x++) {
        final fx = x * step;
        final x0 = fx.floor();
        final tx = fx - x0;
        final rx0 = x0 % cells;
        final rx1 = (x0 + 1) % cells;
        // Smoothstep keeps the lattice from showing through as a grid.
        final sx = tx * tx * (3 - 2 * tx);
        final sy = ty * ty * (3 - 2 * ty);
        final top = lattice[ry0 + rx0] * (1 - sx) + lattice[ry0 + rx1] * sx;
        final bottom = lattice[ry1 + rx0] * (1 - sx) + lattice[ry1 + rx1] * sx;
        out[y * size + x] = top * (1 - sy) + bottom * sy;
      }
    }
    return out;
  }

  static Future<void> _generate() async {
    final rnd = Random(9241);
    final coarse = _octave(16, rnd);
    final mid = _octave(64, rnd);
    final pixels = Uint8List(size * size * 4);

    for (var i = 0; i < size * size; i++) {
      final fine = rnd.nextDouble();
      final v = (128 +
              (coarse[i] - 0.5) * 46 +
              (mid[i] - 0.5) * 64 +
              (fine - 0.5) * 74)
          .clamp(0.0, 255.0)
          .toInt();
      final o = i * 4;
      pixels[o] = v;
      pixels[o + 1] = v;
      pixels[o + 2] = v;
      pixels[o + 3] = 255;
    }

    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(pixels, size, size, ui.PixelFormat.rgba8888, completer.complete);
    _image = await completer.future;
    _pending = null;
  }
}
