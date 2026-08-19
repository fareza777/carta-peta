import 'dart:ui';

enum FrameStyle { none, hairline, doubleLine, inset, plate }

enum ShapeMask { fill, rectangle, circle, rounded, arch }

enum TextPlacement { below, overlayBottom, overlayTop, none }

enum PosterAlign { left, center, right }

/// Everything about the poster "furniture" around the map artwork.
class PosterConfig {
  final bool enabled;
  final String title;
  final String subtitle;
  final String custom;
  final bool showCoordinates;
  final bool showDate;
  final bool coordinatesAsDms;
  final DateTime? date;

  final String titleFont;
  final String bodyFont;
  final double titleScale;
  final double letterSpacing;
  final bool uppercaseTitle;
  final TextPlacement placement;
  final PosterAlign align;

  final FrameStyle frame;
  final ShapeMask shape;

  /// Fraction of the shorter poster edge used as an outer margin.
  final double margin;

  /// Paper colour behind the map when [margin] > 0. Null follows the style.
  final Color? paperColor;

  /// A thin rule between the title block and the meta block.
  final bool divider;

  const PosterConfig({
    this.enabled = true,
    this.title = '',
    this.subtitle = '',
    this.custom = '',
    this.showCoordinates = true,
    this.showDate = false,
    this.coordinatesAsDms = true,
    this.date,
    this.titleFont = 'Inter',
    this.bodyFont = 'Inter',
    this.titleScale = 1.0,
    this.letterSpacing = 0.34,
    this.uppercaseTitle = true,
    this.placement = TextPlacement.below,
    this.align = PosterAlign.center,
    this.frame = FrameStyle.none,
    this.shape = ShapeMask.rectangle,
    this.margin = 0.075,
    this.paperColor,
    this.divider = true,
  });

  PosterConfig copyWith({
    bool? enabled,
    String? title,
    String? subtitle,
    String? custom,
    bool? showCoordinates,
    bool? showDate,
    bool? coordinatesAsDms,
    DateTime? date,
    String? titleFont,
    String? bodyFont,
    double? titleScale,
    double? letterSpacing,
    bool? uppercaseTitle,
    TextPlacement? placement,
    PosterAlign? align,
    FrameStyle? frame,
    ShapeMask? shape,
    double? margin,
    Color? paperColor,
    bool clearPaperColor = false,
    bool? divider,
  }) =>
      PosterConfig(
        enabled: enabled ?? this.enabled,
        title: title ?? this.title,
        subtitle: subtitle ?? this.subtitle,
        custom: custom ?? this.custom,
        showCoordinates: showCoordinates ?? this.showCoordinates,
        showDate: showDate ?? this.showDate,
        coordinatesAsDms: coordinatesAsDms ?? this.coordinatesAsDms,
        date: date ?? this.date,
        titleFont: titleFont ?? this.titleFont,
        bodyFont: bodyFont ?? this.bodyFont,
        titleScale: titleScale ?? this.titleScale,
        letterSpacing: letterSpacing ?? this.letterSpacing,
        uppercaseTitle: uppercaseTitle ?? this.uppercaseTitle,
        placement: placement ?? this.placement,
        align: align ?? this.align,
        frame: frame ?? this.frame,
        shape: shape ?? this.shape,
        margin: margin ?? this.margin,
        paperColor: clearPaperColor ? null : (paperColor ?? this.paperColor),
        divider: divider ?? this.divider,
      );

  Map<String, dynamic> toJson() => {
        'en': enabled,
        't': title,
        's': subtitle,
        'c': custom,
        'sc': showCoordinates,
        'sd': showDate,
        'dms': coordinatesAsDms,
        if (date != null) 'dt': date!.millisecondsSinceEpoch,
        'tf': titleFont,
        'bf': bodyFont,
        'ts': titleScale,
        'lsp': letterSpacing,
        'uc': uppercaseTitle,
        'pl': placement.index,
        'al': align.index,
        'fr': frame.index,
        'sh': shape.index,
        'mg': margin,
        if (paperColor != null) 'pc': paperColor!.toARGB32(),
        'dv': divider,
      };

  factory PosterConfig.fromJson(Map<String, dynamic> j) => PosterConfig(
        enabled: j['en'] as bool? ?? true,
        title: j['t'] as String? ?? '',
        subtitle: j['s'] as String? ?? '',
        custom: j['c'] as String? ?? '',
        showCoordinates: j['sc'] as bool? ?? true,
        showDate: j['sd'] as bool? ?? false,
        coordinatesAsDms: j['dms'] as bool? ?? true,
        date: j['dt'] == null ? null : DateTime.fromMillisecondsSinceEpoch(j['dt'] as int),
        titleFont: j['tf'] as String? ?? 'Inter',
        bodyFont: j['bf'] as String? ?? 'Inter',
        titleScale: (j['ts'] as num?)?.toDouble() ?? 1.0,
        letterSpacing: (j['lsp'] as num?)?.toDouble() ?? 0.34,
        uppercaseTitle: j['uc'] as bool? ?? true,
        placement: TextPlacement
            .values[(j['pl'] as int? ?? 0).clamp(0, TextPlacement.values.length - 1)],
        align: PosterAlign
            .values[(j['al'] as int? ?? 1).clamp(0, PosterAlign.values.length - 1)],
        frame:
            FrameStyle.values[(j['fr'] as int? ?? 0).clamp(0, FrameStyle.values.length - 1)],
        shape:
            ShapeMask.values[(j['sh'] as int? ?? 1).clamp(0, ShapeMask.values.length - 1)],
        margin: (j['mg'] as num?)?.toDouble() ?? 0.075,
        paperColor: j['pc'] == null ? null : Color(j['pc'] as int),
        divider: j['dv'] as bool? ?? true,
      );
}
