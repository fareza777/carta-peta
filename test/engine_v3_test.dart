import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:carta/core/geo.dart';
import 'package:carta/model/layer.dart';
import 'package:carta/model/map_data.dart';
import 'package:carta/model/map_style.dart';
import 'package:carta/model/poster_config.dart';
import 'package:carta/presets/demo_map.dart';
import 'package:carta/presets/format_presets.dart';
import 'package:carta/presets/style_presets.dart';
import 'package:carta/render/exporter.dart';
import 'package:carta/render/path_cache.dart';
import 'package:carta/render/poster_renderer.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

const _window = MapWindow(0.5, 0.5, 7.5e-5);

MapDataSet _data(List<MapFeature> features) => MapDataSet(
      window: _window,
      bbox: const BBox(-0.001, -0.001, 0.001, 0.001),
      capturedAt: DateTime(2024),
      features: features,
    );

Float32List _xy(List<double> v) => Float32List.fromList(v);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('colour grade', () {
    test('an untouched grade is identity and skips the layer', () {
      expect(ColorGrade.none.isIdentity, isTrue);
      expect(const ColorGrade(contrast: 1.4).isIdentity, isFalse);
      expect(const ColorGrade(duoAmount: 1).isIdentity, isTrue,
          reason: 'duotone without colours does nothing');
    });

    test('contrast pivots around mid grey', () {
      final m = const ColorGrade(contrast: 2).matrix();
      // out = 2*in + (0.5 - 1)*255  =>  mid grey stays mid grey
      expect(m[0], closeTo(2, 1e-9));
      expect(m[4], closeTo(-127.5, 1e-6));
      final mid = 127.5 * m[0] + m[4];
      expect(mid, closeTo(127.5, 1e-6));
    });

    test('full duotone maps black and white onto the chosen ramp', () {
      const shadow = Color(0xFF102040);
      const highlight = Color(0xFFF0C060);
      final m = const ColorGrade(
        duoShadow: shadow,
        duoHighlight: highlight,
        duoAmount: 1,
      ).matrix();

      double channel(int row, double r, double g, double b) =>
          m[row * 5] * r + m[row * 5 + 1] * g + m[row * 5 + 2] * b + m[row * 5 + 4];

      // Pure black takes the shadow colour.
      expect(channel(0, 0, 0, 0), closeTo(0x10, 0.6));
      expect(channel(2, 0, 0, 0), closeTo(0x40, 0.6));
      // Pure white takes the highlight colour.
      expect(channel(0, 255, 255, 255), closeTo(0xF0, 0.6));
      expect(channel(1, 255, 255, 255), closeTo(0xC0, 0.6));
    });

    test('grading survives a style JSON round trip', () {
      final style = kStylePresets.first.copyWith(
        grade: const ColorGrade(
          contrast: 1.3,
          saturation: 0.4,
          warmth: -0.5,
          duoShadow: Color(0xFF001122),
          duoHighlight: Color(0xFFFFEECC),
          duoAmount: 0.7,
        ),
      );
      final copy = MapStyle.fromJson(style.toJson());
      expect(copy.grade.contrast, 1.3);
      expect(copy.grade.saturation, 0.4);
      expect(copy.grade.warmth, -0.5);
      expect(copy.grade.duoAmount, 0.7);
      expect(copy.grade.duoShadow?.toARGB32(), 0xFF001122);
    });

    test('a duotone grade actually changes the rendered pixels', () async {
      final data = _data([
        MapFeature(LayerId.roadMajor, false, [_xy([0.0, 0.5, 1.0, 0.5])]),
      ]);
      final base = kStylePresets.firstWhere((s) => s.id == 'oled');
      final graded = base.copyWith(
        grade: const ColorGrade(
          duoShadow: Color(0xFF200040),
          duoHighlight: Color(0xFFFFCC00),
          duoAmount: 1,
        ),
      );

      Future<int> corner(MapStyle style) async {
        final image = await PosterExporter.renderImage(
          PosterScene(
            paths: MapPathCache(data),
            style: style,
            poster: const PosterConfig(
                enabled: false, shape: ShapeMask.fill, margin: 0),
            format: kFormats.first,
            showAttribution: false,
          ),
          120,
          180,
        );
        final px = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
        image.dispose();
        return (px.getUint8(0) << 16) | (px.getUint8(1) << 8) | px.getUint8(2);
      }

      expect(await corner(base), 0x000000);
      // Black background lands on the shadow tone.
      final tinted = await corner(graded);
      expect(tinted, isNot(0x000000));
      expect((tinted >> 16) & 0xFF, closeTo(0x20, 6));
    });
  });

  group('map picture cache', () {
    PosterScene scene(MapPathCache cache, MapStyle style, PosterConfig poster) =>
        PosterScene(
          paths: cache,
          style: style,
          poster: poster,
          format: kFormats.first,
          showAttribution: false,
        );

    test('editing poster text reuses the recorded map, changing style does not',
        () async {
      final cache = MapPathCache(_data([
        MapFeature(LayerId.roadMajor, false, [_xy([0.0, 0.5, 1.0, 0.5])]),
      ]));
      final style = kStylePresets.first;

      (await PosterExporter.renderImage(
              scene(cache, style, const PosterConfig(title: 'A')), 200, 300))
          .dispose();
      final firstKey = cache.mapCacheKey;
      expect(firstKey, isNotNull);

      // Same style object, different words: the geometry must not be redrawn.
      (await PosterExporter.renderImage(
              scene(cache, style, const PosterConfig(title: 'AB')), 200, 300))
          .dispose();
      expect(cache.mapCacheKey, firstKey);
      expect(cache.cachedMap(firstKey!), isNotNull);

      // A restyle produces a new style instance and must invalidate.
      (await PosterExporter.renderImage(
              scene(cache, style.copyWith(lineScale: 2),
                  const PosterConfig(title: 'AB')),
              200,
              300))
          .dispose();
      expect(cache.mapCacheKey, isNot(firstKey));
    });

    test('disposing the cache is safe to call twice', () {
      final cache = MapPathCache(_data(const []));
      cache.dispose();
      cache.dispose();
      expect(cache.hasAnything, isFalse);
    });
  });

  group('map labels', () {
    test('the longest instance of a repeated name wins', () {
      final cache = MapPathCache(_data([
        MapFeature(LayerId.roadMajor, false, [_xy([0.1, 0.5, 0.2, 0.5])],
            name: 'Long Road'),
        MapFeature(LayerId.roadMajor, false, [_xy([0.1, 0.6, 0.9, 0.6])],
            name: 'Long Road'),
      ]));
      expect(cache.labels.length, 1);
      expect(cache.labels.single.span, closeTo(0.8, 1e-6));
    });

    test('a road label follows the direction of its longest segment', () {
      final cache = MapPathCache(_data([
        MapFeature(LayerId.roadMedium, false, [_xy([0.2, 0.2, 0.8, 0.8])],
            name: 'Diagonal'),
      ]));
      final label = cache.labels.single;
      expect(label.area, isFalse);
      expect(label.angle, closeTo(0.785, 0.02));
      expect(label.x, closeTo(0.5, 1e-6));
    });

    test('an area label sits at the centre of its ring', () {
      final cache = MapPathCache(_data([
        MapFeature(LayerId.green, true, [
          _xy([0.2, 0.2, 0.6, 0.2, 0.6, 0.6, 0.2, 0.6, 0.2, 0.2])
        ], name: 'Park'),
      ]));
      final label = cache.labels.single;
      expect(label.area, isTrue);
      expect(label.angle, 0);
      expect(label.x, closeTo(0.4, 0.02));
      expect(label.y, closeTo(0.4, 0.02));
    });

    test('names survive the cache codec', () {
      final data = _data([
        MapFeature(LayerId.roadMajor, false, [_xy([0.0, 0.5, 1.0, 0.5])],
            name: 'Jalan Jenderal Sudirman'),
        MapFeature(LayerId.roadMinor, false, [_xy([0.0, 0.2, 1.0, 0.2])]),
      ]);
      final copy = MapDataCodec.decode(MapDataCodec.encode(data))!;
      expect(copy.features.first.name, 'Jalan Jenderal Sudirman');
      expect(copy.features.last.name, isNull);
    });

    test('labels only draw when the style asks for them', () async {
      final data = _data([
        MapFeature(LayerId.roadMajor, false, [_xy([0.0, 0.5, 1.0, 0.5])],
            name: 'Avenue'),
      ]);
      final style = kStylePresets.firstWhere((s) => s.id == 'oled');
      for (final show in [false, true]) {
        final image = await PosterExporter.renderImage(
          PosterScene(
            paths: MapPathCache(data),
            style: style.copyWith(showLabels: show),
            poster: const PosterConfig(
                enabled: false, shape: ShapeMask.fill, margin: 0),
            format: kFormats.first,
            showAttribution: false,
          ),
          300,
          450,
        );
        expect(image.width, 300);
        image.dispose();
      }
    });
  });

  group('demo map', () {
    test('has every layer the onboarding pages show off', () {
      final demo = buildDemoMap();
      final counts = demo.layerCounts;
      expect(counts[LayerId.roadMajor], greaterThan(3));
      expect(counts[LayerId.roadMedium], greaterThan(3));
      expect(counts[LayerId.building], greaterThan(50));
      expect(counts[LayerId.water], greaterThan(0));
      expect(counts[LayerId.green], greaterThan(0));
      expect(counts[LayerId.contour], greaterThan(3));
      expect(demo.hasContours, isTrue);
      expect(demo.tallestBuilding, greaterThan(20));
    });

    test('is deterministic, so onboarding looks the same every launch', () {
      expect(buildDemoMap().pointCount, buildDemoMap().pointCount);
    });

    test('includes a bridge so the band ordering is visible', () {
      expect(
        buildDemoMap().features.any((f) => f.band == RoadBand.bridge),
        isTrue,
      );
    });

    test('renders in every preset without throwing', () async {
      final cache = MapPathCache(buildDemoMap());
      for (final preset in kStylePresets) {
        final image = await PosterExporter.renderImage(
          PosterScene(
            paths: cache,
            style: preset,
            poster: const PosterConfig(enabled: false),
            format: kFormats.first,
            showAttribution: false,
          ),
          70,
          105,
        );
        expect(image.width, 70);
        image.dispose();
      }
    });
  });
}
