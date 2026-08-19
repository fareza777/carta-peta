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
  final List<RouteTrack> routes;
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
    this.routes = const [],
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
    List<RouteTrack>? routes,
    bool clearRoutes = false,
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
        routes: clearRoutes ? const [] : (routes ?? this.routes),
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
        if (routes.isNotEmpty) 'routes': routes.map((r) => r.toJson()).toList(),
        'z': zoom,
        'fav': favorite,
        'ca': createdAt.millisecondsSinceEpoch,
        'ua': updatedAt.millisecondsSinceEpoch,
        if (thumbnail != null) 'th': thumbnail,
      };

  /// Reads the current list form, falling back to the single-route field that
  /// designs saved before multi-track support used.
  static List<RouteTrack> _readRoutes(Map<String, dynamic> j) {
    final list = j['routes'];
    if (list is List) {
      return list
          .map((e) => RouteTrack.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    }
    final single = j['route'];
    if (single is Map) {
      return [RouteTrack.fromJson(Map<String, dynamic>.from(single))];
    }
    return const [];
  }

  factory Design.fromJson(Map<String, dynamic> j) => Design(
        id: j['id'] as String,
        place: PlaceRef.fromJson(Map<String, dynamic>.from(j['place'] as Map)),
        radiusMetres: (j['r'] as num).toDouble(),
        style: MapStyle.fromJson(Map<String, dynamic>.from(j['style'] as Map)),
        poster: PosterConfig.fromJson(Map<String, dynamic>.from(j['poster'] as Map)),
        formatId: j['fmt'] as String? ?? 'poster23',
        routes: _readRoutes(j),
        zoom: (j['z'] as num?)?.toDouble() ?? 1.0,
        favorite: j['fav'] as bool? ?? false,
        createdAt: DateTime.fromMillisecondsSinceEpoch(j['ca'] as int),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(j['ua'] as int),
        thumbnail: j['th'] as String?,
      );
}
