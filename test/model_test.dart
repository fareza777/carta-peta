import 'dart:ui';

import 'package:carta/core/geo.dart';
import 'package:carta/model/design.dart';
import 'package:carta/model/layer.dart';
import 'package:carta/model/map_style.dart';
import 'package:carta/model/place.dart';
import 'package:carta/model/poster_config.dart';
import 'package:carta/model/route_track.dart';
import 'package:carta/presets/format_presets.dart';
import 'package:carta/presets/style_presets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('style survives a JSON round trip', () {
    for (final preset in kStylePresets) {
      final copy = MapStyle.fromJson(preset.toJson());
      expect(copy.id, preset.id);
      expect(copy.background.toARGB32(), preset.background.toARGB32());
      expect(copy.backgroundEnd?.toARGB32(), preset.backgroundEnd?.toARGB32());
      expect(copy.layers.length, preset.layers.length);
      for (final id in LayerId.values) {
        expect(copy.layer(id).stroke.toARGB32(), preset.layer(id).stroke.toARGB32());
        expect(copy.layer(id).width, preset.layer(id).width);
        expect(copy.layer(id).dash, preset.layer(id).dash);
      }
    }
  });

  test('withLayer does not mutate the original style', () {
    final base = kStylePresets.first;
    final next = base.withLayer(
        LayerId.roadMajor, base.layer(LayerId.roadMajor).copyWith(width: 9));
    expect(next.layer(LayerId.roadMajor).width, 9);
    expect(base.layer(LayerId.roadMajor).width, isNot(9));
  });

  test('clearing the gradient really clears it', () {
    final withGradient = kStylePresets.first.copyWith(backgroundEnd: const Color(0xFF123456));
    expect(withGradient.backgroundEnd, isNotNull);
    expect(withGradient.copyWith(clearBackgroundEnd: true).backgroundEnd, isNull);
  });

  test('poster config survives a JSON round trip', () {
    final poster = PosterConfig(
      title: 'Jakarta',
      subtitle: 'Indonesia',
      custom: 'Where we met',
      showDate: true,
      date: DateTime(2024, 5, 6),
      titleFont: 'Cinzel',
      placement: TextPlacement.overlayBottom,
      frame: FrameStyle.doubleLine,
      shape: ShapeMask.arch,
      margin: 0.11,
      paperColor: const Color(0xFF102030),
    );
    final copy = PosterConfig.fromJson(poster.toJson());
    expect(copy.title, poster.title);
    expect(copy.custom, poster.custom);
    expect(copy.date, poster.date);
    expect(copy.placement, poster.placement);
    expect(copy.frame, poster.frame);
    expect(copy.shape, poster.shape);
    expect(copy.paperColor?.toARGB32(), poster.paperColor?.toARGB32());
  });

  test('clearing the paper colour really clears it', () {
    const poster = PosterConfig(paperColor: Color(0xFF102030));
    expect(poster.copyWith(clearPaperColor: true).paperColor, isNull);
  });

  test('design survives a JSON round trip including its route', () {
    final design = Design(
      id: 'd1',
      place: const PlaceRef(
          name: 'Bandung',
          context: 'West Java',
          country: 'Indonesia',
          centre: LatLng(-6.9175, 107.6191)),
      radiusMetres: 2400,
      style: kStylePresets[3],
      poster: const PosterConfig(title: 'Bandung'),
      formatId: kFormats[2].id,
      route: RouteTrack(
        name: 'Ride',
        points: const [LatLng(-6.91, 107.61), LatLng(-6.92, 107.62)],
        distanceMetres: 1500,
        ascentMetres: 40,
        duration: const Duration(minutes: 12),
      ),
      createdAt: DateTime(2024, 1, 1),
      updatedAt: DateTime(2024, 1, 2),
    );

    final copy = Design.fromJson(design.toJson());
    expect(copy.id, design.id);
    expect(copy.place.name, 'Bandung');
    expect(copy.radiusMetres, 2400);
    expect(copy.formatId, kFormats[2].id);
    expect(copy.style.id, design.style.id);
    expect(copy.route!.points.length, 2);
    expect(copy.route!.duration, const Duration(minutes: 12));
    expect(copy.createdAt, design.createdAt);
  });

  test('format specs compute matching heights', () {
    for (final f in kFormats) {
      for (final w in f.exportWidths) {
        final h = f.heightFor(w);
        expect(h, greaterThan(0));
        expect(w / h, closeTo(f.aspect, 0.01));
      }
    }
  });

  test('at least one export per format reaches 4K', () {
    for (final f in kFormats) {
      final w = f.exportWidths.last;
      final long = w > f.heightFor(w) ? w : f.heightFor(w);
      expect(long, greaterThanOrEqualTo(3840), reason: '${f.name} tops out too low');
    }
  });

  test('route bounds and radius cover the track', () {
    const route = RouteTrack(
      name: 'r',
      points: [LatLng(-6.90, 107.60), LatLng(-6.95, 107.66)],
      distanceMetres: 0,
    );
    final b = route.bounds;
    expect(b.south, -6.95);
    expect(b.north, -6.90);
    final diagonal = haversineMetres(
        LatLng(b.south, b.west), LatLng(b.north, b.east));
    expect(route.suggestedRadius * 2, greaterThan(diagonal * 0.6));
  });
}
