import 'package:carta/core/format.dart';
import 'package:carta/core/geo.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Mercator', () {
    test('round trips longitude and latitude', () {
      for (final p in [
        const LatLng(0, 0),
        const LatLng(-6.2088, 106.8456),
        const LatLng(51.5074, -0.1278),
        const LatLng(-33.8688, 151.2093),
      ]) {
        expect(Mercator.lon(Mercator.x(p.lon)), closeTo(p.lon, 1e-9));
        expect(Mercator.lat(Mercator.y(p.lat)), closeTo(p.lat, 1e-7));
      }
    });

    test('y grows southwards', () {
      expect(Mercator.y(50), lessThan(Mercator.y(-50)));
    });
  });

  group('BBox.square', () {
    test('is roughly square on the ground', () {
      const centre = LatLng(-6.2088, 106.8456);
      final box = BBox.square(centre, 1500);
      final width = haversineMetres(
          LatLng(centre.lat, box.west), LatLng(centre.lat, box.east));
      final height =
          haversineMetres(LatLng(box.south, centre.lon), LatLng(box.north, centre.lon));
      expect(width, closeTo(3000, 60));
      expect(height, closeTo(3000, 60));
    });

    test('stays square at high latitude', () {
      const centre = LatLng(60.17, 24.94);
      final box = BBox.square(centre, 2000);
      final width = haversineMetres(
          LatLng(centre.lat, box.west), LatLng(centre.lat, box.east));
      final height =
          haversineMetres(LatLng(box.south, centre.lon), LatLng(box.north, centre.lon));
      expect((width - height).abs() / width, lessThan(0.05));
    });
  });

  group('MapWindow', () {
    test('maps the box centre to the middle of the window', () {
      const centre = LatLng(48.8566, 2.3522);
      final window = MapWindow.forBox(BBox.square(centre, 1200));
      expect(window.localX(centre.lon), closeTo(0.5, 1e-6));
      expect(window.localY(centre.lat), closeTo(0.5, 1e-6));
    });

    test('reports a sensible ground span', () {
      const centre = LatLng(-6.2088, 106.8456);
      final window = MapWindow.forBox(BBox.square(centre, 1500));
      expect(window.groundSpanMetres, closeTo(3000, 120));
    });

    test('keeps float32 precision below a metre for city captures', () {
      const centre = LatLng(-6.2088, 106.8456);
      final window = MapWindow.forBox(BBox.square(centre, 1500));
      final a = window.localX(centre.lon);
      final b = window.localX(centre.lon + 0.00001); // ~1.1 m
      expect((b - a) * window.groundSpanMetres, greaterThan(0.5));
    });
  });

  group('formatting', () {
    test('DMS carries hemisphere letters', () {
      final s = formatDms(const LatLng(-6.2088, 106.8456));
      expect(s, contains('S'));
      expect(s, contains('E'));
      expect(s, contains('6'));
    });

    test('radius switches to km', () {
      expect(formatRadius(800), '800 m');
      expect(formatRadius(2000), '2 km');
      expect(formatRadius(2500), '2.5 km');
    });

    test('distance formatting', () {
      expect(formatDistance(420), '420 m');
      expect(formatDistance(4200), '4.20 km');
      expect(formatDistance(42000), '42 km');
    });
  });
}
