import 'map_style.dart';
import 'place.dart';
import 'poster_config.dart';
import 'route_track.dart';

/// A saved artwork: place + framing + style + typography.
class Design {
  final String id;
  final PlaceRef place;
  final double radiusMetres;
  final MapStyle style;
  final PosterConfig poster;
  final String formatId;
  final RouteTrack? route;
  final double zoom;
  final bool favorite;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// File name (not full path) of the cached thumbnail.
  final String? thumbnail;

  const Design({
    required this.id,
    required this.place,
    required this.radiusMetres,
    required this.style,
    required this.poster,
    required this.formatId,
    required this.createdAt,
    required this.updatedAt,
    this.route,
    this.zoom = 1.0,
    this.favorite = false,
    this.thumbnail,
  });

  Design copyWith({
    PlaceRef? place,
    double? radiusMetres,
    MapStyle? style,
    PosterConfig? poster,
    String? formatId,
    RouteTrack? route,
    bool clearRoute = false,
    double? zoom,
    bool? favorite,
    DateTime? updatedAt,
    String? thumbnail,
  }) =>
      Design(
        id: id,
        place: place ?? this.place,
        radiusMetres: radiusMetres ?? this.radiusMetres,
        style: style ?? this.style,
        poster: poster ?? this.poster,
        formatId: formatId ?? this.formatId,
        route: clearRoute ? null : (route ?? this.route),
        zoom: zoom ?? this.zoom,
        favorite: favorite ?? this.favorite,
        createdAt: createdAt,
        updatedAt: updatedAt ?? DateTime.now(),
        thumbnail: thumbnail ?? this.thumbnail,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'place': place.toJson(),
        'r': radiusMetres,
        'style': style.toJson(),
        'poster': poster.toJson(),
        'fmt': formatId,
        if (route != null) 'route': route!.toJson(),
        'z': zoom,
        'fav': favorite,
        'ca': createdAt.millisecondsSinceEpoch,
        'ua': updatedAt.millisecondsSinceEpoch,
        if (thumbnail != null) 'th': thumbnail,
      };

  factory Design.fromJson(Map<String, dynamic> j) => Design(
        id: j['id'] as String,
        place: PlaceRef.fromJson(Map<String, dynamic>.from(j['place'] as Map)),
        radiusMetres: (j['r'] as num).toDouble(),
        style: MapStyle.fromJson(Map<String, dynamic>.from(j['style'] as Map)),
        poster: PosterConfig.fromJson(Map<String, dynamic>.from(j['poster'] as Map)),
        formatId: j['fmt'] as String? ?? 'poster23',
        route: j['route'] == null
            ? null
            : RouteTrack.fromJson(Map<String, dynamic>.from(j['route'] as Map)),
        zoom: (j['z'] as num?)?.toDouble() ?? 1.0,
        favorite: j['fav'] as bool? ?? false,
        createdAt: DateTime.fromMillisecondsSinceEpoch(j['ca'] as int),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(j['ua'] as int),
        thumbnail: j['th'] as String?,
      );
}
