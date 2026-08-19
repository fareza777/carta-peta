import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../model/poster_config.dart';
import '../../../presets/font_presets.dart';
import '../../../state/studio_controller.dart';
import '../../widgets/common.dart';

class TextPanel extends ConsumerStatefulWidget {
  const TextPanel({super.key});

  @override
  ConsumerState<TextPanel> createState() => _TextPanelState();
}

class _TextPanelState extends ConsumerState<TextPanel> {
  final _title = TextEditingController();
  final _subtitle = TextEditingController();
  final _custom = TextEditingController();
  final _titleFocus = FocusNode();
  final _subtitleFocus = FocusNode();
  final _customFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _adopt(ref.read(studioControllerProvider).poster);
  }

  /// Pull the text fields back in line with the studio, e.g. after opening a
  /// saved design. Never called during build, so the controllers can notify
  /// their fields safely.
  void _adopt(PosterConfig poster) {
    _title.text = poster.title;
    _subtitle.text = poster.subtitle;
    _custom.text = poster.custom;
  }

  @override
  void dispose() {
    _title.dispose();
    _subtitle.dispose();
    _custom.dispose();
    _titleFocus.dispose();
    _subtitleFocus.dispose();
    _customFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<StudioState>(studioControllerProvider, (previous, next) {
      if (previous?.designId != next.designId) _adopt(next.poster);
    });

    final state = ref.watch(studioControllerProvider);
    final controller = ref.read(studioControllerProvider.notifier);
    final poster = state.poster;

    return ListView(
      padding: const EdgeInsets.only(bottom: 30),
      children: [
        ToggleRow(
          label: 'Show poster text',
          value: poster.enabled,
          onChanged: (v) => controller.updatePoster(poster.copyWith(enabled: v)),
        ),
        const SectionLabel('Words'),
        _field(
          controller: _title,
          focus: _titleFocus,
          hint: state.place?.name ?? 'Title',
          label: 'Title',
          onChanged: (v) => controller.updatePoster(poster.copyWith(title: v)),
        ),
        _field(
          controller: _subtitle,
          focus: _subtitleFocus,
          hint: state.place?.context ?? 'Region, country',
          label: 'Subtitle',
          onChanged: (v) => controller.updatePoster(poster.copyWith(subtitle: v)),
        ),
        _field(
          controller: _custom,
          focus: _customFocus,
          hint: 'Anniversary, dedication, anything',
          label: 'Custom line',
          onChanged: (v) => controller.updatePoster(poster.copyWith(custom: v)),
        ),
        const SectionLabel('Map labels'),
        ToggleRow(
          label: 'Show street & area names',
          subtitle: 'Only names that fit are drawn; overlapping ones are dropped',
          value: state.style.showLabels,
          onChanged: (v) => controller.updateStyle(
              state.style.copyWith(showLabels: v),
              kind: 'labels'),
        ),
        if (state.style.showLabels)
          LabeledSlider(
            label: 'Label size',
            value: state.style.labelScale,
            min: 0.5,
            max: 2,
            valueLabel: '${(state.style.labelScale * 100).round()}%',
            onChanged: (v) => controller.updateStyle(
                state.style.copyWith(labelScale: v),
                kind: 'labelSize'),
          ),
        const SectionLabel('Typeface'),
        _FontStrip(
          selected: poster.titleFont,
          caption: 'Title',
          onSelect: (f) => controller.updatePoster(poster.copyWith(titleFont: f)),
        ),
        const SizedBox(height: 10),
        _FontStrip(
          selected: poster.bodyFont,
          caption: 'Body',
          onSelect: (f) => controller.updatePoster(poster.copyWith(bodyFont: f)),
        ),
        const SectionLabel('Fine tuning'),
        LabeledSlider(
          label: 'Text size',
          value: poster.titleScale,
          min: 0.6,
          max: 1.7,
          valueLabel: '${(poster.titleScale * 100).round()}%',
          onChanged: (v) => controller.updatePoster(poster.copyWith(titleScale: v)),
        ),
        LabeledSlider(
          label: 'Letter spacing',
          value: poster.letterSpacing,
          min: 0,
          max: 1.4,
          valueLabel: poster.letterSpacing.toStringAsFixed(2),
          onChanged: (v) => controller.updatePoster(poster.copyWith(letterSpacing: v)),
        ),
        const SectionLabel('Placement'),
        ChoiceStrip<TextPlacement>(
          items: const [
            TextPlacement.below,
            TextPlacement.overlayBottom,
            TextPlacement.overlayTop,
            TextPlacement.none,
          ],
          selected: poster.placement,
          labelOf: (p) => switch (p) {
            TextPlacement.below => 'Below map',
            TextPlacement.overlayBottom => 'Over bottom',
            TextPlacement.overlayTop => 'Over top',
            TextPlacement.none => 'Hidden',
          },
          onSelect: (p) => controller.updatePoster(poster.copyWith(placement: p)),
        ),
        const SizedBox(height: 10),
        ChoiceStrip<PosterAlign>(
          items: PosterAlign.values,
          selected: poster.align,
          labelOf: (a) => switch (a) {
            PosterAlign.left => 'Align left',
            PosterAlign.center => 'Centred',
            PosterAlign.right => 'Align right',
          },
          onSelect: (a) => controller.updatePoster(poster.copyWith(align: a)),
        ),
        const SizedBox(height: 6),
        ToggleRow(
          label: 'Uppercase title',
          value: poster.uppercaseTitle,
          onChanged: (v) => controller.updatePoster(poster.copyWith(uppercaseTitle: v)),
        ),
        ToggleRow(
          label: 'Divider rule',
          value: poster.divider,
          onChanged: (v) => controller.updatePoster(poster.copyWith(divider: v)),
        ),
        ToggleRow(
          label: 'Coordinates',
          subtitle: poster.coordinatesAsDms ? 'Degrees, minutes, seconds' : 'Decimal degrees',
          value: poster.showCoordinates,
          onChanged: (v) => controller.updatePoster(poster.copyWith(showCoordinates: v)),
        ),
        if (poster.showCoordinates)
          ToggleRow(
            label: 'Use DMS format',
            value: poster.coordinatesAsDms,
            onChanged: (v) =>
                controller.updatePoster(poster.copyWith(coordinatesAsDms: v)),
          ),
        ToggleRow(
          label: 'Date',
          value: poster.showDate,
          onChanged: (v) => controller.updatePoster(
              poster.copyWith(showDate: v, date: poster.date ?? DateTime.now())),
        ),
      ],
    );
  }

  Widget _field({
    required TextEditingController controller,
    required FocusNode focus,
    required String hint,
    required String label,
    required ValueChanged<String> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Shade.textFaint, fontSize: 11.5)),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            focusNode: focus,
            onChanged: onChanged,
            textCapitalization: TextCapitalization.words,
            style: const TextStyle(color: Shade.text, fontSize: 14.5),
            decoration: InputDecoration(
              hintText: hint,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _FontStrip extends StatelessWidget {
  const _FontStrip({
    required this.selected,
    required this.onSelect,
    required this.caption,
  });

  final String selected;
  final String caption;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 60,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        itemCount: kFonts.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final font = kFonts[i];
          final active = font.family == selected;
          return GestureDetector(
            onTap: () => onSelect(font.family),
            child: Container(
              width: 78,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                color: active ? Shade.surfaceHi : Shade.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: active ? Shade.accent : Shade.line),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Aa',
                    style: TextStyle(
                      fontFamily: font.family,
                      fontSize: 20,
                      color: active ? Shade.text : Shade.textDim,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${font.label} · $caption',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Shade.textFaint, fontSize: 9.5),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
