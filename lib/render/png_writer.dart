import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Streams a PNG to disk one horizontal band at a time.
///
/// The obvious way to save a poster — rasterise the whole thing, then ask the
/// engine to encode it — needs the full RGBA bitmap *and* the encoder's copy in
/// memory at once. At 35 megapixels that is roughly 280 MB, which Android's low
/// memory killer will not tolerate. Writing band by band keeps the peak at one
/// band plus the compressor's buffer, a few megabytes.
Future<void> writeStreamingPng({
  required File file,
  required int width,
  required int height,
  required int bandRows,
  required Future<ByteData> Function(int y, int rows) renderBand,
  void Function(double progress)? onProgress,
}) async {
  final sink = file.openWrite();
  try {
    sink.add(_signature);
    _writeChunk(sink, 'IHDR', _ihdr(width, height));

    final pending = BytesBuilder(copy: false);
    final deflate = ZLibCodec(level: 6).encoder.startChunkedConversion(
          _CollectSink(pending),
        );

    final rowLength = width * 4;
    final line = Uint8List(rowLength + 1);
    final previous = Uint8List(rowLength);
    var firstRow = true;

    for (var y = 0; y < height; y += bandRows) {
      final rows = (y + bandRows > height) ? height - y : bandRows;
      final band = await renderBand(y, rows);
      final pixels = band.buffer.asUint8List(band.offsetInBytes, rows * rowLength);

      for (var r = 0; r < rows; r++) {
        final base = r * rowLength;
        if (firstRow) {
          // No previous scanline to subtract from yet.
          line[0] = 0;
          line.setRange(1, rowLength + 1, pixels, base);
          firstRow = false;
        } else {
          // Filter 2 ("Up"): flat poster areas turn into runs of zero, which
          // deflate loves.
          line[0] = 2;
          for (var i = 0; i < rowLength; i++) {
            line[i + 1] = (pixels[base + i] - previous[i]) & 0xFF;
          }
        }
        deflate.add(line);
        previous.setRange(0, rowLength, pixels, base);
      }

      if (pending.length > 0) {
        _writeChunk(sink, 'IDAT', pending.takeBytes());
      }
      onProgress?.call(((y + rows) / height).clamp(0.0, 1.0));
      // Give the UI thread a chance between bands.
      await Future<void>.delayed(Duration.zero);
    }

    deflate.close();
    if (pending.length > 0) {
      _writeChunk(sink, 'IDAT', pending.takeBytes());
    }
    _writeChunk(sink, 'IEND', Uint8List(0));
  } finally {
    await sink.close();
  }
}

const _signature = [137, 80, 78, 71, 13, 10, 26, 10];

Uint8List _ihdr(int width, int height) {
  final data = ByteData(13);
  data.setUint32(0, width);
  data.setUint32(4, height);
  data.setUint8(8, 8); // bit depth
  data.setUint8(9, 6); // colour type: RGBA
  data.setUint8(10, 0); // deflate
  data.setUint8(11, 0); // adaptive filtering
  data.setUint8(12, 0); // no interlace
  return data.buffer.asUint8List();
}

void _writeChunk(IOSink sink, String type, Uint8List data) {
  final header = ByteData(4)..setUint32(0, data.length);
  final typeBytes = Uint8List.fromList(type.codeUnits);
  sink.add(header.buffer.asUint8List());
  sink.add(typeBytes);
  if (data.isNotEmpty) sink.add(data);
  final crc = Crc32()
    ..add(typeBytes)
    ..add(data);
  final tail = ByteData(4)..setUint32(0, crc.value);
  sink.add(tail.buffer.asUint8List());
}

/// CRC-32 as specified by the PNG format.
class Crc32 {
  static final Uint32List _table = _buildTable();

  static Uint32List _buildTable() {
    final t = Uint32List(256);
    for (var n = 0; n < 256; n++) {
      var c = n;
      for (var k = 0; k < 8; k++) {
        c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
      }
      t[n] = c;
    }
    return t;
  }

  int _crc = 0xFFFFFFFF;

  void add(List<int> bytes) {
    var c = _crc;
    for (var i = 0; i < bytes.length; i++) {
      c = _table[(c ^ bytes[i]) & 0xFF] ^ (c >> 8);
    }
    _crc = c;
  }

  int get value => (_crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

/// Forwards every deflate output chunk as it appears, unlike the built-in
/// callback sink which only reports on close.
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
