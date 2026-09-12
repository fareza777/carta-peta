import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/geo.dart';
import '../../model/area_boundary.dart';
import '../../model/place.dart';

/// Thin Nominatim wrapper. Nominatim's usage policy requires an identifying
/// User-Agent and at most one request per second, both honoured here.
class NominatimClient {
  NominatimClient({http.Client? client}) : _client = client ?? http.Client();

  static const _base = 'nominatim.openstreetmap.org';
  static const _userAgent = 'CARTA-MapArtStudio/1.0 (Android; contact via app store listing)';
  static const _minInterval = Duration(milliseconds: 1100);

  final http.Client _client;
  DateTime _lastCall = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> _throttle() async {
    final since = DateTime.now().difference(_lastCall);
    if (since < _minInterval) {
      await Future<void>.delayed(_minInterval - since);
    }
    _lastCall = DateTime.now();
  }

  Future<List<PlaceRef>> search(String query, {int limit = 8}) async {
    final q = query.trim();
    if (q.length < 2) return const [];
    await _throttle();
    final uri = Uri.https(_base, '/search', {
      'q': q,
      'format': 'jsonv2',
      'limit': '$limit',
      'addressdetails': '1',
      'accept-language': 'en',
    });
    final res = await _client
        .get(uri, headers: const {'User-Agent': _userAgent, 'Accept': 'application/json'})
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) {
      throw HttpFailure('Search unavailable (${res.statusCode})');
    }
    final list = jsonDecode(utf8.decode(res.bodyBytes)) as List<dynamic>;
    return list.map(_toPlace).whereType<PlaceRef>().toList();
  }

  /// Fetches the outline of a place that has one. Kept separate from [search]
  /// so an ordinary search never pays for polygon geometry it will not draw.
  Future<AreaBoundary?> boundaryOf(PlaceRef place) async {
    // A curated place, or one restored from a design saved before OSM ids were
    // kept, carries no id. Looking the name up again is cheaper than making
    // the user search for a place they are already looking at.
    var ref = place.osmRef;
    if (ref == null) {
      final query = place.context.isEmpty
          ? place.name
          : '${place.name}, ${place.context}';
      try {
        final hits = await search(query, limit: 1);
        ref = hits.isEmpty ? null : hits.first.osmRef;
      } on Exception {
        return null;
      }
      if (ref == null) return null;
    }
    await _throttle();
    final uri = Uri.https(_base, '/lookup', {
      'osm_ids': ref,
      'format': 'jsonv2',
      'polygon_geojson': '1',
      'accept-language': 'en',
    });
    try {
      final res = await _client
          .get(uri, headers: const {'User-Agent': _userAgent, 'Accept': 'application/json'})
          .timeout(const Duration(seconds: 25));
      if (res.statusCode != 200) return null;
      final list = jsonDecode(utf8.decode(res.bodyBytes));
      if (list is! List || list.isEmpty) return null;
      final entry = Map<String, dynamic>.from(list.first as Map);
      return AreaBoundary.fromGeoJson(place.name, entry['geojson']);
    } catch (_) {
      return null;
    }
  }

  Future<PlaceRef?> reverse(LatLng point) async {
    await _throttle();
    final uri = Uri.https(_base, '/reverse', {
      'lat': '${point.lat}',
      'lon': '${point.lon}',
      'format': 'jsonv2',
      'zoom': '14',
      'addressdetails': '1',
      'accept-language': 'en',
    });
    try {
      final res = await _client
          .get(uri, headers: const {'User-Agent': _userAgent, 'Accept': 'application/json'})
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) return null;
      final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      return _toPlace(j);
    } catch (_) {
      return null;
    }
  }

  PlaceRef? _toPlace(dynamic raw) {
    if (raw is! Map) return null;
    final j = Map<String, dynamic>.from(raw);
    final lat = double.tryParse('${j['lat']}');
    final lon = double.tryParse('${j['lon']}');
    if (lat == null || lon == null) return null;

    final display = (j['display_name'] as String?) ?? '';
    final parts = display.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    final address = (j['address'] as Map?)?.cast<String, dynamic>() ?? const {};

    final name = (j['name'] as String?)?.trim().isNotEmpty == true
        ? (j['name'] as String).trim()
        : (parts.isNotEmpty ? parts.first : display);

    final country = (address['country'] as String?) ?? (parts.isNotEmpty ? parts.last : '');

    final contextParts = <String>[];
    for (final key in ['city', 'town', 'village', 'municipality', 'county', 'state']) {
      final v = address[key] as String?;
      if (v != null && v != name && !contextParts.contains(v)) contextParts.add(v);
      if (contextParts.length >= 2) break;
    }
    if (country.isNotEmpty && !contextParts.contains(country)) contextParts.add(country);
    if (contextParts.isEmpty && parts.length > 1) {
      contextParts.addAll(parts.sublist(1).take(2));
    }

    return PlaceRef(
      name: name,
      context: contextParts.join(', '),
      country: country,
      centre: LatLng(lat, lon),
      category: j['type'] as String?,
      osmType: switch (j['osm_type']) {
        'relation' => 'R',
        'way' => 'W',
        'node' => 'N',
        _ => null,
      },
      osmId: (j['osm_id'] as num?)?.toInt(),
    );
  }

  void close() => _client.close();
}

class HttpFailure implements Exception {
  final String message;
  HttpFailure(this.message);
  @override
  String toString() => message;
}
