import '../core/geo.dart';

/// A searchable location.
class PlaceRef {
  final String name;

  /// e.g. "Central Jakarta, Indonesia"
  final String context;
  final String country;
  final LatLng centre;
  final String? category;

  /// OSM identity of the search hit, so its boundary can be looked up later
  /// without repeating the search. 'R' for relation, 'W' for way, 'N' node.
  final String? osmType;
  final int? osmId;

  const PlaceRef({
    required this.name,
    required this.context,
    required this.country,
    required this.centre,
    this.category,
    this.osmType,
    this.osmId,
  });

  /// The id form Nominatim's lookup endpoint expects, e.g. `R1234567`.
  String? get osmRef =>
      (osmType == null || osmId == null) ? null : '$osmType$osmId';

  Map<String, dynamic> toJson() => {
        'n': name,
        'c': context,
        'co': country,
        'lat': centre.lat,
        'lon': centre.lon,
        if (category != null) 'cat': category,
        if (osmType != null) 'ot': osmType,
        if (osmId != null) 'oi': osmId,
      };

  factory PlaceRef.fromJson(Map<String, dynamic> j) => PlaceRef(
        name: j['n'] as String? ?? '',
        context: j['c'] as String? ?? '',
        country: j['co'] as String? ?? '',
        centre: LatLng((j['lat'] as num).toDouble(), (j['lon'] as num).toDouble()),
        category: j['cat'] as String?,
        osmType: j['ot'] as String?,
        osmId: j['oi'] as int?,
      );
}
