import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../model/area_boundary.dart';
import '../model/format_spec.dart';
import '../model/layer.dart';
import '../model/map_data.dart';
import '../model/map_style.dart';
import '../model/place.dart';
import '../model/poster_config.dart';
import '../model/route_track.dart';
import '../model/terrain_relief.dart';
import 'grain.dart';
import 'path_cache.dart';
import 'poster_text.dart';

/// Everything needed to draw one poster, at any resolution.
class PosterScene {
  PosterScene({
    required this.style,
    required this.poster,
    required this.format,
    this.paths,
    this.routes = const [],
    this.highlight,
    this.place,
    this.relief,
    this.zoom = 1.0,
    this.pan = Offset.zero,
    this.showAttribution = true,
  });

  final MapPathCache? paths;
  final MapStyle style;
  final PosterConfig poster;
  final FormatSpec format;
  final List<RouteTrack> routes;

  /// Area lifted out of the map around it, e.g. one neighbourhood.
  final AreaBoundary? highlight;
  final PlaceRef? place;
  final TerrainRelief? relief;
  final double zoom;
  final Offset pan;
  final bool showAttribution;

  MapDataSet? get data => paths?.data;

  Path? _highlightPath;
  bool _highlightBuilt = false;

  /// The highlighted area as one path in window-local units, or null when
  /// there is nothing to highlight.
  Path? get highlightPath {
    if (_highlightBuilt) return _highlightPath;
    _highlightBuilt = true;
    final area = highlight;
    final d = data;
    if (area == null || area.isEmpty || d == null) return null;
    final path = Path()..fillType = PathFillType.nonZero;
    for (final ring in area.project(d.window)) {
      path.moveTo(ring[0], ring[1]);
      for (var i = 2; i < ring.length; i += 2) {
        path.lineTo(ring[i], ring[i + 1]);
      }
      path.close();
    }
    return _highlightPath = path;
  }

  List<Path>? _routePaths;

  /// One projected path per imported track.
  List<Path> get routePaths {
    final cached = _routePaths;
    if (cached != null) return cached;
    final d = data;
    final out = <Path>[];
    if (d != null) {
      for (final r in routes) {
        if (r.isEmpty) continue;
        final pts = r.project(d.window);
        final p = Path()..moveTo(pts[0], pts[1]);
        for (var i = 2; i < pts.length; i += 2) {
          p.lineTo(pts[i], pts[i + 1]);
        }
        out.add(p);
      }
    }
    return _routePaths = out;
  }
}

/// Draws a [PosterScene] onto any canvas. The same code path powers the live
/// preview, the preset thumbnails and the 4K/8K export.
class PosterRenderer {
  static void paint(ui.Canvas canvas, Size size, PosterScene scene) {
    final grade = scene.style.grade;
    final graded = !grade.isIdentity;
    if (graded) {
      canvas.saveLayer(
        Offset.zero & size,
        Paint()..colorFilter = ColorFilter.matrix(grade.matrix()),
      );
    }
    _paintUngraded(canvas, size, scene);
    if (graded) canvas.restore();
  }

  static void _paintUngraded(ui.Canvas canvas, Size size, PosterScene scene) {
    final s = math.min(size.width, size.height);
    final unit = s / 1000.0;
    final full = Offset.zero & size;

    final isFullBleed = scene.poster.shape == ShapeMask.fill;
    final paper = scene.poster.paperColor;
    if (paper != null && !isFullBleed) {
      canvas.drawRect(full, Paint()..color = paper);
    } else {
      _paintBackground(canvas, full, scene.style);
    }

    final margin = isFullBleed ? 0.0 : scene.poster.margin * s;
    final content = Rect.fromLTWH(
      margin,
      margin,
      math.max(1.0, size.width - margin * 2),
      math.max(1.0, size.height - margin * 2),
    );

    final textWidth = content.width * 0.94;
    final overlay = isFullBleed || scene.poster.placement != TextPlacement.below;
    final block = PosterTextBlock.build(
      poster: scene.poster,
      style: scene.style,
      place: scene.place,
      routes: scene.routes,
      unit: unit,
      maxWidth: textWidth,
    );

    var mapRect = content;
    final gap = s * 0.05;
    if (!overlay && block.height > 0) {
      final h = content.height - block.height - gap;
      if (h > s * 0.25) {
        mapRect = Rect.fromLTWH(content.left, content.top, content.width, h);
      }
    }

    final shape = _shapePath(scene.poster.shape, mapRect, s, full);

    canvas.save();
    canvas.clipPath(shape);
    if (paper != null || isFullBleed) {
      _paintBackground(canvas, shape.getBounds(), scene.style);
    }
    _paintMap(canvas, mapRect, scene);
    if (scene.style.vignette > 0) {
      _paintVignette(canvas, shape.getBounds(), scene.style.vignette);
    }
    canvas.restore();

    _paintFrame(canvas, scene, mapRect, s, full);

    if (block.height > 0) {
      if (!overlay) {
        block.paint(canvas, content, mapRect.bottom + gap, textWidth);
      } else {
        final top = scene.poster.placement == TextPlacement.overlayTop
            ? content.top + s * 0.03
            : content.bottom - block.height - s * 0.02;
        _paintScrim(canvas, full, scene, top, block.height, s);
        block.paint(canvas, content, top, textWidth);
      }
    }

    if (scene.style.grain > 0) _paintGrain(canvas, full, scene.style.grain);
    if (scene.showAttribution) _paintAttribution(canvas, scene, full, unit, overlay);
  }

  // ------------------------------------------------------------- background

  static void _paintBackground(ui.Canvas canvas, Rect rect, MapStyle style) {
    final end = style.backgroundEnd;
    if (end == null) {
      canvas.drawRect(rect, Paint()..color = style.background);
      return;
    }
    final a = style.gradientAngle;
    final dx = math.cos(a), dy = math.sin(a);
    final centre = rect.center;
    final r = math.max(rect.width, rect.height) / 2;
    final shader = ui.Gradient.linear(
      Offset(centre.dx - dx * r, centre.dy - dy * r),
      Offset(centre.dx + dx * r, centre.dy + dy * r),
      [style.background, end],
    );
    canvas.drawRect(rect, Paint()..shader = shader);
  }

  // -------------------------------------------------------------------- map

  static double _densityFactor(MapDataSet? data) {
    final span = data?.window.groundSpanMetres ?? 2600;
    if (span <= 1) return 1.0;
    // The upper clamp used to stop at 1.85, which left a house-scale poster
    // drawing hairline streets. Close-ups need proportionally heavier lines to
    // read like a site plan.
    return math.pow(2600.0 / span, 0.30).toDouble().clamp(0.55, 3.4);
  }

  /// Identifies one rendered view of the map. Styles are immutable and rebuilt
  /// on every edit, so identity is a sound and very cheap signature; poster
  /// text edits leave the style object untouched and hit the cache.
  static String _mapKey(PosterScene scene, Rect mapRect) => [
        identityHashCode(scene.style),
        identityHashCode(scene.relief),
        identityHashCode(scene.routes),
        identityHashCode(scene.highlight),
        scene.zoom.toStringAsFixed(4),
        scene.pan.dx.toStringAsFixed(4),
        scene.pan.dy.toStringAsFixed(4),
        mapRect.left.toStringAsFixed(2),
        mapRect.top.toStringAsFixed(2),
        mapRect.width.toStringAsFixed(2),
        mapRect.height.toStringAsFixed(2),
      ].join('|');

  static void _paintMap(ui.Canvas canvas, Rect mapRect, PosterScene scene) {
    final cache = scene.paths;
    if (cache == null || !cache.hasAnything) return;

    final key = _mapKey(scene, mapRect);
    final cached = cache.cachedMap(key);
    if (cached != null) {
      canvas.drawPicture(cached);
      return;
    }

    final recorder = ui.PictureRecorder();
    final into = ui.Canvas(recorder, mapRect);
    _drawMap(into, mapRect, scene);
    final picture = recorder.endRecording();
    canvas.drawPicture(picture);
    // A Picture is a display list, not a bitmap, so holding one costs almost
    // nothing regardless of the export resolution it was recorded for.
    cache.storeMap(key, picture);
  }

  static void _drawMap(ui.Canvas canvas, Rect mapRect, PosterScene scene) {
    final cache = scene.paths!;
    final scale = math.max(mapRect.width, mapRect.height) * scene.zoom;
    if (scale <= 0) return;
    final dx = mapRect.center.dx - scale * 0.5 + scene.pan.dx * scale;
    final dy = mapRect.center.dy - scale * 0.5 + scene.pan.dy * scale;

    final style = scene.style;
    final density = _densityFactor(cache.data);
    final strokeUnit = mapRect.shortestSide / 1000.0 * density;

    canvas.save();
    canvas.translate(dx, dy);
    canvas.scale(scale);

    // Poster units to local canvas units.
    double px(double posterUnits) => posterUnits * strokeUnit / scale;

    // Local units per metre on the ground. The window is one unit wide, so
    // this is simply the reciprocal of its ground span.
    final ground = cache.data.window.groundSpanMetres;
    final metre = ground > 1 ? 1.0 / ground : 0.0;

    /// Width for a layer: either its real ground width or the usual fraction
    /// of the poster.
    double lineWidth(LayerId id, LayerStyle ls) {
      if (style.trueScaleRoads && metre > 0) {
        final metres = kGroundWidths[id];
        if (metres != null) return metres * metre * style.lineScale;
      }
      return px(ls.width * style.lineScale);
    }

    Paint fillPaint(Color c, double opacity) => Paint()
      ..style = PaintingStyle.fill
      ..isAntiAlias = true
      ..color = c.withValues(alpha: c.a * opacity);

    Paint strokePaint(
      Color c,
      double width,
      double opacity, {
      StrokeCap cap = StrokeCap.round,
    }) =>
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..strokeCap = cap
          ..strokeJoin = StrokeJoin.round
          ..isAntiAlias = true
          ..color = c.withValues(alpha: c.a * opacity);

    void bloom(Path path, LayerStyle ls, double width, double opacity) {
      if (ls.glow <= 0.01) return;
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = width * (1 + 2.4 * ls.glow)
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = ls.stroke.withValues(alpha: 0.34 * ls.glow * opacity)
          ..maskFilter = ui.MaskFilter.blur(BlurStyle.normal, width * 1.6 * ls.glow),
      );
    }

    void paintArea(LayerId id) {
      final ls = style.layer(id);
      if (!ls.enabled || ls.opacity <= 0.01) return;
      final path = cache.solid(id);
      if (ls.filled) canvas.drawPath(path, fillPaint(ls.fill, ls.opacity));
      if (ls.outlined && ls.width > 0) {
        canvas.drawPath(
          path,
          strokePaint(
            ls.stroke,
            px(ls.width * style.lineScale),
            ls.opacity,
            cap: StrokeCap.butt,
          ),
        );
      }
    }

    void paintPlainLine(LayerId id) {
      final ls = style.layer(id);
      if (!ls.enabled || !ls.outlined || ls.opacity <= 0.01) return;
      final width = lineWidth(id, ls);
      if (width <= 0) return;
      var path = cache.solid(id);
      if (ls.dash != null && ls.dash!.length >= 2) {
        path = cache.dashed('s${id.index}', path, px(ls.dash![0]), px(ls.dash![1]));
      }
      bloom(path, ls, width, ls.opacity);
      canvas.drawPath(path, strokePaint(ls.stroke, width, ls.opacity));
    }

    void paintRelief() {
      final relief = scene.relief;
      if (relief == null || style.reliefStrength <= 0.01) return;
      // Mid grey is neutral under an overlay blend, exactly like the grain, so
      // hillshading reads correctly on light and dark styles alike.
      final k = (1.0 - style.reliefStrength.clamp(0.0, 1.0)) * 0.95;
      canvas.drawImageRect(
        relief.image,
        Rect.fromLTWH(
          0,
          0,
          relief.image.width.toDouble(),
          relief.image.height.toDouble(),
        ),
        relief.localRect,
        Paint()
          ..filterQuality = FilterQuality.medium
          ..colorFilter =
              ColorFilter.mode(Color.fromRGBO(128, 128, 128, k), BlendMode.srcOver)
          ..blendMode = BlendMode.overlay,
      );
    }

    void paintContours() {
      final ls = style.layer(LayerId.contour);
      if (!ls.enabled || ls.opacity <= 0.01) return;
      if (cache.contourInterval <= 0) return;
      final width = px(ls.width * style.lineScale);
      if (width <= 0) return;
      canvas.drawPath(
        cache.contour(index: false),
        strokePaint(ls.stroke, width, ls.opacity * 0.7),
      );
      // Every fifth line is drawn heavier, the way printed topo sheets do it.
      canvas.drawPath(
        cache.contour(index: true),
        strokePaint(ls.stroke, width * 2.1, ls.opacity),
      );
    }

    void paintBuildings() {
      final ls = style.layer(LayerId.building);
      if (!ls.enabled || ls.opacity <= 0.01) return;
      if (ls.filled) {
        if (style.heightShade > 0.01 && cache.hasBuildingHeights) {
          // Tint each building by how tall it actually is. The data already
          // arrives in the Overpass response, so this costs nothing to fetch.
          final top = style.heightColor ?? style.accentColor;
          for (var i = 0; i < MapPathCache.heightBuckets; i++) {
            final t = i / (MapPathCache.heightBuckets - 1) * style.heightShade;
            final colour = Color.lerp(ls.fill, top, t) ?? ls.fill;
            canvas.drawPath(cache.buildingBucket(i), fillPaint(colour, ls.opacity));
          }
        } else {
          canvas.drawPath(cache.solid(LayerId.building), fillPaint(ls.fill, ls.opacity));
        }
      }
      if (ls.outlined && ls.width > 0) {
        canvas.drawPath(
          cache.solid(LayerId.building),
          strokePaint(
            ls.stroke,
            px(ls.width * style.lineScale),
            ls.opacity,
            cap: StrokeCap.butt,
          ),
        );
      }
    }

    Path roadPath(LayerId id, RoadBand band, LayerStyle ls) {
      final path = cache.road(id, band);
      if (ls.dash != null && ls.dash!.length >= 2) {
        return cache.dashed(
          'r${id.index}.${band.index}',
          path,
          px(ls.dash![0]),
          px(ls.dash![1]),
        );
      }
      return path;
    }

    /// Lifts one area out of its surroundings: everything outside fades back
    /// towards the background, the area itself keeps full contrast and gets a
    /// bold outline. Drawn over the map but under the routes, so a journey
    /// leaving the area is still readable end to end.
    void paintHighlight() {
      final ring = scene.highlightPath;
      if (ring == null) return;
      final colour = style.highlightColor ?? style.accentColor;
      final dim = style.highlightDim.clamp(0.0, 1.0);
      if (dim > 0.01) {
        // The visible slice of window space, recovered from the transform so
        // the scrim covers the whole frame at any zoom or pan.
        final visible = Rect.fromLTRB(
          (mapRect.left - dx) / scale,
          (mapRect.top - dy) / scale,
          (mapRect.right - dx) / scale,
          (mapRect.bottom - dy) / scale,
        ).inflate(0.02);
        final outside = Path()
          ..fillType = PathFillType.evenOdd
          ..addRect(visible)
          ..addPath(ring, Offset.zero);
        canvas.drawPath(
          outside,
          fillPaint(style.background, 0.88 * dim),
        );
      }
      final tint = style.highlightTint.clamp(0.0, 1.0);
      if (tint > 0.01) canvas.drawPath(ring, fillPaint(colour, 0.35 * tint));
      final width = px(style.highlightWidth * style.lineScale);
      if (width > 0) {
        canvas.drawPath(ring, strokePaint(colour, width, 1.0, cap: StrokeCap.butt));
      }
    }

    paintRelief();
    paintArea(LayerId.green);
    paintArea(LayerId.sand);
    paintContours();
    paintArea(LayerId.water);
    paintPlainLine(LayerId.waterway);
    paintBuildings();
    paintPlainLine(LayerId.barrier);

    // Roads go down in three passes so a flyover always sits above whatever it
    // crosses, whatever their classes. Within each pass every casing is laid
    // first, which is what makes a dense junction read as a junction.
    for (final band in RoadBand.values) {
      final bandOpacity = band == RoadBand.tunnel ? 0.45 : 1.0;

      if (band != RoadBand.tunnel) {
        for (final id in kRoadOrder) {
          final ls = style.layer(id);
          final casing = ls.casing;
          if (casing == null || !ls.enabled || !ls.outlined || ls.opacity <= 0.01) {
            continue;
          }
          final extra = band == RoadBand.bridge ? 1.7 : 1.0;
          final width = style.trueScaleRoads && metre > 0
              ? lineWidth(id, ls) + px(2 * ls.casingWidth * extra)
              : px(ls.width * style.lineScale + 2 * ls.casingWidth * extra);
          if (width <= 0) continue;
          canvas.drawPath(
            roadPath(id, band, ls),
            strokePaint(
              casing,
              width,
              ls.opacity,
              cap: band == RoadBand.bridge ? StrokeCap.butt : StrokeCap.round,
            ),
          );
        }
      }

      for (final id in kRoadOrder) {
        final ls = style.layer(id);
        if (!ls.enabled || !ls.outlined || ls.opacity <= 0.01) continue;
        final width = lineWidth(id, ls);
        if (width <= 0) continue;
        final path = roadPath(id, band, ls);
        bloom(path, ls, width, ls.opacity * bandOpacity);
        canvas.drawPath(path, strokePaint(ls.stroke, width, ls.opacity * bandOpacity));
      }
    }

    paintHighlight();
    _paintRoutes(canvas, scene, strokeUnit / scale);

    canvas.restore();

    // Labels live outside the map transform: text must not be scaled by three
    // thousand along with the geometry.
    if (style.showLabels) {
      _paintLabels(canvas, scene, mapRect, dx, dy, scale, strokeUnit);
    }
  }

  /// Draws every imported track. With more than one they fan out between the
  /// route colour and its end colour so they stay tellable apart; a single
  /// track can instead be graded along its own elevation profile.
  static void _paintRoutes(ui.Canvas canvas, PosterScene scene, double unit) {
    final paths = scene.routePaths;
    if (paths.isEmpty) return;
    final style = scene.style;
    final data = scene.data;
    final w = style.routeWidth * unit;
    final endColour = style.routeColorEnd ?? style.accentColor;

    Color colourFor(int index) {
      if (paths.length == 1) return style.routeColor;
      final t = index / (paths.length - 1);
      return Color.lerp(style.routeColor, endColour, t) ?? style.routeColor;
    }

    Paint stroke(Color c, double width) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = c;

    for (var i = 0; i < paths.length; i++) {
      final colour = colourFor(i);
      if (style.routeGlow > 0.01) {
        canvas.drawPath(
          paths[i],
          stroke(colour.withValues(alpha: 0.4 * style.routeGlow),
              w * (1 + 3.2 * style.routeGlow))
            ..maskFilter = ui.MaskFilter.blur(BlurStyle.normal, w * 2.0),
        );
      }

      final track = i < scene.routes.length ? scene.routes[i] : null;
      final gradient = style.routeGradient &&
          paths.length == 1 &&
          data != null &&
          track != null &&
          track.hasProfile;

      if (gradient) {
        for (final chunk in track.chunks(data.window)) {
          final pts = chunk.points;
          if (pts.length < 4) continue;
          final piece = Path()..moveTo(pts[0], pts[1]);
          for (var k = 2; k < pts.length; k += 2) {
            piece.lineTo(pts[k], pts[k + 1]);
          }
          canvas.drawPath(
            piece,
            stroke(Color.lerp(style.routeColor, endColour, chunk.t) ?? colour, w),
          );
        }
      } else {
        canvas.drawPath(paths[i], stroke(colour, w));
      }

      if (track != null) _paintRouteEnds(canvas, scene, track, colour, w);
    }
  }

  static void _paintRouteEnds(
    ui.Canvas canvas,
    PosterScene scene,
    RouteTrack r,
    Color colour,
    double w,
  ) {
    final d = scene.data;
    if (d == null || r.isEmpty) return;
    final pts = r.project(d.window);
    final start = Offset(pts[0], pts[1]);
    final end = Offset(pts[pts.length - 2], pts[pts.length - 1]);
    final fill = Paint()..color = colour;
    final halo = Paint()
      ..color = scene.style.background
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.8;
    for (final p in [start, end]) {
      canvas.drawCircle(p, w * 1.5, fill);
      canvas.drawCircle(p, w * 1.5, halo);
    }
  }

  // ----------------------------------------------------------------- labels

  static const int _maxLabels = 26;

  static void _paintLabels(
    ui.Canvas canvas,
    PosterScene scene,
    Rect mapRect,
    double dx,
    double dy,
    double scale,
    double strokeUnit,
  ) {
    final cache = scene.paths;
    if (cache == null) return;
    final style = scene.style;
    final colour = style.labelColor ?? style.textColor;
    final size = 17 * style.labelScale * mapRect.shortestSide / 1000.0;
    if (size < 4) return;

    final placed = <Rect>[];
    var drawn = 0;

    for (final label in cache.labels) {
      if (drawn >= _maxLabels) break;
      final centre = Offset(dx + label.x * scale, dy + label.y * scale);
      if (!mapRect.contains(centre)) continue;

      final area = label.area;
      final text = area ? label.text.toUpperCase() : label.text;
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontFamily: scene.poster.bodyFont,
            fontSize: area ? size * 0.92 : size,
            letterSpacing: size * (area ? 0.16 : 0.04),
            fontWeight: area ? FontWeight.w600 : FontWeight.w400,
            color: colour,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();

      // Only letter something the label actually fits along.
      final room = label.span * scale;
      if (room < painter.width * 1.15) continue;

      final box = Rect.fromCenter(
        center: centre,
        width: painter.width + size * 0.6,
        height: painter.height + size * 0.35,
      );
      if (!mapRect.contains(box.topLeft) || !mapRect.contains(box.bottomRight)) {
        continue;
      }
      if (placed.any((r) => r.overlaps(box))) continue;
      placed.add(box);
      drawn++;

      canvas.save();
      canvas.translate(centre.dx, centre.dy);
      if (label.angle.abs() > 0.01) canvas.rotate(label.angle);
      final origin = Offset(-painter.width / 2, -painter.height / 2);

      // A halo in the background colour keeps names readable over dense
      // geometry without needing a filled plate behind them.
      final halo = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontFamily: scene.poster.bodyFont,
            fontSize: area ? size * 0.92 : size,
            letterSpacing: size * (area ? 0.16 : 0.04),
            fontWeight: area ? FontWeight.w600 : FontWeight.w400,
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = strokeUnit * 2.2
              ..strokeJoin = StrokeJoin.round
              ..color = style.background.withValues(alpha: 0.8),
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      halo.paint(canvas, origin);
      painter.paint(canvas, origin);
      canvas.restore();
    }
  }

  // ------------------------------------------------------------ decoration

  static Path _shapePath(ShapeMask shape, Rect rect, double s, Rect full) {
    switch (shape) {
      case ShapeMask.fill:
        return Path()..addRect(full);
      case ShapeMask.rectangle:
        return Path()..addRect(rect);
      case ShapeMask.rounded:
        return Path()..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(s * 0.035)));
      case ShapeMask.circle:
        final d = math.min(rect.width, rect.height);
        return Path()..addOval(Rect.fromCenter(center: rect.center, width: d, height: d));
      case ShapeMask.arch:
        final r = rect.width / 2;
        if (rect.height <= r * 1.05) {
          return Path()
            ..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(s * 0.035)));
        }
        return Path()
          ..moveTo(rect.left, rect.bottom)
          ..lineTo(rect.left, rect.top + r)
          ..arcTo(
            Rect.fromLTWH(rect.left, rect.top, rect.width, rect.width),
            math.pi,
            math.pi,
            false,
          )
          ..lineTo(rect.right, rect.bottom)
          ..close();
    }
  }

  static void _paintFrame(
    ui.Canvas canvas,
    PosterScene scene,
    Rect mapRect,
    double s,
    Rect full,
  ) {
    final f = scene.poster.frame;
    if (f == FrameStyle.none) return;
    final colour = scene.style.accentColor;
    final shape = scene.poster.shape;

    Paint stroke(double w, double alpha) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..color = colour.withValues(alpha: alpha);

    switch (f) {
      case FrameStyle.none:
        return;
      case FrameStyle.hairline:
        canvas.drawPath(_shapePath(shape, mapRect, s, full), stroke(s * 0.0022, 0.65));
      case FrameStyle.doubleLine:
        canvas.drawPath(_shapePath(shape, mapRect, s, full), stroke(s * 0.0026, 0.7));
        canvas.drawPath(
          _shapePath(shape, mapRect.deflate(s * 0.014), s, full),
          stroke(s * 0.0014, 0.45),
        );
      case FrameStyle.inset:
        canvas.drawPath(
          _shapePath(shape, mapRect.deflate(s * 0.028), s, full),
          stroke(s * 0.0022, 0.55),
        );
      case FrameStyle.plate:
        canvas.drawPath(_shapePath(shape, mapRect, s, full), stroke(s * 0.009, 0.9));
        canvas.drawPath(
          _shapePath(shape, mapRect.deflate(s * 0.013), s, full),
          stroke(s * 0.0012, 0.5),
        );
    }
  }

  static void _paintVignette(ui.Canvas canvas, Rect rect, double strength) {
    final shader = ui.Gradient.radial(
      rect.center,
      math.max(rect.width, rect.height) * 0.72,
      [const Color(0x00000000), Color.fromRGBO(0, 0, 0, strength.clamp(0.0, 1.0))],
      [0.45, 1.0],
    );
    canvas.drawRect(rect, Paint()..shader = shader);
  }

  static void _paintScrim(
    ui.Canvas canvas,
    Rect full,
    PosterScene scene,
    double top,
    double h,
    double s,
  ) {
    final fromTop = scene.poster.placement == TextPlacement.overlayTop;
    final band = Rect.fromLTRB(
      full.left,
      fromTop ? full.top : top - s * 0.09,
      full.right,
      fromTop ? top + h + s * 0.09 : full.bottom,
    );
    final bg = scene.style.background;
    final shader = ui.Gradient.linear(
      Offset(band.center.dx, fromTop ? band.bottom : band.top),
      Offset(band.center.dx, fromTop ? band.top : band.bottom),
      [bg.withValues(alpha: 0.0), bg.withValues(alpha: 0.82)],
    );
    canvas.drawRect(band, Paint()..shader = shader);
  }

  static void _paintGrain(ui.Canvas canvas, Rect rect, double strength) {
    final img = GrainTexture.image;
    if (img == null) return;
    // One noise texel per device pixel. Real film grain gets finer relative to
    // the sheet as the print grows; it does not scale up with it.
    final matrix =
        Float64List.fromList([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]);
    final k = (1.0 - strength.clamp(0.0, 1.0)) * 0.94;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.ImageShader(img, TileMode.repeated, TileMode.repeated, matrix)
        ..colorFilter =
            ColorFilter.mode(Color.fromRGBO(128, 128, 128, k), BlendMode.srcOver)
        ..blendMode = BlendMode.overlay,
    );
  }

  static void _paintAttribution(
    ui.Canvas canvas,
    PosterScene scene,
    Rect full,
    double unit,
    bool overlay,
  ) {
    final size = math.max(6.0, unit * 11);
    final painter = TextPainter(
      text: TextSpan(
        text: '(c) OpenStreetMap contributors',
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: size,
          letterSpacing: size * 0.06,
          color: scene.style.accentColor.withValues(alpha: overlay ? 0.55 : 0.45),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final pad = unit * 22;
    final y = overlay
        ? full.bottom - painter.height - pad
        : full.bottom - painter.height - pad * 0.6;
    painter.paint(canvas, Offset(full.right - painter.width - pad, y));
  }
}
