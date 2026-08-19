import 'dart:ui' as ui;

/// A shaded-relief raster covering part of the poster window.
///
/// Computed from the same elevation grid the contour tracer uses, so switching
/// hillshading on costs no extra download once terrain has been fetched.
class TerrainRelief {
  const TerrainRelief({
    required this.image,
    required this.originLocalX,
    required this.originLocalY,
    required this.stepLocal,
  });

  final ui.Image image;

  /// Window-local position of the raster's top-left sample.
  final double originLocalX;
  final double originLocalY;

  /// Window-local size of one sample.
  final double stepLocal;

  ui.Rect get localRect => ui.Rect.fromLTWH(
        originLocalX,
        originLocalY,
        image.width * stepLocal,
        image.height * stepLocal,
      );

  void dispose() => image.dispose();
}
