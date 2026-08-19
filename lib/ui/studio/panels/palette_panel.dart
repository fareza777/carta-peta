import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../model/map_style.dart';
import '../../../state/studio_controller.dart';
import '../../widgets/color_picker.dart';
import '../../widgets/common.dart';

class PalettePanel extends ConsumerWidget {
  const PalettePanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(studioControllerProvider);
    final controller = ref.read(studioControllerProvider.notifier);
    final style = state.style;

    Future<void> pick(String title, Color current, ValueChanged<Color> apply) async {
      final picked = await showColorPicker(context, initial: current, title: title);
      if (picked != null) apply(picked);
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        const SectionLabel('Base colours'),
        _ColorRow(
          label: 'Background',
          color: style.background,
          onTap: () => pick('Background', style.background,
              (c) => controller.updateStyle(style.copyWith(background: c))),
        ),
        _ColorRow(
          label: 'Gradient tint',
          color: style.backgroundEnd ?? style.background,
          enabled: style.backgroundEnd != null,
          onToggle: (on) => controller.updateStyle(on
              ? style.copyWith(backgroundEnd: _shift(style.background))
              : style.copyWith(clearBackgroundEnd: true)),
          onTap: style.backgroundEnd == null
              ? null
              : () => pick('Gradient tint', style.backgroundEnd!,
                  (c) => controller.updateStyle(style.copyWith(backgroundEnd: c))),
        ),
        _ColorRow(
          label: 'Text',
          color: style.textColor,
          onTap: () => pick('Text', style.textColor,
              (c) => controller.updateStyle(style.copyWith(textColor: c))),
        ),
        _ColorRow(
          label: 'Accent & captions',
          color: style.accentColor,
          onTap: () => pick('Accent', style.accentColor,
              (c) => controller.updateStyle(style.copyWith(accentColor: c))),
        ),
        const SectionLabel('Finish'),
        LabeledSlider(
          label: 'Paper grain',
          value: style.grain,
          min: 0,
          max: 1,
          valueLabel: '${(style.grain * 100).round()}%',
          onChanged: (v) => controller.updateStyle(style.copyWith(grain: v)),
        ),
        LabeledSlider(
          label: 'Vignette',
          value: style.vignette,
          min: 0,
          max: 0.8,
          valueLabel: '${(style.vignette * 125).round()}%',
          onChanged: (v) => controller.updateStyle(style.copyWith(vignette: v)),
        ),
        const SectionLabel('Buildings'),
        LabeledSlider(
          label: 'Height shading',
          value: style.heightShade,
          min: 0,
          max: 1,
          valueLabel: '${(style.heightShade * 100).round()}%',
          onChanged: (v) => controller.updateStyle(style.copyWith(heightShade: v),
              kind: 'heightShade'),
        ),
        _ColorRow(
          label: 'Tall building tint',
          color: style.heightColor ?? style.accentColor,
          onTap: () => pick('Tall building tint', style.heightColor ?? style.accentColor,
              (c) => controller.updateStyle(style.copyWith(heightColor: c))),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 2, 20, 0),
          child: Text(
            'Buildings are tinted by their real height from OpenStreetMap. Areas '
            'where nobody has mapped heights stay flat.',
            style: TextStyle(color: Shade.textFaint, fontSize: 11.5, height: 1.4),
          ),
        ),
        const SectionLabel('Colour grading'),
        LabeledSlider(
          label: 'Contrast',
          value: style.grade.contrast,
          min: 0.6,
          max: 1.8,
          valueLabel: style.grade.contrast.toStringAsFixed(2),
          onChanged: (v) => controller.updateStyle(
              style.copyWith(grade: style.grade.copyWith(contrast: v)),
              kind: 'grade'),
        ),
        LabeledSlider(
          label: 'Saturation',
          value: style.grade.saturation,
          min: 0,
          max: 1.8,
          valueLabel: style.grade.saturation.toStringAsFixed(2),
          onChanged: (v) => controller.updateStyle(
              style.copyWith(grade: style.grade.copyWith(saturation: v)),
              kind: 'grade'),
        ),
        LabeledSlider(
          label: 'Warmth',
          value: style.grade.warmth,
          min: -1,
          max: 1,
          valueLabel: style.grade.warmth.toStringAsFixed(2),
          onChanged: (v) => controller.updateStyle(
              style.copyWith(grade: style.grade.copyWith(warmth: v)),
              kind: 'grade'),
        ),
        LabeledSlider(
          label: 'Duotone',
          value: style.grade.duoAmount,
          min: 0,
          max: 1,
          valueLabel: '${(style.grade.duoAmount * 100).round()}%',
          onChanged: (v) => controller.updateStyle(
              style.copyWith(
                grade: style.grade.copyWith(
                  duoAmount: v,
                  duoShadow: style.grade.duoShadow ?? style.background,
                  duoHighlight: style.grade.duoHighlight ?? style.accentColor,
                ),
              ),
              kind: 'grade'),
        ),
        if (style.grade.duoAmount > 0.01) ...[
          _ColorRow(
            label: 'Shadow tone',
            color: style.grade.duoShadow ?? style.background,
            onTap: () => pick('Shadow tone', style.grade.duoShadow ?? style.background,
                (c) => controller.updateStyle(
                    style.copyWith(grade: style.grade.copyWith(duoShadow: c)))),
          ),
          _ColorRow(
            label: 'Highlight tone',
            color: style.grade.duoHighlight ?? style.accentColor,
            onTap: () => pick(
                'Highlight tone', style.grade.duoHighlight ?? style.accentColor,
                (c) => controller.updateStyle(
                    style.copyWith(grade: style.grade.copyWith(duoHighlight: c)))),
          ),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
          child: GhostButton(
            label: 'Reset grading',
            icon: Icons.restart_alt,
            onPressed: () => controller.updateStyle(
                style.copyWith(grade: ColorGrade.none),
                kind: 'gradeReset'),
          ),
        ),
        const SectionLabel('Route'),
        _ColorRow(
          label: 'Route colour',
          color: style.routeColor,
          onTap: () => pick('Route', style.routeColor,
              (c) => controller.updateStyle(style.copyWith(routeColor: c))),
        ),
        LabeledSlider(
          label: 'Route weight',
          value: style.routeWidth,
          min: 1,
          max: 8,
          valueLabel: style.routeWidth.toStringAsFixed(1),
          onChanged: (v) => controller.updateStyle(style.copyWith(routeWidth: v)),
        ),
        LabeledSlider(
          label: 'Route glow',
          value: style.routeGlow,
          min: 0,
          max: 1,
          valueLabel: '${(style.routeGlow * 100).round()}%',
          onChanged: (v) => controller.updateStyle(style.copyWith(routeGlow: v)),
        ),
        if (state.route == null)
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: Text(
              'Import a GPX from the home screen to draw a run, ride or trip on top '
              'of the map.',
              style: TextStyle(color: Shade.textFaint, fontSize: 11.5, height: 1.4),
            ),
          ),
      ],
    );
  }

  static Color _shift(Color base) {
    final hsv = HSVColor.fromColor(base);
    return hsv
        .withHue((hsv.hue + 28) % 360)
        .withValue((hsv.value + 0.12).clamp(0.0, 1.0))
        .toColor();
  }
}

class _ColorRow extends StatelessWidget {
  const _ColorRow({
    required this.label,
    required this.color,
    this.onTap,
    this.enabled = true,
    this.onToggle,
  });

  final String label;
  final Color color;
  final VoidCallback? onTap;
  final bool enabled;
  final ValueChanged<bool>? onToggle;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 9, 16, 9),
        child: Row(
          children: [
            Opacity(
              opacity: enabled ? 1 : 0.35,
              child: ColorDot(color: color, size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      color: enabled ? Shade.text : Shade.textFaint, fontSize: 14.5)),
            ),
            if (onToggle != null)
              Transform.scale(
                scale: 0.8,
                child: Switch(value: enabled, onChanged: onToggle),
              )
            else
              const Icon(Icons.tune, size: 17, color: Shade.textFaint),
          ],
        ),
      ),
    );
  }
}
