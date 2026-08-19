import 'package:flutter/material.dart';

import '../../core/theme.dart';

const List<Color> kSwatches = [
  Color(0xFF000000), Color(0xFF15151A), Color(0xFF2E2E36), Color(0xFF5A5A66),
  Color(0xFF9A97A0), Color(0xFFCFCCC6), Color(0xFFF3F1EC), Color(0xFFFFFFFF),
  Color(0xFFD8B370), Color(0xFFC9A44C), Color(0xFFB87333), Color(0xFF8C6E45),
  Color(0xFFE2503F), Color(0xFFFF6B5B), Color(0xFFE8879B), Color(0xFFC97A92),
  Color(0xFF6A2CC7), Color(0xFF8A4DE8), Color(0xFFFF2FB9), Color(0xFF00E5FF),
  Color(0xFF1B9AAA), Color(0xFF2E5E7E), Color(0xFF0A2647), Color(0xFF06192E),
  Color(0xFF3E9C9C), Color(0xFF7FBF8A), Color(0xFF13301F), Color(0xFFCBD4A8),
  Color(0xFFF0E3C6), Color(0xFFFDF6F1), Color(0xFFDCE6EC), Color(0xFFEAEEF1),
];

/// Compact colour dot used inside the studio panels.
class ColorDot extends StatelessWidget {
  const ColorDot({super.key, required this.color, this.size = 30, this.selected = false});

  final Color color;
  final double size;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? Shade.accent : Shade.line,
          width: selected ? 2 : 1,
        ),
      ),
    );
  }
}

Future<Color?> showColorPicker(
  BuildContext context, {
  required Color initial,
  required String title,
}) {
  return showModalBottomSheet<Color>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Shade.bgAlt,
    builder: (_) => _ColorPickerSheet(initial: initial, title: title),
  );
}

class _ColorPickerSheet extends StatefulWidget {
  const _ColorPickerSheet({required this.initial, required this.title});

  final Color initial;
  final String title;

  @override
  State<_ColorPickerSheet> createState() => _ColorPickerSheetState();
}

class _ColorPickerSheetState extends State<_ColorPickerSheet> {
  late HSVColor _hsv = HSVColor.fromColor(widget.initial);

  Color get _color => _hsv.toColor();

  String get _hex =>
      '#${(_color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: _color,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: Shade.line),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.title,
                          style: const TextStyle(
                              color: Shade.text, fontSize: 15, fontWeight: FontWeight.w600)),
                      Text(_hex,
                          style: const TextStyle(
                              color: Shade.textFaint, fontSize: 12, letterSpacing: 0.6)),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(_color),
                  child: const Text('Apply',
                      style: TextStyle(color: Shade.accent, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _SaturationPad(
              hsv: _hsv,
              onChanged: (h) => setState(() => _hsv = h),
            ),
            const SizedBox(height: 14),
            _HueSlider(
              hue: _hsv.hue,
              onChanged: (h) => setState(() => _hsv = _hsv.withHue(h)),
            ),
            const SizedBox(height: 18),
            const Text('PALETTE',
                style: TextStyle(
                    color: Shade.textFaint,
                    fontSize: 10.5,
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 9,
              runSpacing: 9,
              children: [
                for (final c in kSwatches)
                  GestureDetector(
                    onTap: () => setState(() => _hsv = HSVColor.fromColor(c)),
                    child: ColorDot(
                      color: c,
                      size: 28,
                      selected: c.toARGB32() == _color.toARGB32(),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SaturationPad extends StatelessWidget {
  const _SaturationPad({required this.hsv, required this.onChanged});

  final HSVColor hsv;
  final ValueChanged<HSVColor> onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        const h = 168.0;
        void handle(Offset p) {
          final s = (p.dx / w).clamp(0.0, 1.0);
          final v = 1 - (p.dy / h).clamp(0.0, 1.0);
          onChanged(hsv.withSaturation(s).withValue(v));
        }

        return GestureDetector(
          onPanDown: (d) => handle(d.localPosition),
          onPanUpdate: (d) => handle(d.localPosition),
          child: SizedBox(
            width: w,
            height: h,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.white,
                          HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor(),
                        ],
                      ),
                    ),
                  ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black],
                      ),
                    ),
                    child: SizedBox.expand(),
                  ),
                  Positioned(
                    left: (hsv.saturation * w - 9).clamp(0.0, w - 18),
                    top: ((1 - hsv.value) * h - 9).clamp(0.0, h - 18),
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2.4),
                        boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 4)],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _HueSlider extends StatelessWidget {
  const _HueSlider({required this.hue, required this.onChanged});

  final double hue;
  final ValueChanged<double> onChanged;

  static const _hues = [
    Color(0xFFFF0000), Color(0xFFFFFF00), Color(0xFF00FF00), Color(0xFF00FFFF),
    Color(0xFF0000FF), Color(0xFFFF00FF), Color(0xFFFF0000),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        void handle(Offset p) => onChanged(((p.dx / w).clamp(0.0, 1.0)) * 360);
        return GestureDetector(
          onPanDown: (d) => handle(d.localPosition),
          onPanUpdate: (d) => handle(d.localPosition),
          child: SizedBox(
            width: w,
            height: 26,
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(13),
                  child: const DecoratedBox(
                    decoration: BoxDecoration(gradient: LinearGradient(colors: _hues)),
                    child: SizedBox.expand(),
                  ),
                ),
                Positioned(
                  left: ((hue / 360) * w - 11).clamp(0.0, w - 22),
                  top: 2,
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: HSVColor.fromAHSV(1, hue, 1, 1).toColor(),
                      border: Border.all(color: Colors.white, width: 2.4),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
