import '../../core/geo.dart';

/// How much OSM detail to request. Wider captures automatically drop the
/// heaviest layers so a poster of a whole city still renders quickly.
enum DetailLevel { full, high, medium, wide }

DetailLevel detailForRadius(double radiusMetres) {
  if (radiusMetres <= 1400) return DetailLevel.full;
  if (radiusMetres <= 3200) return DetailLevel.high;
  if (radiusMetres <= 7000) return DetailLevel.medium;
  return DetailLevel.wide;
}

extension DetailInfo on DetailLevel {
  bool get includesBuildings => this == DetailLevel.full || this == DetailLevel.high;
  bool get includesPaths => this == DetailLevel.full || this == DetailLevel.high;
  bool get includesMinorRoads => this != DetailLevel.wide;

  String get label => switch (this) {
        DetailLevel.full => 'Full detail',
        DetailLevel.high => 'High detail',
        DetailLevel.medium => 'Balanced',
        DetailLevel.wide => 'Wide area',
      };
}

/// Builds an Overpass QL request for a bounding box.
String buildOverpassQuery(BBox box, DetailLevel detail) {
  final b = box.overpass;
  final buf = StringBuffer()
    ..writeln('[out:json][timeout:120];')
    ..writeln('(');

  // Roads -----------------------------------------------------------------
  final major = 'motorway|motorway_link|trunk|trunk_link|primary|primary_link';
  final medium = 'secondary|secondary_link|tertiary|tertiary_link';
  final minor = 'residential|unclassified|living_street|service|pedestrian';
  final paths = 'footway|path|cycleway|steps|track|bridleway';

  buf.writeln('  way["highway"~"^($major)\$"]($b);');
  buf.writeln('  way["highway"~"^($medium)\$"]($b);');
  if (detail.includesMinorRoads) {
    buf.writeln('  way["highway"~"^($minor)\$"]($b);');
  }
  if (detail.includesPaths) {
    buf.writeln('  way["highway"~"^($paths)\$"]($b);');
  }
  buf.writeln('  way["railway"~"^(rail|light_rail|subway|tram|narrow_gauge|monorail)\$"]($b);');

  // Water -----------------------------------------------------------------
  buf.writeln('  way["natural"~"^(water|bay|strait)\$"]($b);');
  buf.writeln('  relation["natural"~"^(water|bay)\$"]($b);');
  buf.writeln('  way["waterway"~"^(riverbank|dock)\$"]($b);');
  buf.writeln('  way["landuse"~"^(reservoir|basin)\$"]($b);');
  buf.writeln('  way["natural"="coastline"]($b);');
  buf.writeln('  way["waterway"~"^(river|canal${detail == DetailLevel.wide ? '' : '|stream|ditch'})\$"]($b);');

  // Green & sand ----------------------------------------------------------
  buf.writeln('  way["leisure"~"^(park|garden|golf_course|nature_reserve|pitch|common|dog_park)\$"]($b);');
  buf.writeln('  relation["leisure"~"^(park|garden|nature_reserve)\$"]($b);');
  buf.writeln('  way["landuse"~"^(forest|grass|meadow|village_green|recreation_ground|cemetery|orchard|vineyard|allotments|farmland|greenfield)\$"]($b);');
  buf.writeln('  relation["landuse"~"^(forest|grass|meadow|recreation_ground|cemetery)\$"]($b);');
  buf.writeln('  way["natural"~"^(wood|scrub|grassland|heath|wetland)\$"]($b);');
  buf.writeln('  relation["natural"="wood"]($b);');
  buf.writeln('  way["natural"~"^(beach|sand|dune|shingle)\$"]($b);');

  // Buildings -------------------------------------------------------------
  if (detail.includesBuildings) {
    buf.writeln('  way["building"]($b);');
    buf.writeln('  relation["building"]($b);');
  }

  buf..writeln(');')..writeln('out geom;');
  return buf.toString();
}
