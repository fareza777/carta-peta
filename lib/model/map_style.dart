import 'dart:ui';

import 'layer.dart';

/// Styling for one map layer.
class LayerStyle {
  final bool enabled;
  final bool filled;
  final bool outlined;
  final Color fill;
  final Color stroke;

  /// Stroke width expressed in poster units: 1.0 == 1/1000 of the poster's
  /// shorter edge, so styles are resolution independent.
  final double width;
  final double opacity;

  /// 0 = crisp, >0 adds a soft neon bloom underneath the stroke.
  final double glow;

  /// null = solid, otherwise [on, off] in poster units.
  final List<double>? dash;

  /// Colour of the wider stroke drawn beneath this one. Null disables casing.
  /// Casing is what makes a dense street network read as a network instead of
  /// a tangle: every junction gets a clean outline.
  final Color? casing;

  /// Extra width added on each side of the stroke, in poster units.
  final double casingWidth;

  const LayerStyle({
    this.enabled = true,
    this.filled = false,
    this.outlined = true,
    this.fill = const Color(0xFF000000),
    this.stroke = const Color(0xFFFFFFFF),
    this.width = 1.0,
    this.opacity = 1.0,
    this.glow = 0.0,
    this.dash,
    this.casing,
    this.casingWidth = 0.55,
  });

  LayerStyle copyWith({
    bool? enabled,
    bool? filled,
    bool? outlined,
    Color? fill,
    Color? stroke,
    double? width,
    double? opacity,
    double? glow,
    List<double>? dash,
    bool clearDash = false,
    Color? casing,
    bool clearCasing = false,
    double? casingWidth,
  }) =>
      LayerStyle(
        enabled: enabled ?? this.enabled,
        filled: filled ?? this.filled,
        outlined: outlined ?? this.outlined,
        fill: fill ?? this.fill,
        stroke: stroke ?? this.stroke,
        width: width ?? this.width,
        opacity: opacity ?? this.opacity,
        glow: glow ?? this.glow,
        dash: clearDash ? null : (dash ?? this.dash),
        casing: clearCasing ? null : (casing ?? this.casing),
        casingWidth: casingWidth ?? this.casingWidth,
      );

  Map<String, dynamic> toJson() => {
        'e': enabled,
        'f': filled,
        'o': outlined,
        'fc': fill.toARGB32(),
        'sc': stroke.toARGB32(),
        'w': width,
        'op': opacity,
        'g': glow,
        if (dash != null) 'd': dash,
        if (casing != null) 'cc': casing!.toARGB32(),
        'cw': casingWidth,
      };

  factory LayerStyle.fromJson(Map<String, dynamic> j) => LayerStyle(
        enabled: j['e'] as bool? ?? true,
        filled: j['f'] as bool? ?? false,
        outlined: j['o'] as bool? ?? true,
        fill: Color(j['fc'] as int? ?? 0xFF000000),
        stroke: Color(j['sc'] as int? ?? 0xFFFFFFFF),
        width: (j['w'] as num?)?.toDouble() ?? 1.0,
        opacity: (j['op'] as num?)?.toDouble() ?? 1.0,
        glow: (j['g'] as num?)?.toDouble() ?? 0.0,
        dash: (j['d'] as List?)?.map((e) => (e as num).toDouble()).toList(),
        casing: j['cc'] == null ? null : Color(j['cc'] as int),
        casingWidth: (j['cw'] as num?)?.toDouble() ?? 0.55,
      );
}

/// The full look of a poster's map area.
class MapStyle {
  final String id;
  final String name;
  final Color background;

  /// Optional second colour for a background gradient.
  final Color? backgroundEnd;
  final double gradientAngle;

  final Map<LayerId, LayerStyle> layers;

  /// Global multiplier on every stroke width (user "thickness" slider).
  final double lineScale;

  /// How strongly buildings are tinted by their height, 0 = flat.
  final double heightShade;

  /// Colour the tallest building reaches. Null falls back to the accent.
  final Color? heightColor;

  /// Contour spacing in metres; 0 turns terrain contours off.
  final double contourInterval;

  final Color routeColor;
  final double routeWidth;
  final double routeGlow;

  /// Default poster typography colours.
  final Color textColor;
  final Color accentColor;

  /// Paper texture strength 0..1.
  final double grain;

  /// Corner darkening 0..1.
  final double vignette;

  const MapStyle({
    required this.id,
    required this.name,
    required this.background,
    this.backgroundEnd,
    this.gradientAngle = 0.35,
    required this.layers,
    this.lineScale = 1.0,
    this.heightShade = 0.0,
    this.heightColor,
    this.contourInterval = 0,
    this.routeColor = const Color(0xFFFF4D4D),
    this.routeWidth = 3.2,
    this.routeGlow = 0.5,
    required this.textColor,
    required this.accentColor,
    this.grain = 0.0,
    this.vignette = 0.0,
  });

  LayerStyle layer(LayerId id) => layers[id] ?? const LayerStyle(enabled: false);

  bool get wantsContours => contourInterval > 0 && layer(LayerId.contour).enabled;

  MapStyle copyWith({
    String? id,
    String? name,
    Color? background,
    Color? backgroundEnd,
    bool clearBackgroundEnd = false,
    double? gradientAngle,
    Map<LayerId, LayerStyle>? layers,
    double? lineScale,
    double? heightShade,
    Color? heightColor,
    double? contourInterval,
    Color? routeColor,
    double? routeWidth,
    double? routeGlow,
    Color? textColor,
    Color? accentColor,
    double? grain,
    double? vignette,
  }) =>
      MapStyle(
        id: id ?? this.id,
        name: name ?? this.name,
        background: background ?? this.background,
        backgroundEnd: clearBackgroundEnd ? null : (backgroundEnd ?? this.backgroundEnd),
        gradientAngle: gradientAngle ?? this.gradientAngle,
        layers: layers ?? this.layers,
        lineScale: lineScale ?? this.lineScale,
        heightShade: heightShade ?? this.heightShade,
        heightColor: heightColor ?? this.heightColor,
        contourInterval: contourInterval ?? this.contourInterval,
        routeColor: routeColor ?? this.routeColor,
        routeWidth: routeWidth ?? this.routeWidth,
        routeGlow: routeGlow ?? this.routeGlow,
        textColor: textColor ?? this.textColor,
        accentColor: accentColor ?? this.accentColor,
        grain: grain ?? this.grain,
        vignette: vignette ?? this.vignette,
      );

  MapStyle withLayer(LayerId id, LayerStyle style) {
    final next = Map<LayerId, LayerStyle>.from(layers);
    next[id] = style;
    return copyWith(layers: next);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'bg': background.toARGB32(),
        if (backgroundEnd != null) 'bg2': backgroundEnd!.toARGB32(),
        'ga': gradientAngle,
        'ls': lineScale,
        'hs': heightShade,
        if (heightColor != null) 'hc': heightColor!.toARGB32(),
        'ci': contourInterval,
        'rc': routeColor.toARGB32(),
        'rw': routeWidth,
        'rg': routeGlow,
        'tc': textColor.toARGB32(),
        'ac': accentColor.toARGB32(),
        'gr': grain,
        'vg': vignette,
        'layers': layers.map((k, v) => MapEntry(k.key, v.toJson())),
      };

  factory MapStyle.fromJson(Map<String, dynamic> j) {
    final raw = (j['layers'] as Map?) ?? {};
    final layers = <LayerId, LayerStyle>{};
    raw.forEach((k, v) {
      final id = layerFromKey(k as String);
      if (id != null) layers[id] = LayerStyle.fromJson(Map<String, dynamic>.from(v as Map));
    });
    return MapStyle(
      id: j['id'] as String? ?? 'custom',
      name: j['name'] as String? ?? 'Custom',
      background: Color(j['bg'] as int? ?? 0xFF101010),
      backgroundEnd: j['bg2'] == null ? null : Color(j['bg2'] as int),
      gradientAngle: (j['ga'] as num?)?.toDouble() ?? 0.35,
      layers: layers,
      lineScale: (j['ls'] as num?)?.toDouble() ?? 1.0,
      heightShade: (j['hs'] as num?)?.toDouble() ?? 0.0,
      heightColor: j['hc'] == null ? null : Color(j['hc'] as int),
      contourInterval: (j['ci'] as num?)?.toDouble() ?? 0,
      routeColor: Color(j['rc'] as int? ?? 0xFFFF4D4D),
      routeWidth: (j['rw'] as num?)?.toDouble() ?? 3.2,
      routeGlow: (j['rg'] as num?)?.toDouble() ?? 0.5,
      textColor: Color(j['tc'] as int? ?? 0xFFFFFFFF),
      accentColor: Color(j['ac'] as int? ?? 0xFFFFFFFF),
      grain: (j['gr'] as num?)?.toDouble() ?? 0.0,
      vignette: (j['vg'] as num?)?.toDouble() ?? 0.0,
    );
  }
}
