import '../model/format_spec.dart';

const List<FormatSpec> kFormats = [
  FormatSpec(
    id: 'poster23',
    name: 'Poster',
    hint: '2 : 3',
    aspect: 2 / 3,
    exportWidths: [1600, 2560, 3200, 4000],
  ),
  FormatSpec(
    id: 'poster34',
    name: 'Classic',
    hint: '3 : 4',
    aspect: 3 / 4,
    exportWidths: [1800, 2880, 3600, 4320],
  ),
  FormatSpec(
    id: 'square',
    name: 'Square',
    hint: '1 : 1',
    aspect: 1,
    exportWidths: [2048, 3000, 4096, 6000],
  ),
  FormatSpec(
    id: 'phone',
    name: 'Wallpaper',
    hint: '9 : 19.5',
    aspect: 9 / 19.5,
    exportWidths: [1080, 1440, 1800, 2160],
  ),
  FormatSpec(
    id: 'story',
    name: 'Story',
    hint: '9 : 16',
    aspect: 9 / 16,
    exportWidths: [1080, 1620, 2160, 3240],
  ),
  FormatSpec(
    id: 'print',
    name: 'Print',
    hint: 'A-series',
    aspect: 1 / 1.41421,
    exportWidths: [2480, 3508, 4961],
  ),
  FormatSpec(
    id: 'desktop',
    name: 'Desktop',
    hint: '16 : 9',
    aspect: 16 / 9,
    exportWidths: [2560, 3840, 5120],
  ),
];

FormatSpec formatById(String id) =>
    kFormats.firstWhere((f) => f.id == id, orElse: () => kFormats.first);

/// A short marketing tier for a pixel size, e.g. "4K".
String resolutionTier(int width, int height) {
  final long = width > height ? width : height;
  if (long >= 7680) return '8K';
  if (long >= 5120) return '5K';
  if (long >= 3840) return '4K';
  if (long >= 2560) return 'QHD';
  if (long >= 1920) return 'FHD';
  return 'HD';
}
