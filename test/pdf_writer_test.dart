import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:carta/render/pdf_writer.dart';
import 'package:flutter_test/flutter_test.dart';

Future<ByteData> _flatBand(int y, int rows, int width, int value) async {
  final bytes = Uint8List(rows * width * 4);
  for (var i = 0; i < rows * width; i++) {
    bytes[i * 4] = value;
    bytes[i * 4 + 1] = value;
    bytes[i * 4 + 2] = value;
    bytes[i * 4 + 3] = 255;
  }
  return ByteData.sublistView(bytes);
}

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('carta_pdf'));
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<String> writeAndRead({
    int width = 90,
    int height = 60,
    int bandRows = 7,
    double dpi = 300,
    void Function(double)? onProgress,
  }) async {
    final file = File('${tmp.path}${Platform.pathSeparator}poster.pdf');
    await writeStreamingPdf(
      file: file,
      width: width,
      height: height,
      bandRows: bandRows,
      dpi: dpi,
      onProgress: onProgress,
      renderBand: (y, rows) => _flatBand(y, rows, width, 128),
    );
    return latin1.decode(await file.readAsBytes(), allowInvalid: true);
  }

  test('writes a structurally valid PDF', () async {
    final pdf = await writeAndRead();
    expect(pdf.startsWith('%PDF-1.4'), isTrue);
    expect(pdf.trimRight().endsWith('%%EOF'), isTrue);
    expect(pdf, contains('/Type /Catalog'));
    expect(pdf, contains('/Type /Page '));
    expect(pdf, contains('/Subtype /Image'));
    expect(pdf, contains('/Filter /FlateDecode'));
    expect(pdf, contains('trailer'));
  });

  test('the page is sized in points for the requested DPI', () async {
    // 900 x 600 px at 300 DPI is 3 x 2 inches, i.e. 216 x 144 points.
    final pdf = await writeAndRead(width: 900, height: 600, bandRows: 64);
    expect(pdf, contains('/MediaBox [0 0 216.00 144.00]'));
    expect(pdf, contains('q 216.00 0 0 144.00 0 0 cm /Im0 Do Q'));
  });

  test('xref offsets point at their objects', () async {
    final pdf = await writeAndRead();
    final xrefStart = int.parse(
        RegExp(r'startxref\s+(\d+)').firstMatch(pdf)!.group(1)!);
    expect(pdf.substring(xrefStart, xrefStart + 4), 'xref');

    final entries = RegExp(r'^(\d{10}) 00000 n $', multiLine: true)
        .allMatches(pdf)
        .map((m) => int.parse(m.group(1)!))
        .toList();
    expect(entries.length, 6);
    for (var i = 0; i < entries.length; i++) {
      expect(pdf.startsWith('${i + 1} 0 obj', entries[i]), isTrue,
          reason: 'object ${i + 1} is not where the xref says it is');
    }
  });

  test('the declared stream length matches the bytes written', () async {
    final pdf = await writeAndRead(width: 120, height: 90, bandRows: 11);
    final declared = int.parse(
        RegExp(r'6 0 obj\s+(\d+)').firstMatch(pdf)!.group(1)!);
    final start = pdf.indexOf('stream\n', pdf.indexOf('4 0 obj')) + 'stream\n'.length;
    final end = pdf.indexOf('\nendstream', start);
    expect(end - start, declared);
  });

  test('the image stream really is deflate and decodes to the right size',
      () async {
    const width = 40, height = 30;
    final file = File('${tmp.path}${Platform.pathSeparator}decode.pdf');
    await writeStreamingPdf(
      file: file,
      width: width,
      height: height,
      bandRows: 8,
      dpi: 300,
      renderBand: (y, rows) => _flatBand(y, rows, width, 200),
    );
    final bytes = await file.readAsBytes();
    final text = latin1.decode(bytes, allowInvalid: true);
    final start = text.indexOf('stream\n', text.indexOf('4 0 obj')) + 'stream\n'.length;
    final declared = int.parse(
        RegExp(r'6 0 obj\s+(\d+)').firstMatch(text)!.group(1)!);

    final raw = ZLibCodec().decode(bytes.sublist(start, start + declared));
    expect(raw.length, width * height * 3, reason: 'three bytes per RGB pixel');
    expect(raw.every((b) => b == 200), isTrue);
  });

  test('progress runs to completion on an uneven last band', () async {
    final seen = <double>[];
    await writeAndRead(width: 33, height: 25, bandRows: 7, onProgress: seen.add);
    expect(seen.last, 1.0);
    expect(seen.length, 4);
  });
}
