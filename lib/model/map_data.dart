import 'dart:convert';
import 'dart:typed_data';

import '../core/geo.dart';
import 'layer.dart';

/// A single drawable geometry. Coordinates are stored interleaved (x,y) in
/// window-local units where 0..1 spans the captured [MapWindow]. Storing them
/// locally (rather than world Mercator) keeps float32 precision at millimetre
/// level for city-scale captures.
class MapFeature {
  final LayerId layer;

  /// True for polygons (filled), false for polylines.
  final bool closed;

  /// One entry per ring. For multipolygons the extra rings are holes and are
  /// rendered with an even-odd fill.
  final List<Float32List> parts;

  /// Buildings: height in metres (0 when untagged). Contours: elevation.
  final double height;

  /// Vertical band, used to keep flyovers above the roads they cross.
  final RoadBand band;

  /// OSM `name`, kept so the renderer can letter the map.
  final String? name;

  const MapFeature(
    this.layer,
    this.closed,
    this.parts, {
    this.height = 0,
    this.band = RoadBand.ground,
    this.name,
  });

  int get pointCount {
    var n = 0;
    for (final p in parts) {
      n += p.length >> 1;
    }
    return n;
  }
}

/// A captured, projected and layered slice of OpenStreetMap.
class MapDataSet {
  final MapWindow window;
  final BBox bbox;
  final List<MapFeature> features;
  final DateTime capturedAt;

  MapDataSet({
    required this.window,
    required this.bbox,
    required this.features,
    required this.capturedAt,
  });

  bool get hasContours => features.any((f) => f.layer == LayerId.contour);

  int get pointCount {
    var n = 0;
    for (final f in features) {
      n += f.pointCount;
    }
    return n;
  }

  Map<LayerId, int> get layerCounts {
    final m = <LayerId, int>{};
    for (final f in features) {
      m[f.layer] = (m[f.layer] ?? 0) + 1;
    }
    return m;
  }

  /// Highest tagged building, used to normalise height shading.
  double get tallestBuilding {
    var top = 0.0;
    for (final f in features) {
      if (f.layer == LayerId.building && f.height > top) top = f.height;
    }
    return top;
  }

  MapDataSet withExtra(List<MapFeature> extra) {
    final merged = [...features, ...extra]
      ..sort((a, b) => a.layer.index.compareTo(b.layer.index));
    return MapDataSet(
      window: window,
      bbox: bbox,
      features: merged,
      capturedAt: capturedAt,
    );
  }

  /// A cheaper copy used for preset thumbnails: drops tiny geometry and
  /// decimates long ways.
  MapDataSet decimated({int step = 3, double minExtent = 0.004}) {
    final out = <MapFeature>[];
    for (final f in features) {
      final parts = <Float32List>[];
      for (final p in f.parts) {
        final n = p.length >> 1;
        if (n < 2) continue;
        if (_extent(p) < minExtent && f.layer == LayerId.building) continue;
        if (n <= 4 || step <= 1) {
          parts.add(p);
          continue;
        }
        final keep = <double>[];
        for (var i = 0; i < n; i += step) {
          keep..add(p[i * 2])..add(p[i * 2 + 1]);
        }
        // always keep the final vertex so shapes close correctly
        if ((n - 1) % step != 0) {
          keep..add(p[(n - 1) * 2])..add(p[(n - 1) * 2 + 1]);
        }
        if (keep.length >= 4) parts.add(Float32List.fromList(keep));
      }
      if (parts.isNotEmpty) {
        out.add(MapFeature(f.layer, f.closed, parts,
            height: f.height, band: f.band, name: f.name));
      }
    }
    return MapDataSet(window: window, bbox: bbox, features: out, capturedAt: capturedAt);
  }

  static double _extent(Float32List p) {
    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    for (var i = 0; i < p.length; i += 2) {
      if (p[i] < minX) minX = p[i];
      if (p[i] > maxX) maxX = p[i];
      if (p[i + 1] < minY) minY = p[i + 1];
      if (p[i + 1] > maxY) maxY = p[i + 1];
    }
    final w = maxX - minX, h = maxY - minY;
    return w > h ? w : h;
  }
}

/// Compact binary encoding used for the on-device tile cache.
class MapDataCodec {
  static const int _magic = 0x43415254; // 'CART'
  static final Uint8List _noName = Uint8List(0);

  /// v2 added per-feature height and vertical band, v3 added names. Bumping
  /// the version makes older cache files decode to null, so they are simply
  /// refetched rather than misread.
  static const int _version = 3;

  static Uint8List encode(MapDataSet data) {
    var bytes = 4 + 4 + 8 * 3 + 8 * 4 + 8 + 4;
    final names = <Uint8List>[];
    for (final f in data.features) {
      names.add(f.name == null ? _noName : utf8.encode(f.name!));
      bytes += 1 + 1 + 1 + 4 + 2 + names.last.length + 4;
      for (final p in f.parts) {
        bytes += 4 + p.length * 4;
      }
    }
    final buf = ByteData(bytes);
    var o = 0;
    buf.setUint32(o, _magic); o += 4;
    buf.setUint32(o, _version); o += 4;
    buf.setFloat64(o, data.window.originX); o += 8;
    buf.setFloat64(o, data.window.originY); o += 8;
    buf.setFloat64(o, data.window.span); o += 8;
    buf.setFloat64(o, data.bbox.south); o += 8;
    buf.setFloat64(o, data.bbox.west); o += 8;
    buf.setFloat64(o, data.bbox.north); o += 8;
    buf.setFloat64(o, data.bbox.east); o += 8;
    buf.setFloat64(o, data.capturedAt.millisecondsSinceEpoch.toDouble()); o += 8;
    buf.setUint32(o, data.features.length); o += 4;
    for (var i = 0; i < data.features.length; i++) {
      final f = data.features[i];
      buf.setUint8(o, f.layer.index); o += 1;
      buf.setUint8(o, f.closed ? 1 : 0); o += 1;
      buf.setUint8(o, f.band.index); o += 1;
      buf.setFloat32(o, f.height); o += 4;
      final name = names[i];
      buf.setUint16(o, name.length); o += 2;
      for (var k = 0; k < name.length; k++) {
        buf.setUint8(o, name[k]); o += 1;
      }
      buf.setUint32(o, f.parts.length); o += 4;
      for (final p in f.parts) {
        buf.setUint32(o, p.length); o += 4;
        for (var v = 0; v < p.length; v++) {
          buf.setFloat32(o, p[v]); o += 4;
        }
      }
    }
    return buf.buffer.asUint8List(0, o);
  }

  static MapDataSet? decode(Uint8List raw) {
    try {
      final buf = ByteData.sublistView(raw);
      var o = 0;
      if (buf.getUint32(o) != _magic) return null;
      o += 4;
      if (buf.getUint32(o) != _version) return null;
      o += 4;
      final ox = buf.getFloat64(o); o += 8;
      final oy = buf.getFloat64(o); o += 8;
      final sp = buf.getFloat64(o); o += 8;
      final s = buf.getFloat64(o); o += 8;
      final w = buf.getFloat64(o); o += 8;
      final n = buf.getFloat64(o); o += 8;
      final e = buf.getFloat64(o); o += 8;
      final ts = buf.getFloat64(o).toInt(); o += 8;
      final count = buf.getUint32(o); o += 4;
      final features = <MapFeature>[];
      for (var i = 0; i < count; i++) {
        final layer = LayerId.values[buf.getUint8(o)]; o += 1;
        final closed = buf.getUint8(o) == 1; o += 1;
        final band = RoadBand.values[buf.getUint8(o)]; o += 1;
        final height = buf.getFloat32(o); o += 4;
        final nameLength = buf.getUint16(o); o += 2;
        String? name;
        if (nameLength > 0) {
          name = utf8.decode(raw.sublist(o, o + nameLength), allowMalformed: true);
          o += nameLength;
        }
        final partCount = buf.getUint32(o); o += 4;
        final parts = <Float32List>[];
        for (var j = 0; j < partCount; j++) {
          final len = buf.getUint32(o); o += 4;
          final list = Float32List(len);
          for (var k = 0; k < len; k++) {
            list[k] = buf.getFloat32(o); o += 4;
          }
          parts.add(list);
        }
        features.add(
            MapFeature(layer, closed, parts, height: height, band: band, name: name));
      }
      return MapDataSet(
        window: MapWindow(ox, oy, sp),
        bbox: BBox(s, w, n, e),
        features: features,
        capturedAt: DateTime.fromMillisecondsSinceEpoch(ts),
      );
    } catch (_) {
      return null;
    }
  }
}
