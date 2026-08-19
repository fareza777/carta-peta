import '../core/geo.dart';

/// A searchable location.
class PlaceRef {
  final String name;

  /// e.g. "Central Jakarta, Indonesia"
  final String context;
  final String country;
  final LatLng centre;
  final String? category;

  const PlaceRef({
    required this.name,
    required this.context,
    required this.country,
    required this.centre,
    this.category,
  });

  Map<String, dynamic> toJson() => {
        'n': name,
        'c': context,
        'co': country,
        'lat': centre.lat,
        'lon': centre.lon,
        if (category != null) 'cat': category,
      };

  factory PlaceRef.fromJson(Map<String, dynamic> j) => PlaceRef(
        name: j['n'] as String? ?? '',
        context: j['c'] as String? ?? '',
        country: j['co'] as String? ?? '',
        centre: LatLng((j['lat'] as num).toDouble(), (j['lon'] as num).toDouble()),
        category: j['cat'] as String?,
      );
}
