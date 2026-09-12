import 'dart:convert';

import 'package:carta/core/geo.dart';
import 'package:carta/data/osm/nominatim_client.dart';
import 'package:carta/model/place.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _tebet = PlaceRef(
  name: 'Tebet Barat',
  context: 'South Jakarta, Indonesia',
  country: 'Indonesia',
  centre: LatLng(-6.2337, 106.8486),
  osmType: 'R',
  osmId: 7152610,
);

/// The shape Nominatim's /lookup returns, trimmed to four points.
String _lookup() => jsonEncode([
      {
        'osm_type': 'relation',
        'osm_id': 7152610,
        'name': 'Tebet Barat',
        'lat': '-6.2337',
        'lon': '106.8486',
        'display_name': 'Tebet Barat, Tebet, South Jakarta',
        'geojson': {
          'type': 'Polygon',
          'coordinates': [
            [
              [106.84388, -6.24330],
              [106.85346, -6.24330],
              [106.85346, -6.22414],
              [106.84388, -6.22414],
              [106.84388, -6.24330],
            ]
          ],
        },
      }
    ]);

String _searchHit() => jsonEncode([
      {
        'osm_type': 'relation',
        'osm_id': 7152610,
        'name': 'Tebet Barat',
        'type': 'administrative',
        'lat': '-6.2337',
        'lon': '106.8486',
        'display_name': 'Tebet Barat, Tebet, South Jakarta, Indonesia',
        'address': {'city': 'Jakarta', 'country': 'Indonesia'},
      }
    ]);

/// A real RW: Jakarta maps them as administrative relations, and the number
/// alone ("RW 01") is useless as a title.
String _rwLookup() => jsonEncode([
      {
        'osm_type': 'relation',
        'osm_id': 7152617,
        'name': 'RW 01',
        'display_name':
            'RW 01, Tebet Barat, Tebet, South Jakarta, Special Capital Region of Jakarta',
        'geojson': {
          'type': 'Polygon',
          'coordinates': [
            [
              [106.8470, -6.2290],
              [106.8520, -6.2290],
              [106.8520, -6.2240],
              [106.8470, -6.2240],
              [106.8470, -6.2290],
            ]
          ],
        },
      }
    ]);

void main() {
  test('fetches the outline of a place that has one', () async {
    late Uri seen;
    final client = NominatimClient(client: MockClient((req) async {
      seen = req.url;
      return http.Response(_lookup(), 200);
    }));

    final area = await client.boundaryOf(_tebet);
    expect(area, isNotNull);
    expect(area!.name, 'Tebet Barat');
    expect(area.rings.first, hasLength(5));
    expect(area.suggestedRadius, greaterThan(1000));

    expect(seen.path, '/lookup');
    expect(seen.queryParameters['osm_ids'], 'R7152610');
    expect(seen.queryParameters['polygon_geojson'], '1');
  });

  test('looks the name up again when the place carries no OSM id', () async {
    final paths = <String>[];
    final client = NominatimClient(client: MockClient((req) async {
      paths.add(req.url.path);
      return http.Response(
          req.url.path == '/search' ? _searchHit() : _lookup(), 200);
    }));

    const curated = PlaceRef(
      name: 'Tebet Barat',
      context: 'South Jakarta, Indonesia',
      country: 'Indonesia',
      centre: LatLng(-6.2337, 106.8486),
    );
    final area = await client.boundaryOf(curated);
    expect(area, isNotNull);
    expect(paths, ['/search', '/lookup']);
  });

  test('a place with no outline comes back as null, not an error', () async {
    final client = NominatimClient(client: MockClient((_) async => http.Response(
        jsonEncode([
          {'osm_type': 'node', 'osm_id': 1, 'name': 'A cafe'}
        ]),
        200)));
    expect(await client.boundaryOf(_tebet), isNull);
  });

  test('a server error comes back as null, not an exception', () async {
    final client =
        NominatimClient(client: MockClient((_) async => http.Response('busy', 503)));
    expect(await client.boundaryOf(_tebet), isNull);
  });

  test('an RW is titled with the kelurahan it sits in', () async {
    final client = NominatimClient(
        client: MockClient((_) async => http.Response(_rwLookup(), 200)));
    const rw = PlaceRef(
      name: 'RW 01',
      context: 'Jakarta, Indonesia',
      country: 'Indonesia',
      centre: LatLng(-6.2268, 106.8495),
      osmType: 'R',
      osmId: 7152617,
    );
    final area = await client.boundaryOf(rw);
    expect(area!.name, 'RW 01 Tebet Barat');
  });

  test('an ordinary place keeps its own name', () async {
    final client = NominatimClient(
        client: MockClient((_) async => http.Response(_lookup(), 200)));
    final area = await client.boundaryOf(_tebet);
    expect(area!.name, 'Tebet Barat',
        reason: 'only RT/RW codes need their parent folded in');
  });

  test('search keeps the OSM identity so a boundary can be fetched later', () async {
    final client =
        NominatimClient(client: MockClient((_) async => http.Response(_searchHit(), 200)));
    final hits = await client.search('Tebet Barat');
    expect(hits, hasLength(1));
    expect(hits.first.osmRef, 'R7152610');
    expect(hits.first.name, 'Tebet Barat');
  });
}
