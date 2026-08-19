import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../model/poster_config.dart';
import '../../../state/studio_controller.dart';
import '../../widgets/color_picker.dart';
import '../../widgets/common.dart';

class FramePanel extends ConsumerWidget {
  const FramePanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(studioControllerProvider);
    final controller = ref.read(studioControllerProvider.notifier);
    final poster = state.poster;

    return ListView(
      padding: const EdgeInsets.only(bottom: 28),
      children: [
        const SectionLabel('Map shape'),
        ChoiceStrip<ShapeMask>(
          items: ShapeMask.values,
          selected: poster.shape,
          labelOf: (s) => switch (s) {
            ShapeMask.fill => 'Full bleed',
            ShapeMask.rectangle => 'Rectangle',
            ShapeMask.circle => 'Circle',
            ShapeMask.rounded => 'Rounded',
            ShapeMask.arch => 'Arch',
          },
          onSelect: (s) => controller.updatePoster(poster.copyWith(shape: s)),
        ),
        const SectionLabel('Border'),
        ChoiceStrip<FrameStyle>(
          items: FrameStyle.values,
          selected: poster.frame,
          labelOf: (f) => switch (f) {
            FrameStyle.none => 'None',
            FrameStyle.hairline => 'Hairline',
            FrameStyle.doubleLine => 'Double',
            FrameStyle.inset => 'Inset',
            FrameStyle.plate => 'Plate',
          },
          onSelect: (f) => controller.updatePoster(poster.copyWith(frame: f)),
        ),
        const SectionLabel('Margins'),
        LabeledSlider(
          label: 'Outer margin',
          value: poster.margin,
          min: 0,
          max: 0.18,
          valueLabel: '${(poster.margin * 100).toStringAsFixed(1)}%',
          onChanged: (v) => controller.updatePoster(poster.copyWith(margin: v)),
        ),
        _paperRow(context, ref, state, controller),
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Text(
            'Full bleed ignores margins and prints the map edge to edge — the best '
            'choice for phone wallpapers.',
            style: TextStyle(color: Shade.textFaint, fontSize: 11.5, height: 1.4),
          ),
        ),
      ],
    );
  }

  Widget _paperRow(BuildContext context, WidgetRef ref, StudioState state,
      StudioController controller) {
    final poster = state.poster;
    final custom = poster.paperColor != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 16, 4),
      child: Row(
        children: [
          GestureDetector(
            onTap: () async {
              final picked = await showColorPicker(
                context,
                initial: poster.paperColor ?? state.style.background,
                title: 'Paper colour',
              );
              if (picked != null) {
                controller.updatePoster(poster.copyWith(paperColor: picked));
              }
            },
            child: Opacity(
              opacity: custom ? 1 : 0.4,
              child: ColorDot(
                color: poster.paperColor ?? state.style.background,
                size: 28,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              custom ? 'Custom paper colour' : 'Paper follows the map background',
              style: TextStyle(
                  color: custom ? Shade.text : Shade.textFaint, fontSize: 14),
            ),
          ),
          Transform.scale(
            scale: 0.8,
            child: Switch(
              value: custom,
              onChanged: (v) => controller.updatePoster(v
                  ? poster.copyWith(paperColor: state.style.background)
                  : poster.copyWith(clearPaperColor: true)),
            ),
          ),
        ],
      ),
    );
  }
}
