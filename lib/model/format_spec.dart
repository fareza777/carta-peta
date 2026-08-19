/// A poster canvas format and the resolutions it can be exported at.
class FormatSpec {
  final String id;
  final String name;
  final String hint;

  /// width / height
  final double aspect;
  final List<int> exportWidths;

  const FormatSpec({
    required this.id,
    required this.name,
    required this.hint,
    required this.aspect,
    required this.exportWidths,
  });

  int heightFor(int width) => (width / aspect).round();

  String labelFor(int width) => '$width x ${heightFor(width)}';

  /// Rough megapixel count, used to warn about very heavy exports.
  double megapixelsFor(int width) => width * heightFor(width) / 1000000.0;
}
