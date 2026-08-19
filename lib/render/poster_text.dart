import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../core/format.dart';
import '../model/map_style.dart';
import '../model/place.dart';
import '../model/poster_config.dart';
import '../model/route_track.dart';
import '../presets/font_presets.dart';

class _Line {
  final TextPainter painter;
  final double gapBefore;
  final bool isDivider;
  _Line(this.painter, this.gapBefore, {this.isDivider = false});
}

/// The typographic block underneath (or over) the map.
class PosterTextBlock {
  PosterTextBlock._(this._lines, this.height, this._align, this._dividerColor,
      this._dividerWidth);

  final List<_Line> _lines;
  final double height;
  final PosterAlign _align;
  final Color _dividerColor;
  final double _dividerWidth;

  static PosterTextBlock build({
    required PosterConfig poster,
    required MapStyle style,
    required PlaceRef? place,
    required RouteTrack? route,
    required double unit,
    required double maxWidth,
    Color? overrideColor,
  }) {
    final lines = <_Line>[];
    if (!poster.enabled || poster.placement == TextPlacement.none) {
      return PosterTextBlock._(lines, 0, poster.align, style.accentColor, 0);
    }

    final colorMain = overrideColor ?? style.textColor;
    final colorSoft = (overrideColor ?? style.accentColor).withValues(alpha: 0.92);

    final titleFont = fontByFamily(poster.titleFont);
    final bodyFont = fontByFamily(poster.bodyFont);
    final textAlign = switch (poster.align) {
      PosterAlign.left => TextAlign.left,
      PosterAlign.center => TextAlign.center,
      PosterAlign.right => TextAlign.right,
    };

    var titleText = poster.title.trim().isNotEmpty ? poster.title.trim() : (place?.name ?? '');
    if (poster.uppercaseTitle) titleText = titleText.toUpperCase();

    final titleSize = unit * 62 * poster.titleScale;
    if (titleText.isNotEmpty) {
      lines.add(_Line(
        _painter(
          titleText,
          family: poster.titleFont,
          size: titleSize,
          weight: FontWeight.w600,
          color: colorMain,
          spacing: titleSize * 0.34 * poster.letterSpacing * (titleFont.tracking / 0.34),
          maxWidth: maxWidth,
          maxLines: 2,
          align: textAlign,
        ),
        0,
      ));
    }

    if (poster.divider) {
      lines.add(_Line(
        _painter('', family: poster.bodyFont, size: 1, color: colorSoft, maxWidth: maxWidth,
            align: textAlign),
        unit * 26,
        isDivider: true,
      ));
    }

    final subtitle =
        poster.subtitle.trim().isNotEmpty ? poster.subtitle.trim() : (place?.context ?? '');
    if (subtitle.isNotEmpty) {
      final s = unit * 21 * poster.titleScale;
      lines.add(_Line(
        _painter(
          subtitle.toUpperCase(),
          family: poster.bodyFont,
          size: s,
          color: colorSoft,
          spacing: s * 0.42 * poster.letterSpacing * (bodyFont.tracking / 0.34),
          maxWidth: maxWidth,
          align: textAlign,
        ),
        poster.divider ? unit * 22 : unit * 20,
      ));
    }

    final meta = <String>[];
    if (poster.showCoordinates && place != null) {
      meta.add(
          poster.coordinatesAsDms ? formatDms(place.centre) : formatDecimal(place.centre));
    }
    if (route != null && !route.isEmpty) {
      final parts = <String>[formatDistance(route.distanceMetres)];
      if (route.ascentMetres > 20) parts.add('${route.ascentMetres.round()} m elev');
      if (route.duration != null) parts.add(_duration(route.duration!));
      meta.add(parts.join('   /   '));
    }
    if (poster.custom.trim().isNotEmpty) meta.add(poster.custom.trim());
    if (poster.showDate) meta.add(formatPosterDate(poster.date ?? DateTime.now()));

    for (var i = 0; i < meta.length; i++) {
      final s = unit * 15 * poster.titleScale;
      lines.add(_Line(
        _painter(
          meta[i].toUpperCase(),
          family: poster.bodyFont,
          size: s,
          color: colorSoft.withValues(alpha: 0.82),
          spacing: s * 0.5 * poster.letterSpacing * (bodyFont.tracking / 0.34),
          maxWidth: maxWidth,
          align: textAlign,
        ),
        i == 0 ? unit * 24 : unit * 11,
      ));
    }

    var h = 0.0;
    for (final l in lines) {
      h += l.gapBefore + (l.isDivider ? 0 : l.painter.height);
    }
    return PosterTextBlock._(lines, h, poster.align, colorSoft, unit * 1.6);
  }

  static String _duration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    return h > 0 ? '${h}h ${m.toString().padLeft(2, '0')}m' : '${m}m';
  }

  static TextPainter _painter(
    String text, {
    required String family,
    required double size,
    required Color color,
    double spacing = 0,
    FontWeight weight = FontWeight.w400,
    required double maxWidth,
    int maxLines = 1,
    TextAlign align = TextAlign.center,
  }) {
    final p = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: family,
          fontSize: size,
          height: 1.12,
          color: color,
          letterSpacing: spacing,
          fontWeight: weight,
        ),
      ),
      textAlign: align,
      textDirection: TextDirection.ltr,
      maxLines: maxLines,
      ellipsis: '…',
    );
    p.layout(maxWidth: maxWidth);
    return p;
  }

  /// Paints the block inside [area], starting at [top].
  void paint(ui.Canvas canvas, Rect area, double top, double maxWidth) {
    var y = top;
    for (final line in _lines) {
      y += line.gapBefore;
      if (line.isDivider) {
        final w = maxWidth * 0.16;
        final paint = Paint()
          ..color = _dividerColor.withValues(alpha: 0.55)
          ..strokeWidth = _dividerWidth
          ..strokeCap = StrokeCap.square;
        final left = switch (_align) {
          PosterAlign.left => area.left,
          PosterAlign.center => area.center.dx - w / 2,
          PosterAlign.right => area.right - w,
        };
        canvas.drawLine(Offset(left, y), Offset(left + w, y), paint);
        continue;
      }
      final x = switch (_align) {
        PosterAlign.left => area.left,
        PosterAlign.center => area.center.dx - line.painter.width / 2,
        PosterAlign.right => area.right - line.painter.width,
      };
      line.painter.paint(canvas, Offset(x, y));
      y += line.painter.height;
    }
  }
}
