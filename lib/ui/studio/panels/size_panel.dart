import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../model/format_spec.dart';
import '../../../presets/format_presets.dart';
import '../../../state/studio_controller.dart';
import '../../widgets/common.dart';
import '../export_sheet.dart';

class SizePanel extends ConsumerWidget {
  const SizePanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(studioControllerProvider);
    final controller = ref.read(studioControllerProvider.notifier);

    return ListView(
      padding: const EdgeInsets.only(bottom: 26),
      children: [
        const SectionLabel('Canvas'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 9,
            runSpacing: 9,
            children: [
              for (final f in kFormats)
                _FormatChip(
                  format: f,
                  selected: f.id == state.format.id,
                  onTap: () => controller.setFormat(f),
                ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Text(
            'Wallpaper switches the poster to edge-to-edge with the text over the '
            'map. Change it back any time in the Frame tab.',
            style: TextStyle(color: Shade.textFaint, fontSize: 11.5, height: 1.4),
          ),
        ),
        const SectionLabel('Export'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            'Largest available: '
            '${state.format.labelFor(state.format.exportWidths.last)} px  ·  '
            '${state.format.megapixelsFor(state.format.exportWidths.last).toStringAsFixed(1)} MP',
            style: const TextStyle(color: Shade.textFaint, fontSize: 12),
          ),
        ),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: PrimaryButton(
            label: 'Export artwork',
            icon: Icons.download_outlined,
            onPressed: state.hasArtwork ? () => showExportSheet(context, ref) : null,
          ),
        ),
      ],
    );
  }
}

class _FormatChip extends StatelessWidget {
  const _FormatChip({required this.format, required this.selected, required this.onTap});

  final FormatSpec format;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final h = 46.0;
    final w = format.aspect >= 1 ? 34.0 : 34.0 * format.aspect / 1;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 104,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? Shade.surfaceHi : Shade.surface,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: selected ? Shade.accent : Shade.line),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 34,
              height: h,
              child: Center(
                child: Container(
                  width: format.aspect >= 1 ? 30 : w,
                  height: format.aspect >= 1 ? 30 / format.aspect : 40,
                  decoration: BoxDecoration(
                    border: Border.all(color: selected ? Shade.accent : Shade.textFaint),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(format.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: selected ? Shade.text : Shade.textDim,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      )),
                  Text(format.hint,
                      style: const TextStyle(color: Shade.textFaint, fontSize: 10.5)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
