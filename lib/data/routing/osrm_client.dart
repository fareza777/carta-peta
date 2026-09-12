import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/geo.dart';
import '../../model/route_track.dart';

enum TravelMode { car, bike, foot }

extension TravelModeInfo on TravelMode {
  /// FOSSGIS runs one OSRM instance per profile, and the profile also appears
  /// in the request path.
  String get service => switch (this) {
        TravelMode.car => 'routed-car',
        TravelMode.bike => 'routed-bike',
        TravelMode.foot => 'routed-foot',
      };

  String get profile => switch (this) {
        TravelMode.car => 'driving',
        TravelMode.bike => 'bike',
        TravelMode.foot => 'foot',
      };

  String get label => switch (this) {
        TravelMode.car => 'Drive',
        TravelMode.bike => 'Cycle',
        TravelMode.foot => 'Walk',
      };
}

class RoutingFailure implements Exception {
  RoutingFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Turns two or more points into the real road route between them.
///
/// Uses the public OSRM instances FOSSGIS runs on OpenStreetMap data: free,
/// no API key, no account — the same constraint the rest of the app works
/// under. They are a shared community service, so one request per journey and
/// nothing is polled.
class OsrmClient {
  OsrmClient({http.Client? client}) : _client = client ?? http.Client();

  static const _host = 'routing.openstreetmap.de';
  static const _userAgent = 'CARTA-MapArtStudio/1.0 (Android)';

  final http.Client _client;

  Future<RouteTrack> route({
    required List<LatLng> waypoints,
    required TravelMode mode,
    required String name,
  }) async {
    if (waypoints.length < 2) {
      throw RoutingFailure('Pick a start and a destination.');
    }
    final coords = waypoints
        .map((p) => '${p.lon.toStringAsFixed(6)},${p.lat.toStringAsFixed(6)}')
        .join(';');
    final uri = Uri.https(
      _host,
      '/${mode.service}/route/v1/${mode.profile}/$coords',
      const {'overview': 'full', 'geometries': 'geojson', 'alternatives': 'false'},
    );

    late final http.Response res;
    try {
      res = await _client
          .get(uri, headers: const {'User-Agent': _userAgent})
          .timeout(const Duration(seconds: 30));
    } catch (e) {
      throw RoutingFailure('Could not reach the routing service: $e');
    }

    if (res.statusCode != 200) {
      throw RoutingFailure('Routing service error ${res.statusCode}.');
    }

    final body = jsonDecode(utf8.decode(res.bodyBytes));
    if (body is! Map || body['code'] != 'Ok') {
      final code = body is Map ? body['code'] : null;
      throw RoutingFailure(code == 'NoRoute'
          ? 'No road connects those two points for this travel mode.'
          : 'The routing service could not plan that journey.');
    }

    final routes = body['routes'];
    if (routes is! List || routes.isEmpty) {
      throw RoutingFailure('The routing service returned no route.');
    }
    final first = Map<String, dynamic>.from(routes.first as Map);
    final geometry = first['geometry'];
    final coordinates = geometry is Map ? geometry['coordinates'] : null;
    if (coordinates is! List || coordinates.length < 2) {
      throw RoutingFailure('The route came back empty.');
    }

    final points = <LatLng>[];
    for (final pair in coordinates) {
      if (pair is! List || pair.length < 2) continue;
      points.add(LatLng((pair[1] as num).toDouble(), (pair[0] as num).toDouble()));
    }
    if (points.length < 2) throw RoutingFailure('The route came back empty.');

    final seconds = (first['duration'] as num?)?.round() ?? 0;
    return RouteTrack(
      name: name,
      points: points,
      distanceMetres: (first['distance'] as num?)?.toDouble() ?? 0,
      duration: seconds > 0 ? Duration(seconds: seconds) : null,
    );
  }

  void close() => _client.close();
}
