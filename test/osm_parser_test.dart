import 'dart:convert';
import 'dart:typed_data';

import 'package:carta/data/osm/osm_parser.dart';
import 'package:carta/model/layer.dart';
import 'package:carta/model/map_data.dart';
import 'package:flutter_test/flutter_test.dart';

const _south = -6.22;
const _west = 106.83;
const _north = -6.20;
const _east = 106.85;

Map<String, dynamic> _way(
  int id,
  Map<String, String> tags,
  List<List<double>> coords,
) =>
    {
      'type': 'way',
      'id': id,
      'tags': tags,
      'geometry': [
        for (final c in coords) {'lat': c[0], 'lon': c[1]}
      ],
    };

MapDataSet _parse(List<Map<String, dynamic>> elements) {
  final bytes = parseOverpassToBytes(OsmParseRequest(
    json: jsonEncode({'elements': elements}),
    south: _south,
    west: _west,
    north: _north,
    east: _east,
  ));
  final data = MapDataCodec.decode(bytes);
  expect(data, isNotNull);
  return data!;
}

void main() {
  test('classifies roads into weight classes', () {
    final data = _parse([
      _way(1, {'highway': 'primary'}, [
        [-6.21, 106.835],
        [-6.21, 106.845]
      ]),
      _way(2, {'highway': 'secondary'}, [
        [-6.212, 106.835],
        [-6.212, 106.845]
      ]),
      _way(3, {'highway': 'residential'}, [
        [-6.214, 106.835],
        [-6.214, 106.845]
      ]),
      _way(4, {'highway': 'footway'}, [
        [-6.216, 106.835],
        [-6.216, 106.845]
      ]),
      _way(5, {'railway': 'rail'}, [
        [-6.218, 106.835],
        [-6.218, 106.845]
      ]),
    ]);

    final counts = data.layerCounts;
    expect(counts[LayerId.roadMajor], 1);
    expect(counts[LayerId.roadMedium], 1);
    expect(counts[LayerId.roadMinor], 1);
    expect(counts[LayerId.roadPath], 1);
    expect(counts[LayerId.rail], 1);
  });

  test('ignores untagged and irrelevant ways', () {
    final data = _parse([
      _way(1, {'power': 'line'}, [
        [-6.21, 106.835],
        [-6.21, 106.845]
      ]),
      _way(2, {'building': 'no'}, [
        [-6.211, 106.836],
        [-6.211, 106.837],
        [-6.212, 106.837]
      ]),
    ]);
    expect(data.features, isEmpty);
  });

  test('walls and hedges are kept, other barriers are not', () {
    final data = _parse([
      _way(1, {'barrier': 'fence'}, [
        [-6.21, 106.835],
        [-6.21, 106.845]
      ]),
      _way(2, {'barrier': 'gate'}, [
        [-6.212, 106.835],
        [-6.212, 106.845]
      ]),
    ]);
    expect(data.layerCounts[LayerId.barrier], 1);
  });

  test('area layers are closed even when the source ring is open', () {
    final data = _parse([
      _way(1, {'leisure': 'park'}, [
        [-6.210, 106.836],
        [-6.210, 106.840],
        [-6.213, 106.840],
        [-6.213, 106.836],
      ]),
    ]);
    expect(data.features.length, 1);
    final f = data.features.first;
    expect(f.layer, LayerId.green);
    expect(f.closed, isTrue);
    final ring = f.parts.first;
    expect(ring[0], closeTo(ring[ring.length - 2], 1e-6));
    expect(ring[1], closeTo(ring[ring.length - 1], 1e-6));
  });

  test('multipolygon relations stitch split member ways into rings', () {
    final relation = {
      'type': 'relation',
      'id': 99,
      'tags': {'natural': 'water'},
      'members': [
        {
          'type': 'way',
          'role': 'outer',
          'geometry': [
            {'lat': -6.210, 'lon': 106.836},
            {'lat': -6.210, 'lon': 106.842},
          ],
        },
        {
          'type': 'way',
          'role': 'outer',
          'geometry': [
            {'lat': -6.210, 'lon': 106.842},
            {'lat': -6.216, 'lon': 106.842},
            {'lat': -6.216, 'lon': 106.836},
            {'lat': -6.210, 'lon': 106.836},
          ],
        },
        {
          'type': 'way',
          'role': 'inner',
          'geometry': [
            {'lat': -6.212, 'lon': 106.838},
            {'lat': -6.212, 'lon': 106.840},
            {'lat': -6.214, 'lon': 106.840},
            {'lat': -6.214, 'lon': 106.838},
            {'lat': -6.212, 'lon': 106.838},
          ],
        },
      ],
    };

    final data = _parse([relation]);
    expect(data.features.length, 1);
    final f = data.features.first;
    expect(f.layer, LayerId.water);
    expect(f.closed, isTrue);
    // one stitched outer ring plus the island hole
    expect(f.parts.length, 2);
    expect(f.parts.first.length ~/ 2, greaterThanOrEqualTo(5));
  });

  test('drops geometry far outside the poster window', () {
    final data = _parse([
      _way(1, {'highway': 'primary'}, [
        [-7.5, 105.0],
        [-7.5, 105.1]
      ]),
    ]);
    expect(data.features, isEmpty);
  });

  test('collapses duplicate points', () {
    final data = _parse([
      _way(1, {'highway': 'primary'}, [
        [-6.210, 106.836],
        [-6.210, 106.836],
        [-6.210, 106.836],
        [-6.210, 106.842],
      ]),
    ]);
    expect(data.features.single.pointCount, 2);
  });

  test('features come out in painting order', () {
    final data = _parse([
      _way(1, {'highway': 'primary'}, [
        [-6.210, 106.836],
        [-6.210, 106.842]
      ]),
      _way(2, {'leisure': 'park'}, [
        [-6.211, 106.836],
        [-6.211, 106.838],
        [-6.212, 106.838],
      ]),
      _way(3, {'building': 'yes'}, [
        [-6.213, 106.836],
        [-6.213, 106.837],
        [-6.214, 106.837],
      ]),
    ]);
    final order = data.features.map((f) => f.layer.index).toList();
    final sorted = [...order]..sort();
    expect(order, sorted);
  });

  test('binary codec round trips', () {
    final data = _parse([
      _way(1, {'highway': 'primary'}, [
        [-6.210, 106.836],
        [-6.210, 106.842]
      ]),
      _way(2, {'natural': 'water'}, [
        [-6.211, 106.836],
        [-6.211, 106.838],
        [-6.212, 106.838],
      ]),
    ]);
    final decoded = MapDataCodec.decode(MapDataCodec.encode(data))!;
    expect(decoded.features.length, data.features.length);
    expect(decoded.pointCount, data.pointCount);
    expect(decoded.window.span, closeTo(data.window.span, 1e-12));
    expect(decoded.features.first.parts.first.first,
        closeTo(data.features.first.parts.first.first, 1e-6));
  });

  test('rejects corrupt cache payloads instead of throwing', () {
    expect(MapDataCodec.decode(Uint8List.fromList([1, 2, 3, 4, 5])), isNull);
  });
}
