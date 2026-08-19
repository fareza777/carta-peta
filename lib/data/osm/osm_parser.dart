import 'dart:convert';
import 'dart:typed_data';

import '../../core/geo.dart';
import '../../model/layer.dart';
import '../../model/map_data.dart';
import 'coastline.dart';

/// Isolate payload. Only plain values so it can cross isolate boundaries.
class OsmParseRequest {
  final String json;
  final double south;
  final double west;
  final double north;
  final double east;

  const OsmParseRequest({
    required this.json,
    required this.south,
    required this.west,
    required this.north,
    required this.east,
  });
}

/// Top-level so it can be used with `compute`. Returns the encoded dataset,
/// which is both what the cache stores and what the UI decodes.
Uint8List parseOverpassToBytes(OsmParseRequest req) {
  final bbox = BBox(req.south, req.west, req.north, req.east);
  final window = MapWindow.forBox(bbox);
  final features = <MapFeature>[];
  final coastWays = <Float32List>[];

  final root = jsonDecode(req.json);
  final elements = (root is Map && root['elements'] is List)
      ? root['elements'] as List<dynamic>
      : const <dynamic>[];

  for (final raw in elements) {
    if (raw is! Map) continue;
    final tags = (raw['tags'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
    final type = raw['type'] as String?;

    if (tags['natural'] == 'coastline' && type == 'way') {
      final pts = _project(raw['geometry'], window, close: false);
      if (pts != null) coastWays.add(pts);
      continue;
    }

    final layer = _classify(tags);
    if (layer == null) continue;
    final area = layer.isArea;

    final height = layer == LayerId.building ? _buildingHeight(tags) : 0.0;
    final band = layer.isRoad ? _band(tags) : RoadBand.ground;

    if (type == 'way') {
      final pts = _project(raw['geometry'], window, close: area);
      if (pts == null) continue;
      if (area && pts.length < 8) continue;
      features.add(MapFeature(layer, area, [pts], height: height, band: band));
    } else if (type == 'relation' && area) {
      final rings = _relationRings(raw['members'], window);
      if (rings.isNotEmpty) {
        features.add(MapFeature(layer, true, rings, height: height));
      }
    }
  }

  if (coastWays.isNotEmpty) {
    final rings = CoastlineBuilder.build(coastWays);
    if (rings.isNotEmpty) {
      features.add(MapFeature(LayerId.water, true, rings));
    } else {
      // Fall back to drawing the shoreline itself so the coast is still visible.
      for (final w in coastWays) {
        features.add(MapFeature(LayerId.waterway, false, [w]));
      }
    }
  }

  features.sort((a, b) => a.layer.index.compareTo(b.layer.index));

  return MapDataCodec.encode(MapDataSet(
    window: window,
    bbox: bbox,
    features: features,
    capturedAt: DateTime.now(),
  ));
}

// ------------------------------------------------------------------ heights

/// Typical storey height used when only `building:levels` is tagged.
const double _metresPerLevel = 3.2;

double _buildingHeight(Map<String, dynamic> tags) {
  final raw = tags['height'] ?? tags['building:height'];
  if (raw != null) {
    final parsed = double.tryParse('$raw'.replaceAll(RegExp(r'[^0-9.\-]'), ''));
    if (parsed != null && parsed > 0 && parsed < 900) return parsed;
  }
  final levels = tags['building:levels'] ?? tags['levels'];
  if (levels != null) {
    final parsed = double.tryParse('$levels'.replaceAll(RegExp(r'[^0-9.]'), ''));
    if (parsed != null && parsed > 0 && parsed < 200) return parsed * _metresPerLevel;
  }
  return 0;
}

const _tunnelValues = {'yes', 'building_passage', 'culvert', 'covered', 'avalanche_protector'};

RoadBand _band(Map<String, dynamic> tags) {
  final layerTag = int.tryParse('${tags['layer'] ?? ''}') ?? 0;
  final tunnel = tags['tunnel'];
  if (tunnel != null && tunnel != 'no' && _tunnelValues.contains('$tunnel')) {
    return RoadBand.tunnel;
  }
  final bridge = tags['bridge'];
  if (bridge != null && bridge != 'no') return RoadBand.bridge;
  if (layerTag < 0) return RoadBand.tunnel;
  if (layerTag > 0) return RoadBand.bridge;
  return RoadBand.ground;
}

// --------------------------------------------------------------------- tags

const _majorRoads = {
  'motorway', 'motorway_link', 'trunk', 'trunk_link', 'primary', 'primary_link'
};
const _mediumRoads = {'secondary', 'secondary_link', 'tertiary', 'tertiary_link'};
const _minorRoads = {'residential', 'unclassified', 'living_street', 'service', 'pedestrian'};
const _pathRoads = {'footway', 'path', 'cycleway', 'steps', 'track', 'bridleway'};
const _rails = {'rail', 'light_rail', 'subway', 'tram', 'narrow_gauge', 'monorail'};
const _greenLanduse = {
  'forest', 'grass', 'meadow', 'village_green', 'recreation_ground', 'cemetery',
  'orchard', 'vineyard', 'allotments', 'farmland', 'greenfield'
};
const _greenLeisure = {
  'park', 'garden', 'golf_course', 'nature_reserve', 'pitch', 'common', 'dog_park'
};
const _greenNatural = {'wood', 'scrub', 'grassland', 'heath', 'wetland'};
const _sandNatural = {'beach', 'sand', 'dune', 'shingle'};
const _waterways = {'river', 'stream', 'canal', 'ditch'};

LayerId? _classify(Map<String, dynamic> tags) {
  final building = tags['building'];
  if (building != null && building != 'no') return LayerId.building;

  final highway = tags['highway'] as String?;
  if (highway != null) {
    if (_majorRoads.contains(highway)) return LayerId.roadMajor;
    if (_mediumRoads.contains(highway)) return LayerId.roadMedium;
    if (_minorRoads.contains(highway)) return LayerId.roadMinor;
    if (_pathRoads.contains(highway)) return LayerId.roadPath;
    return null;
  }

  final railway = tags['railway'] as String?;
  if (railway != null && _rails.contains(railway)) return LayerId.rail;

  final natural = tags['natural'] as String?;
  final landuse = tags['landuse'] as String?;
  final waterway = tags['waterway'] as String?;
  final leisure = tags['leisure'] as String?;

  if (natural == 'water' ||
      natural == 'bay' ||
      natural == 'strait' ||
      landuse == 'reservoir' ||
      landuse == 'basin' ||
      waterway == 'riverbank' ||
      waterway == 'dock') {
    return LayerId.water;
  }
  if (natural != null && _sandNatural.contains(natural)) return LayerId.sand;
  if (waterway != null && _waterways.contains(waterway)) return LayerId.waterway;
  if (leisure != null && _greenLeisure.contains(leisure)) return LayerId.green;
  if (landuse != null && _greenLanduse.contains(landuse)) return LayerId.green;
  if (natural != null && _greenNatural.contains(natural)) return LayerId.green;
  return null;
}

// --------------------------------------------------------------- projection

/// Anything further than this outside the window is dropped.
const double _cullMin = -0.35;
const double _cullMax = 1.35;

/// Points closer than this (in window units) collapse into one. At a 4000 px
/// export that is well below half a pixel.
const double _simplifyEps = 0.00011;

Float32List? _project(dynamic geometry, MapWindow window, {required bool close}) {
  if (geometry is! List || geometry.length < 2) return null;
  final out = <double>[];
  var minX = double.infinity, minY = double.infinity;
  var maxX = -double.infinity, maxY = -double.infinity;
  double? lastX, lastY;

  for (final g in geometry) {
    if (g is! Map) continue;
    final lat = (g['lat'] as num?)?.toDouble();
    final lon = (g['lon'] as num?)?.toDouble();
    if (lat == null || lon == null) continue;
    final x = window.localX(lon);
    final y = window.localY(lat);
    if (lastX != null) {
      final dx = x - lastX;
      final dy = y - lastY!;
      if (dx * dx + dy * dy < _simplifyEps * _simplifyEps) continue;
    }
    out..add(x)..add(y);
    lastX = x;
    lastY = y;
    if (x < minX) minX = x;
    if (x > maxX) maxX = x;
    if (y < minY) minY = y;
    if (y > maxY) maxY = y;
  }

  if (out.length < 4) return null;
  if (maxX < _cullMin || minX > _cullMax || maxY < _cullMin || minY > _cullMax) return null;

  if (close) {
    if ((out[0] - out[out.length - 2]).abs() > 1e-9 ||
        (out[1] - out[out.length - 1]).abs() > 1e-9) {
      out..add(out[0])..add(out[1]);
    }
  }
  return Float32List.fromList(out);
}

List<Float32List> _relationRings(dynamic members, MapWindow window) {
  if (members is! List) return const [];
  final outer = <List<double>>[];
  final inner = <List<double>>[];

  for (final m in members) {
    if (m is! Map) continue;
    if (m['type'] != 'way') continue;
    final pts = _project(m['geometry'], window, close: false);
    if (pts == null) continue;
    final role = (m['role'] as String?) ?? '';
    (role == 'inner' ? inner : outer).add(List<double>.from(pts));
  }

  final rings = <Float32List>[];
  for (final group in [outer, inner]) {
    for (final chain in _stitch(group)) {
      if (chain.length < 8) continue;
      if ((chain[0] - chain[chain.length - 2]).abs() > 1e-9 ||
          (chain[1] - chain[chain.length - 1]).abs() > 1e-9) {
        chain..add(chain[0])..add(chain[1]);
      }
      rings.add(Float32List.fromList(chain));
    }
  }
  return rings;
}

/// Joins way fragments that share an endpoint into closed rings.
List<List<double>> _stitch(List<List<double>> parts) {
  final open = List<List<double>>.from(parts);
  final out = <List<double>>[];
  var guard = 0;
  while (open.isNotEmpty && guard++ < 4000) {
    var chain = open.removeLast();
    var grew = true;
    var inner = 0;
    while (grew && inner++ < 2000) {
      grew = false;
      if (_closedRing(chain)) break;
      for (var i = 0; i < open.length; i++) {
        final o = open[i];
        if (_near(chain[chain.length - 2], chain[chain.length - 1], o[0], o[1])) {
          chain.addAll(o.sublist(2));
        } else if (_near(chain[chain.length - 2], chain[chain.length - 1],
            o[o.length - 2], o[o.length - 1])) {
          for (var k = o.length - 4; k >= 0; k -= 2) {
            chain..add(o[k])..add(o[k + 1]);
          }
        } else if (_near(chain[0], chain[1], o[o.length - 2], o[o.length - 1])) {
          chain = [...o.sublist(0, o.length - 2), ...chain];
        } else if (_near(chain[0], chain[1], o[0], o[1])) {
          final rev = <double>[];
          for (var k = o.length - 2; k >= 2; k -= 2) {
            rev..add(o[k])..add(o[k + 1]);
          }
          chain = [...rev, ...chain];
        } else {
          continue;
        }
        open.removeAt(i);
        grew = true;
        break;
      }
    }
    out.add(chain);
  }
  return out;
}

bool _closedRing(List<double> c) =>
    c.length >= 6 && _near(c[0], c[1], c[c.length - 2], c[c.length - 1]);

bool _near(double ax, double ay, double bx, double by) =>
    (ax - bx).abs() < 2e-6 && (ay - by).abs() < 2e-6;
