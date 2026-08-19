import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../model/layer.dart';
import '../../../model/map_style.dart';
import '../../../state/studio_controller.dart';
import '../../widgets/color_picker.dart';
import '../../widgets/common.dart';

/// Roads first: that is what people reach for most.
final _order = LayerId.values.reversed.toList();

class LayersPanel extends ConsumerStatefulWidget {
  const LayersPanel({super.key});

  @override
  ConsumerState<LayersPanel> createState() => _LayersPanelState();
}

class _LayersPanelState extends ConsumerState<LayersPanel> {
  LayerId? _expanded;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(studioControllerProvider);
    final controller = ref.read(studioControllerProvider.notifier);
    final counts = state.paths?.data.layerCounts ?? const <LayerId, int>{};

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 26),
      children: [
        for (final id in _order)
          _LayerCard(
            id: id,
            style: state.style.layer(id),
            count: counts[id] ?? 0,
            expanded: _expanded == id,
            onExpand: () => setState(() => _expanded = _expanded == id ? null : id),
            onChanged: (s) => controller.updateLayer(id, s),
          ),
        const SizedBox(height: 8),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 6),
          child: Text(
            'Layers with no data at this location are dimmed. Widen the area or move '
            'the map to bring them in.',
            style: TextStyle(color: Shade.textFaint, fontSize: 11.5, height: 1.4),
          ),
        ),
      ],
    );
  }
}

class _LayerCard extends StatelessWidget {
  const _LayerCard({
    required this.id,
    required this.style,
    required this.count,
    required this.expanded,
    required this.onExpand,
    required this.onChanged,
  });

  final LayerId id;
  final LayerStyle style;
  final int count;
  final bool expanded;
  final VoidCallback onExpand;
  final ValueChanged<LayerStyle> onChanged;

  @override
  Widget build(BuildContext context) {
    final present = count > 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Shade.surface,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: expanded ? Shade.line : Colors.transparent),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: onExpand,
            borderRadius: BorderRadius.circular(13),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 11, 8, 11),
              child: Row(
                children: [
                  Opacity(
                    opacity: present ? 1 : 0.4,
                    child: ColorDot(
                      color: id.isArea && style.filled ? style.fill : style.stroke,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      id.label,
                      style: TextStyle(
                        color: present ? Shade.text : Shade.textFaint,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Transform.scale(
                    scale: 0.72,
                    child: Switch(
                      value: style.enabled,
                      onChanged: (v) => onChanged(style.copyWith(enabled: v)),
                    ),
                  ),
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    size: 19,
                    color: Shade.textFaint,
                  ),
                  const SizedBox(width: 4),
                ],
              ),
            ),
          ),
          if (expanded) _details(context),
        ],
      ),
    );
  }

  Widget _details(BuildContext context) {
    Future<void> pick(String title, Color current, ValueChanged<Color> apply) async {
      final picked = await showColorPicker(context, initial: current, title: title);
      if (picked != null) apply(picked);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
          const Divider(height: 1, indent: 14, endIndent: 14),
          const SizedBox(height: 6),
          if (id.isArea)
            _swatchRow(
              'Fill',
              style.fill,
              style.filled,
              (v) => onChanged(style.copyWith(filled: v)),
              () => pick('${id.label} fill', style.fill, (c) => onChanged(style.copyWith(fill: c))),
            ),
          _swatchRow(
            id.isArea ? 'Outline' : 'Colour',
            style.stroke,
            style.outlined,
            (v) => onChanged(style.copyWith(outlined: v)),
            () => pick('${id.label} line', style.stroke,
                (c) => onChanged(style.copyWith(stroke: c))),
          ),
          if (style.outlined && id.isRoad)
            _swatchRow(
              'Casing',
              style.casing ?? style.stroke,
              style.casing != null,
              (v) => onChanged(v
                  ? style.copyWith(casing: style.casing ?? const Color(0xFF000000))
                  : style.copyWith(clearCasing: true)),
              () => pick('${id.label} casing', style.casing ?? style.stroke,
                  (c) => onChanged(style.copyWith(casing: c))),
            ),
          if (style.outlined && id.isRoad && style.casing != null)
            LabeledSlider(
              label: 'Casing width',
              value: style.casingWidth,
              min: 0.1,
              max: 2.5,
              valueLabel: style.casingWidth.toStringAsFixed(2),
              onChanged: (v) => onChanged(style.copyWith(casingWidth: v)),
            ),
          if (style.outlined)
            LabeledSlider(
              label: 'Line weight',
              value: style.width,
              min: 0.1,
              max: 8,
              valueLabel: style.width.toStringAsFixed(2),
              onChanged: (v) => onChanged(style.copyWith(width: v)),
            ),
          LabeledSlider(
            label: 'Opacity',
            value: style.opacity,
            min: 0.05,
            max: 1,
            valueLabel: '${(style.opacity * 100).round()}%',
            onChanged: (v) => onChanged(style.copyWith(opacity: v)),
          ),
          if (!id.isArea)
            LabeledSlider(
              label: 'Glow',
              value: style.glow,
              min: 0,
              max: 1,
              valueLabel: '${(style.glow * 100).round()}%',
              onChanged: (v) => onChanged(style.copyWith(glow: v)),
            ),
          if (!id.isArea)
            ToggleRow(
              label: 'Dashed',
              value: style.dash != null,
              onChanged: (v) => onChanged(v
                  ? style.copyWith(dash: const [4, 3])
                  : style.copyWith(clearDash: true)),
            ),
        ],
      ),
    );
  }

  Widget _swatchRow(
    String label,
    Color color,
    bool on,
    ValueChanged<bool> toggle,
    VoidCallback tap,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 12, 6),
      child: Row(
        children: [
          GestureDetector(onTap: tap, child: ColorDot(color: color, size: 24)),
          const SizedBox(width: 12),
          Expanded(
            child: GestureDetector(
              onTap: tap,
              behavior: HitTestBehavior.opaque,
              child: Text(label,
                  style: const TextStyle(color: Shade.textDim, fontSize: 13.5)),
            ),
          ),
          Transform.scale(
            scale: 0.7,
            child: Switch(value: on, onChanged: toggle),
          ),
        ],
      ),
    );
  }
}
