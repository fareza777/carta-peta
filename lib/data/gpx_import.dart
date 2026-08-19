import 'dart:math' as math;

import 'package:xml/xml.dart';

import '../core/geo.dart';
import '../model/route_track.dart';

class GpxParseException implements Exception {
  final String message;
  GpxParseException(this.message);
  @override
  String toString() => message;
}

/// Reads a GPX file exported by Strava, Garmin, Komoot, Apple Fitness, ...
RouteTrack parseGpx(String xmlText, {String fallbackName = 'Route'}) {
  late final XmlDocument doc;
  try {
    doc = XmlDocument.parse(xmlText);
  } catch (e) {
    throw GpxParseException('That file is not valid GPX.');
  }

  final points = <LatLng>[];
  final elevations = <double?>[];
  final times = <DateTime?>[];

  void collect(String tag) {
    for (final node in doc.findAllElements(tag)) {
      final lat = double.tryParse(node.getAttribute('lat') ?? '');
      final lon = double.tryParse(node.getAttribute('lon') ?? '');
      if (lat == null || lon == null) continue;
      points.add(LatLng(lat, lon));
      final ele = node.getElement('ele')?.innerText.trim();
      elevations.add(ele == null ? null : double.tryParse(ele));
      final t = node.getElement('time')?.innerText.trim();
      times.add(t == null ? null : DateTime.tryParse(t));
    }
  }

  collect('trkpt');
  if (points.isEmpty) collect('rtept');
  if (points.isEmpty) collect('wpt');
  if (points.length < 2) {
    throw GpxParseException('No track points found in that GPX file.');
  }

  var name = doc.findAllElements('trk').firstOrNull?.getElement('name')?.innerText.trim();
  name ??= doc.findAllElements('metadata').firstOrNull?.getElement('name')?.innerText.trim();
  if (name == null || name.isEmpty) name = fallbackName;

  var distance = 0.0;
  for (var i = 1; i < points.length; i++) {
    distance += haversineMetres(points[i - 1], points[i]);
  }

  var ascent = 0.0;
  double? lastEle;
  for (final e in elevations) {
    if (e == null) continue;
    if (lastEle != null && e - lastEle > 1.0) ascent += e - lastEle;
    if (lastEle == null || (e - lastEle).abs() > 1.0) lastEle = e;
  }

  final stamps = times.whereType<DateTime>().toList();
  final duration = stamps.length >= 2 ? stamps.last.difference(stamps.first) : null;

  return RouteTrack(
    name: name,
    elevations: _profile(elevations),
    points: _decimate(points, 12000),
    distanceMetres: distance,
    ascentMetres: ascent,
    duration: duration != null && duration.inSeconds > 0 ? duration : null,
    recordedAt: stamps.isNotEmpty ? stamps.first : null,
  );
}

/// A fixed-length elevation series for the poster profile. Anything longer is
/// averaged down so the drawing cost does not depend on how long the ride was.
List<double> _profile(List<double?> raw, {int buckets = 160}) {
  final values = raw.whereType<double>().toList();
  if (values.length < 5) return const [];
  if (values.length <= buckets) return values;
  final out = <double>[];
  final size = values.length / buckets;
  for (var i = 0; i < buckets; i++) {
    final from = (i * size).floor();
    final to = math.min(values.length, ((i + 1) * size).ceil());
    var sum = 0.0;
    for (var k = from; k < to; k++) {
      sum += values[k];
    }
    out.add(sum / math.max(1, to - from));
  }
  return out;
}

List<LatLng> _decimate(List<LatLng> pts, int maxPoints) {
  if (pts.length <= maxPoints) return pts;
  final step = (pts.length / maxPoints).ceil();
  final out = <LatLng>[];
  for (var i = 0; i < pts.length; i += step) {
    out.add(pts[i]);
  }
  if (out.last != pts.last) out.add(pts.last);
  return out;
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
