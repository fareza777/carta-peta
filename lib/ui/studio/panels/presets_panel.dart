import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format.dart';
import '../../../core/theme.dart';
import '../../../data/osm/overpass_query.dart';
import '../../../model/map_data.dart';
import '../../../model/poster_config.dart';
import '../../../presets/format_presets.dart';
import '../../../presets/style_presets.dart';
import '../../../render/exporter.dart';
import '../../../render/path_cache.dart';
import '../../../render/poster_renderer.dart';
import '../../../state/studio_controller.dart';
import '../../widgets/common.dart';

const _radiusSteps = <double>[
  400, 600, 800, 1000, 1250, 1600, 2000, 2600, 3200, 4000, 5000, 6500, 8000, 10000, 13000
];

const double _thumbWidth = 68;
const double _thumbHeight = 96;

class PresetsPanel extends ConsumerStatefulWidget {
  const PresetsPanel({super.key});

  @override
  ConsumerState<PresetsPanel> createState() => _PresetsPanelState();
}

class _PresetsPanelState extends ConsumerState<PresetsPanel> {
  /// Preset previews are rasterised once per capture instead of being live
  /// `CustomPaint`s. Eighteen live painters repainting on every slider tick was
  /// the most obvious jank risk in the studio.
  MapDataSet? _source;
  final Map<String, ui.Image> _thumbs = {};
  bool _building = false;

  @override
  void dispose() {
    _disposeThumbs();
    super.dispose();
  }

  void _disposeThumbs() {
    for (final image in _thumbs.values) {
      image.dispose();
    }
    _thumbs.clear();
  }

  void _ensureThumbs(MapDataSet? data) {
    if (data == null || identical(data, _source)) return;
    _source = data;
    _disposeThumbs();
    _buildThumbs(data);
  }

  Future<void> _buildThumbs(MapDataSet data) async {
    if (_building) return;
    _building = true;
    try {
      final cache = MapPathCache(data.decimated(step: 4));
      final ratio = MediaQuery.of(context).devicePixelRatio.clamp(1.0, 3.0);
      final w = (_thumbWidth * ratio).round();
      final h = (_thumbHeight * ratio).round();
      for (final preset in kStylePresets) {
        if (!mounted || !identical(_source, data)) return;
        final scene = PosterScene(
          paths: cache,
          style: preset,
          poster: const PosterConfig(enabled: false, shape: ShapeMask.fill, margin: 0),
          format: kFormats.first,
          showAttribution: false,
        );
        final image = await PosterExporter.renderImage(scene, w, h);
        if (!mounted || !identical(_source, data)) {
          image.dispose();
          return;
        }
        setState(() => _thumbs[preset.id] = image);
      }
    } catch (_) {
      // A failed thumbnail just falls back to a flat colour swatch.
    } finally {
      _building = false;
    }
  }

  int _radiusIndex(double metres) {
    var best = 0;
    var bestDelta = double.infinity;
    for (var i = 0; i < _radiusSteps.length; i++) {
      final d = (_radiusSteps[i] - metres).abs();
      if (d < bestDelta) {
        bestDelta = d;
        best = i;
      }
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(studioControllerProvider);
    final controller = ref.read(studioControllerProvider.notifier);
    _ensureThumbs(state.paths?.data);
    final index = _radiusIndex(state.radiusMetres);

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        const SectionLabel('Looks'),
        SizedBox(
          height: 132,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            itemCount: kStylePresets.length,
            separatorBuilder: (_, __) => const SizedBox(width: 11),
            itemBuilder: (context, i) {
              final preset = kStylePresets[i];
              final active = preset.id == state.style.id;
              final thumb = _thumbs[preset.id];
              return GestureDetector(
                onTap: () => controller.applyPreset(preset),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(
                          color: active ? Shade.accent : Shade.line,
                          width: active ? 2 : 1,
                        ),
                      ),
                      padding: const EdgeInsets.all(2),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: SizedBox(
                          width: _thumbWidth,
                          height: _thumbHeight,
                          child: thumb == null
                              ? ColoredBox(color: preset.background)
                              : RawImage(image: thumb, fit: BoxFit.cover),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      width: 72,
                      child: Text(
                        preset.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: active ? Shade.text : Shade.textFaint,
                          fontSize: 11.5,
                          fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        const SectionLabel('Area'),
        LabeledSlider(
          label: 'How much of the map to show',
          value: index.toDouble(),
          min: 0,
          max: (_radiusSteps.length - 1).toDouble(),
          divisions: _radiusSteps.length - 1,
          valueLabel: formatRadius(_radiusSteps[index]),
          onChanged: (v) => controller.setRadius(_radiusSteps[v.round()]),
          onChangeEnd: (_) => controller.commitRadius(),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
          child: Row(
            children: [
              const Icon(Icons.auto_awesome_outlined, size: 14, color: Shade.textFaint),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  _detailNote(state.detail),
                  style: const TextStyle(color: Shade.textFaint, fontSize: 11.5, height: 1.4),
                ),
              ),
            ],
          ),
        ),
        const SectionLabel('Terrain'),
        ToggleRow(
          label: 'Contour lines',
          subtitle: _contourNote(state),
          value: state.style.contourInterval > 0,
          onChanged: controller.setContours,
        ),
        ToggleRow(
          label: 'Hillshade relief',
          subtitle: 'Shades slopes using the elevation already downloaded',
          value: state.style.reliefStrength > 0.01,
          onChanged: controller.setRelief,
        ),
        if (state.style.reliefStrength > 0.01)
          LabeledSlider(
            label: 'Relief strength',
            value: state.style.reliefStrength,
            min: 0.05,
            max: 1,
            valueLabel: '${(state.style.reliefStrength * 100).round()}%',
            onChanged: (v) => controller.updateStyle(
                state.style.copyWith(reliefStrength: v),
                kind: 'relief'),
          ),
        const SectionLabel('Thickness'),
        LabeledSlider(
          label: 'Road weight',
          value: state.style.lineScale,
          min: 0.3,
          max: 2.6,
          valueLabel: '${(state.style.lineScale * 100).round()}%',
          onChanged: controller.setLineScale,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
          child: Row(
            children: [
              Expanded(
                child: GhostButton(
                  label: 'Refresh data',
                  icon: Icons.refresh,
                  onPressed: () => controller.reload(force: true),
                ),
              ),
              if (state.route != null) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: GhostButton(
                    label: 'Remove route',
                    icon: Icons.close,
                    onPressed: controller.detachRoute,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  String _contourNote(StudioState state) => switch (state.contourStatus) {
        ContourStatus.loading => 'Reading elevation data...',
        ContourStatus.ready => 'Traced from public-domain elevation tiles',
        ContourStatus.unavailable =>
          state.contourMessage ?? 'No usable elevation data here',
        ContourStatus.off => 'Adds real terrain relief, downloaded once per place',
      };

  String _detailNote(DetailLevel detail) => switch (detail) {
        DetailLevel.full => 'Full detail: buildings, paths and every street.',
        DetailLevel.high => 'High detail: buildings and streets, lighter paths.',
        DetailLevel.medium => 'Balanced: buildings are dropped so wide areas stay crisp.',
        DetailLevel.wide => 'Wide area: main roads, water and green only.',
      };
}
