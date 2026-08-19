/// The visual layers a rendered map is decomposed into. Order in this enum is
/// also the painting order (first painted is furthest back).
enum LayerId {
  green,
  sand,
  contour,
  water,
  waterway,
  building,
  barrier,
  rail,
  roadPath,
  roadMinor,
  roadMedium,
  roadMajor,
}

/// Where a way sits relative to the ground. Bridges must be drawn over every
/// ground-level road regardless of their own class, and tunnels under them.
enum RoadBand { tunnel, ground, bridge }

extension LayerInfo on LayerId {
  String get label => switch (this) {
        LayerId.green => 'Parks & green',
        LayerId.sand => 'Sand & beach',
        LayerId.contour => 'Terrain contours',
        LayerId.water => 'Water',
        LayerId.waterway => 'Rivers & streams',
        LayerId.building => 'Buildings',
        LayerId.barrier => 'Walls, fences & hedges',
        LayerId.rail => 'Railway',
        LayerId.roadPath => 'Paths & trails',
        LayerId.roadMinor => 'Small streets',
        LayerId.roadMedium => 'Secondary roads',
        LayerId.roadMajor => 'Main roads',
      };

  /// Polygon layers are filled, line layers are stroked.
  bool get isArea =>
      this == LayerId.green ||
      this == LayerId.sand ||
      this == LayerId.water ||
      this == LayerId.building;

  /// Layers that take part in the tunnel / ground / bridge ordering and get a
  /// casing drawn underneath.
  bool get isRoad =>
      this == LayerId.rail ||
      this == LayerId.roadPath ||
      this == LayerId.roadMinor ||
      this == LayerId.roadMedium ||
      this == LayerId.roadMajor;

  String get key => name;
}

/// Typical real-world width in metres, used when a poster is close enough to
/// draw roads to scale rather than as a fixed fraction of the sheet.
const Map<LayerId, double> kGroundWidths = {
  LayerId.roadMajor: 16,
  LayerId.roadMedium: 11,
  LayerId.roadMinor: 6.5,
  LayerId.roadPath: 2,
  LayerId.rail: 5,
  LayerId.barrier: 0.4,
  LayerId.waterway: 6,
};

/// Road classes in the order they should be stacked within one band.
const List<LayerId> kRoadOrder = [
  LayerId.rail,
  LayerId.roadPath,
  LayerId.roadMinor,
  LayerId.roadMedium,
  LayerId.roadMajor,
];

LayerId? layerFromKey(String key) {
  for (final l in LayerId.values) {
    if (l.name == key) return l;
  }
  return null;
}
