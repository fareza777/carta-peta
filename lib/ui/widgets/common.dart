import 'package:flutter/material.dart';

import '../../core/theme.dart';

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
      child: Row(
        children: [
          Text(
            text.toUpperCase(),
            style: const TextStyle(
              color: Shade.textFaint,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.4,
            ),
          ),
          const Spacer(),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class LabeledSlider extends StatelessWidget {
  const LabeledSlider({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.onChangeEnd,
    this.valueLabel,
    this.divisions,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;
  final String? valueLabel;
  final int? divisions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(label, style: const TextStyle(color: Shade.textDim, fontSize: 13)),
              const Spacer(),
              Text(
                valueLabel ?? value.toStringAsFixed(2),
                style: const TextStyle(
                    color: Shade.text, fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          SizedBox(
            height: 30,
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
              onChangeEnd: onChangeEnd,
            ),
          ),
        ],
      ),
    );
  }
}

class ToggleRow extends StatelessWidget {
  const ToggleRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 14, 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(color: Shade.text, fontSize: 14.5)),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(subtitle!,
                          style: const TextStyle(color: Shade.textFaint, fontSize: 11.5)),
                    ),
                ],
              ),
            ),
            Transform.scale(
              scale: 0.85,
              child: Switch(value: value, onChanged: onChanged),
            ),
          ],
        ),
      ),
    );
  }
}

/// Horizontally scrolling single-choice chips.
class ChoiceStrip<T> extends StatelessWidget {
  const ChoiceStrip({
    super.key,
    required this.items,
    required this.selected,
    required this.labelOf,
    required this.onSelect,
    this.subtitleOf,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
  });

  final List<T> items;
  final T? selected;
  final String Function(T) labelOf;
  final String Function(T)? subtitleOf;
  final ValueChanged<T> onSelect;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: subtitleOf == null ? 42 : 56,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: padding,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final item = items[i];
          final active = item == selected;
          return GestureDetector(
            onTap: () => onSelect(item),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: active ? Shade.accent : Shade.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: active ? Shade.accent : Shade.line),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    labelOf(item),
                    style: TextStyle(
                      color: active ? const Color(0xFF14100A) : Shade.text,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (subtitleOf != null)
                    Text(
                      subtitleOf!(item),
                      style: TextStyle(
                        color: active ? const Color(0xAA14100A) : Shade.textFaint,
                        fontSize: 11,
                      ),
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

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.expand = true,
    this.busy = false,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool expand;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final child = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (busy)
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF14100A)),
          )
        else if (icon != null)
          Icon(icon, size: 18, color: const Color(0xFF14100A)),
        if (icon != null || busy) const SizedBox(width: 9),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF14100A),
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );

    return GestureDetector(
      onTap: busy ? null : onPressed,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: onPressed == null ? Shade.surfaceHi : Shade.accent,
          borderRadius: BorderRadius.circular(15),
        ),
        alignment: Alignment.center,
        child: child,
      ),
    );
  }
}

class GhostButton extends StatelessWidget {
  const GhostButton({super.key, required this.label, required this.onPressed, this.icon});

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: Shade.surface,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: Shade.line),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: Shade.text),
              const SizedBox(width: 9),
            ],
            Text(label,
                style: const TextStyle(
                    color: Shade.text, fontSize: 15, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class EmptyHint extends StatelessWidget {
  const EmptyHint({super.key, required this.icon, required this.title, this.body});

  final IconData icon;
  final String title;
  final String? body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 30, color: Shade.textFaint),
          const SizedBox(height: 12),
          Text(title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Shade.textDim, fontSize: 14.5, fontWeight: FontWeight.w600)),
          if (body != null) ...[
            const SizedBox(height: 6),
            Text(body!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Shade.textFaint, fontSize: 12.5, height: 1.4)),
          ],
        ],
      ),
    );
  }
}
