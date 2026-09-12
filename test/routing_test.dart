import 'dart:convert';

import 'package:carta/core/geo.dart';
import 'package:carta/data/routing/osrm_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _jakarta = [LatLng(-6.2337, 106.8486), LatLng(-6.2087, 106.8230)];

/// The shape of a real FOSSGIS OSRM reply, trimmed to three points.
String _ok() => jsonEncode({
      'code': 'Ok',
      'routes': [
        {
          'distance': 7283.4,
          'duration': 566.1,
          'geometry': {
            'type': 'LineString',
            'coordinates': [
              [106.8486, -6.2337],
              [106.8401, -6.2251],
              [106.8230, -6.2087],
            ],
          },
        }
      ],
      'waypoints': [
        {'name': 'Jalan Tebet Barat'},
        {'name': 'Jalan Jenderal Sudirman'},
      ],
    });

OsrmClient _client(Future<http.Response> Function(http.Request) handler) =>
    OsrmClient(client: MockClient(handler));

void main() {
  test('reads a route into a track', () async {
    late Uri seen;
    final client = _client((req) async {
      seen = req.url;
      return http.Response(_ok(), 200);
    });

    final track = await client.route(
      waypoints: _jakarta,
      mode: TravelMode.car,
      name: 'Home → Work',
    );

    expect(track.name, 'Home → Work');
    expect(track.points, hasLength(3));
    expect(track.points.first.lat, closeTo(-6.2337, 1e-6));
    expect(track.points.first.lon, closeTo(106.8486, 1e-6));
    expect(track.distanceMetres, closeTo(7283.4, 0.1));
    expect(track.duration, const Duration(seconds: 566));

    // The profile lives in the path, the geometry format in the query.
    expect(seen.host, 'routing.openstreetmap.de');
    expect(seen.path, contains('routed-car'));
    expect(seen.path, contains('/route/v1/driving/'));
    expect(seen.path, contains('106.848600,-6.233700'));
    expect(seen.queryParameters['geometries'], 'geojson');
    expect(seen.queryParameters['overview'], 'full');
  });

  test('each travel mode asks its own profile', () async {
    for (final mode in TravelMode.values) {
      late Uri seen;
      final client = _client((req) async {
        seen = req.url;
        return http.Response(_ok(), 200);
      });
      await client.route(waypoints: _jakarta, mode: mode, name: 'x');
      expect(seen.path, contains(mode.service));
      expect(seen.path, contains('/route/v1/${mode.profile}/'));
    }
  });

  test('identifies itself, as the public instances ask', () async {
    String? agent;
    final client = _client((req) async {
      agent = req.headers['User-Agent'];
      return http.Response(_ok(), 200);
    });
    await client.route(waypoints: _jakarta, mode: TravelMode.foot, name: 'x');
    expect(agent, contains('CARTA'));
  });

  test('explains when no road connects the two points', () async {
    final client = _client((_) async => http.Response(
        jsonEncode({'code': 'NoRoute', 'message': 'no route'}), 200));
    await expectLater(
      client.route(waypoints: _jakarta, mode: TravelMode.car, name: 'x'),
      throwsA(isA<RoutingFailure>().having(
          (e) => e.message, 'message', contains('No road connects'))),
    );
  });

  test('reports a server error rather than pretending', () async {
    final client = _client((_) async => http.Response('upstream down', 503));
    await expectLater(
      client.route(waypoints: _jakarta, mode: TravelMode.car, name: 'x'),
      throwsA(isA<RoutingFailure>()
          .having((e) => e.message, 'message', contains('503'))),
    );
  });

  test('refuses a reply whose geometry cannot be drawn', () async {
    final client = _client((_) async => http.Response(
        jsonEncode({
          'code': 'Ok',
          'routes': [
            {
              'distance': 10,
              'duration': 10,
              'geometry': {'type': 'LineString', 'coordinates': []},
            }
          ],
        }),
        200));
    await expectLater(
      client.route(waypoints: _jakarta, mode: TravelMode.car, name: 'x'),
      throwsA(isA<RoutingFailure>()),
    );
  });

  test('will not ask for a route with one end', () async {
    var called = false;
    final client = _client((_) async {
      called = true;
      return http.Response(_ok(), 200);
    });
    await expectLater(
      client.route(
          waypoints: [_jakarta.first], mode: TravelMode.car, name: 'x'),
      throwsA(isA<RoutingFailure>()),
    );
    expect(called, isFalse, reason: 'no request should leave the device');
  });

  test('turns a network failure into a message, not a raw exception', () async {
    final client = _client((_) async => throw const _Offline());
    await expectLater(
      client.route(waypoints: _jakarta, mode: TravelMode.car, name: 'x'),
      throwsA(isA<RoutingFailure>().having(
          (e) => e.message, 'message', contains('Could not reach'))),
    );
  });

  test('the planned track frames itself like an imported one', () async {
    final client = _client((_) async => http.Response(_ok(), 200));
    final track =
        await client.route(waypoints: _jakarta, mode: TravelMode.bike, name: 'x');
    final radius = track.suggestedRadius;
    expect(radius, greaterThan(1000));
    expect(track.centre.lat, closeTo(-6.2212, 0.002));
    expect(track.hasProfile, isFalse, reason: 'OSRM returns no elevation');
  });
}

class _Offline implements Exception {
  const _Offline();
  @override
  String toString() => 'SocketException: offline';
}
