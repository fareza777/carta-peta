import 'package:carta/data/gpx_import.dart';
import 'package:flutter_test/flutter_test.dart';

const _gpx = '''<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="test">
  <metadata><name>Morning</name></metadata>
  <trk>
    <name>Sunday long run</name>
    <trkseg>
      <trkpt lat="-6.2000" lon="106.8000"><ele>10</ele><time>2024-03-01T06:00:00Z</time></trkpt>
      <trkpt lat="-6.2010" lon="106.8010"><ele>25</ele><time>2024-03-01T06:05:00Z</time></trkpt>
      <trkpt lat="-6.2020" lon="106.8020"><ele>18</ele><time>2024-03-01T06:11:00Z</time></trkpt>
      <trkpt lat="-6.2030" lon="106.8030"><ele>40</ele><time>2024-03-01T06:20:00Z</time></trkpt>
    </trkseg>
  </trk>
</gpx>''';

const _routeOnly = '''<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1"><rte>
  <rtept lat="48.85" lon="2.35"/>
  <rtept lat="48.86" lon="2.36"/>
</rte></gpx>''';

void main() {
  test('reads track points, name, distance, ascent and duration', () {
    final route = parseGpx(_gpx);
    expect(route.name, 'Sunday long run');
    expect(route.points.length, 4);
    expect(route.distanceMetres, greaterThan(400));
    expect(route.distanceMetres, lessThan(700));
    // 10 -> 25 (+15) and 18 -> 40 (+22); the 25 -> 18 descent is ignored.
    expect(route.ascentMetres, closeTo(37, 1));
    expect(route.duration, const Duration(minutes: 20));
  });

  test('falls back to route points when there is no track', () {
    final route = parseGpx(_routeOnly, fallbackName: 'Imported');
    expect(route.points.length, 2);
    expect(route.name, 'Imported');
    expect(route.duration, isNull);
  });

  test('suggested radius contains the whole track', () {
    final route = parseGpx(_gpx);
    expect(route.suggestedRadius, greaterThanOrEqualTo(400));
    final b = route.bounds;
    expect(b.south, lessThan(b.north));
    expect(b.west, lessThan(b.east));
  });

  test('rejects files that are not GPX', () {
    expect(() => parseGpx('hello world'), throwsA(isA<GpxParseException>()));
    expect(() => parseGpx('<gpx></gpx>'), throwsA(isA<GpxParseException>()));
  });
}
