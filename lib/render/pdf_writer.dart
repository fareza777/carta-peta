import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Streams a print-ready PDF containing the poster at a real physical size.
///
/// Print shops want a page with correct dimensions, not a bare bitmap, and they
/// want 300 DPI. The image is written as a Flate-compressed XObject fed band by
/// band, so a 35 megapixel A2 sheet never needs more than a few megabytes of
/// memory — the same trick the PNG writer uses.
Future<void> writeStreamingPdf({
  required File file,
  required int width,
  required int height,
  required int bandRows,
  required double dpi,
  required Future<ByteData> Function(int y, int rows) renderBand,
  void Function(double progress)? onProgress,
}) async {
  final sink = file.openWrite();
  var position = 0;
  final offsets = <int, int>{};

  void add(List<int> bytes) {
    sink.add(bytes);
    position += bytes.length;
  }

  void addText(String s) => add(latin1.encode(s));

  void startObject(int id) {
    offsets[id] = position;
    addText('$id 0 obj\n');
  }

  final pageWidth = (width / dpi * 72).toStringAsFixed(2);
  final pageHeight = (height / dpi * 72).toStringAsFixed(2);

  try {
    addText('%PDF-1.4\n');
    // A binary comment marks the file as containing binary data.
    add([0x25, 0xE2, 0xE3, 0xCF, 0xD3, 0x0A]);

    startObject(1);
    addText('<< /Type /Catalog /Pages 2 0 R >>\nendobj\n');

    startObject(2);
    addText('<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n');

    startObject(3);
    addText('<< /Type /Page /Parent 2 0 R '
        '/MediaBox [0 0 $pageWidth $pageHeight] '
        '/Resources << /XObject << /Im0 4 0 R >> >> '
        '/Contents 5 0 R >>\nendobj\n');

    // Image object: length is an indirect reference so the stream can be
    // written before its size is known.
    startObject(4);
    addText('<< /Type /XObject /Subtype /Image /Width $width /Height $height '
        '/ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /FlateDecode '
        '/Length 6 0 R >>\nstream\n');
    final streamStart = position;

    final pending = BytesBuilder(copy: false);
    final deflate = ZLibCodec(level: 6).encoder.startChunkedConversion(
          _CollectSink(pending),
        );

    final rowLength = width * 3;
    final row = Uint8List(rowLength);

    for (var y = 0; y < height; y += bandRows) {
      final rows = (y + bandRows > height) ? height - y : bandRows;
      final band = await renderBand(y, rows);
      final pixels = band.buffer.asUint8List(band.offsetInBytes, rows * width * 4);
      for (var r = 0; r < rows; r++) {
        final base = r * width * 4;
        for (var x = 0; x < width; x++) {
          final src = base + x * 4;
          final dst = x * 3;
          row[dst] = pixels[src];
          row[dst + 1] = pixels[src + 1];
          row[dst + 2] = pixels[src + 2];
        }
        deflate.add(row);
      }
      if (pending.length > 0) add(pending.takeBytes());
      onProgress?.call(((y + rows) / height).clamp(0.0, 1.0));
      await Future<void>.delayed(Duration.zero);
    }

    deflate.close();
    if (pending.length > 0) add(pending.takeBytes());
    final streamLength = position - streamStart;
    addText('\nendstream\nendobj\n');

    final content = 'q $pageWidth 0 0 $pageHeight 0 0 cm /Im0 Do Q\n';
    startObject(5);
    addText('<< /Length ${content.length} >>\nstream\n$content'
        'endstream\nendobj\n');

    startObject(6);
    addText('$streamLength\nendobj\n');

    final xref = position;
    addText('xref\n0 7\n0000000000 65535 f \n');
    for (var i = 1; i <= 6; i++) {
      addText('${offsets[i]!.toString().padLeft(10, '0')} 00000 n \n');
    }
    addText('trailer\n<< /Size 7 /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n');
  } finally {
    await sink.close();
  }
}

/// Forwards every deflate output chunk as it appears.
class _CollectSink extends ByteConversionSink {
  _CollectSink(this._out);

  final BytesBuilder _out;

  @override
  void add(List<int> chunk) => _out.add(chunk);

  @override
  void addSlice(List<int> chunk, int start, int end, bool isLast) {
    _out.add(Uint8List.sublistView(
        chunk is Uint8List ? chunk : Uint8List.fromList(chunk), start, end));
    if (isLast) close();
  }

  @override
  void close() {}
}
