import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:gal/gal.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'pdf_writer.dart';
import 'png_writer.dart';
import 'poster_renderer.dart';

enum ExportFormat { png, jpeg, pdf }

extension ExportFormatInfo on ExportFormat {
  String get extension => switch (this) {
        ExportFormat.png => 'png',
        ExportFormat.jpeg => 'jpg',
        ExportFormat.pdf => 'pdf',
      };

  String get label => switch (this) {
        ExportFormat.png => 'PNG',
        ExportFormat.jpeg => 'JPEG',
        ExportFormat.pdf => 'PDF',
      };

  String get hint => switch (this) {
        ExportFormat.png => 'Lossless, best for printing and archiving',
        ExportFormat.jpeg => 'Small file for sharing, up to 8 MP',
        ExportFormat.pdf => 'Print-ready page at 300 DPI',
      };

  bool get goesToGallery => this != ExportFormat.pdf;
}

class ExportResult {
  final String filePath;
  final int bytes;
  final int width;
  final int height;
  final ExportFormat format;
  final bool savedToGallery;
  const ExportResult({
    required this.filePath,
    required this.bytes,
    required this.width,
    required this.height,
    required this.format,
    required this.savedToGallery,
  });
}

class ExportException implements Exception {
  final String message;
  ExportException(this.message);
  @override
  String toString() => message;
}

/// Renders a [PosterScene] at arbitrary resolution and hands the file to the
/// gallery or share sheet. Rendering is resolution independent, so a 4K export
/// is pixel-for-pixel the same artwork as the preview.
class PosterExporter {
  /// Roughly how many bytes of RGBA to hold at once while exporting. Small
  /// enough that a 35 megapixel poster still fits comfortably on a phone.
  static const int _bandBudgetBytes = 4 * 1024 * 1024;

  /// JPEG has no streaming encoder available to us, so it needs the whole
  /// bitmap in memory. Above this it is not worth the risk on a phone.
  static const int jpegMaxPixels = 8000000;

  static const double printDpi = 300;

  static ui.Picture _record(PosterScene scene, int width, int height) {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(
        recorder, Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()));
    PosterRenderer.paint(canvas, Size(width.toDouble(), height.toDouble()), scene);
    return recorder.endRecording();
  }

  static Future<ui.Image> renderImage(PosterScene scene, int width, int height) async {
    final picture = _record(scene, width, height);
    try {
      return await picture.toImage(width, height);
    } finally {
      picture.dispose();
    }
  }

  /// Whole-image encode. Only safe for small sizes: thumbnails and tests.
  static Future<Uint8List> renderPngBytes(PosterScene scene, int width, int height) async {
    final image = await renderImage(scene, width, height);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw ExportException('Could not encode the image.');
      return data.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  static int bandRowsFor(int width) {
    final rows = _bandBudgetBytes ~/ (width * 4);
    return rows.clamp(8, 512);
  }

  /// Rasterises one horizontal strip of an already-recorded picture. The whole
  /// display list is replayed with a translation rather than clipped, so blurs
  /// and gradients that straddle a band boundary still come out right.
  static Future<ByteData> _rasterBand(
      ui.Picture picture, int width, int y, int rows) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(
        recorder, Rect.fromLTWH(0, 0, width.toDouble(), rows.toDouble()));
    canvas.translate(0, -y.toDouble());
    canvas.drawPicture(picture);
    final band = recorder.endRecording();
    try {
      final image = await band.toImage(width, rows);
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        if (data == null) throw ExportException('Could not read rendered pixels.');
        return data;
      } finally {
        image.dispose();
      }
    } finally {
      band.dispose();
    }
  }

  /// Writes [scene] to [file] band by band. Separate from [export] so it can
  /// run without any platform plugins.
  static Future<void> writePng(
    PosterScene scene, {
    required File file,
    required int width,
    required int height,
    void Function(double progress)? onProgress,
  }) async {
    final picture = _record(scene, width, height);
    try {
      await writeStreamingPng(
        file: file,
        width: width,
        height: height,
        bandRows: bandRowsFor(width),
        renderBand: (y, rows) => _rasterBand(picture, width, y, rows),
        onProgress: onProgress,
      );
    } finally {
      picture.dispose();
    }
  }

  static Future<void> writePdf(
    PosterScene scene, {
    required File file,
    required int width,
    required int height,
    void Function(double progress)? onProgress,
  }) async {
    final picture = _record(scene, width, height);
    try {
      await writeStreamingPdf(
        file: file,
        width: width,
        height: height,
        bandRows: bandRowsFor(width),
        dpi: printDpi,
        renderBand: (y, rows) => _rasterBand(picture, width, y, rows),
        onProgress: onProgress,
      );
    } finally {
      picture.dispose();
    }
  }

  static Future<void> writeJpeg(
    PosterScene scene, {
    required File file,
    required int width,
    required int height,
    int quality = 92,
    void Function(double progress)? onProgress,
  }) async {
    if (width * height > jpegMaxPixels) {
      throw ExportException(
          'JPEG is limited to 8 megapixels. Pick PNG for larger sizes.');
    }
    final image = await renderImage(scene, width, height);
    try {
      onProgress?.call(0.4);
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) throw ExportException('Could not read rendered pixels.');
      final frame = img.Image.fromBytes(
        width: width,
        height: height,
        bytes: data.buffer,
        numChannels: 4,
      );
      onProgress?.call(0.7);
      await file.writeAsBytes(img.encodeJpg(frame, quality: quality), flush: true);
      onProgress?.call(1.0);
    } finally {
      image.dispose();
    }
  }

  /// Writes the poster and, for image formats, tries to add it to the device
  /// gallery. [onProgress] reports 0..1 as bands complete.
  static Future<ExportResult> export(
    PosterScene scene, {
    required int width,
    required int height,
    required String baseName,
    ExportFormat format = ExportFormat.png,
    bool toGallery = true,
    void Function(double progress)? onProgress,
  }) async {
    final dir = await getApplicationDocumentsDirectory();
    final exports = Directory('${dir.path}${Platform.pathSeparator}exports');
    if (!await exports.exists()) await exports.create(recursive: true);
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final path = '${exports.path}${Platform.pathSeparator}'
        '${_slug(baseName)}_$stamp.${format.extension}';
    final file = File(path);

    try {
      switch (format) {
        case ExportFormat.png:
          await writePng(scene,
              file: file, width: width, height: height, onProgress: onProgress);
        case ExportFormat.pdf:
          await writePdf(scene,
              file: file, width: width, height: height, onProgress: onProgress);
        case ExportFormat.jpeg:
          await writeJpeg(scene,
              file: file, width: width, height: height, onProgress: onProgress);
      }
    } on ExportException {
      await _deleteQuietly(file);
      rethrow;
    } on OutOfMemoryError {
      await _deleteQuietly(file);
      throw ExportException(
          'This device ran out of memory at this size. Try a smaller resolution.');
    } catch (e) {
      await _deleteQuietly(file);
      throw ExportException('Could not render at $width x $height: $e');
    }

    final size = await file.length();

    var saved = false;
    if (toGallery && format.goesToGallery) {
      try {
        if (!await Gal.hasAccess(toAlbum: true)) {
          await Gal.requestAccess(toAlbum: true);
        }
        await Gal.putImage(path, album: 'CARTA');
        saved = true;
      } catch (_) {
        saved = false;
      }
    }

    return ExportResult(
      filePath: path,
      bytes: size,
      width: width,
      height: height,
      format: format,
      savedToGallery: saved,
    );
  }

  static Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {
      // nothing useful to do
    }
  }

  static Future<void> share(String path, String title) async {
    await Share.shareXFiles([XFile(path)], text: '$title - made with CARTA');
  }

  /// Small preview bitmap stored alongside a saved design.
  static Future<Uint8List> thumbnail(PosterScene scene, {int width = 420}) async {
    final height = (width / scene.format.aspect).round();
    return renderPngBytes(scene, width, height);
  }

  static String _slug(String s) {
    final cleaned = s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    final trimmed = cleaned.replaceAll(RegExp(r'^-+|-+$'), '');
    return trimmed.isEmpty ? 'carta' : trimmed;
  }
}
