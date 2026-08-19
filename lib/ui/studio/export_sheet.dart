import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../model/format_spec.dart';
import '../../presets/format_presets.dart';
import '../../render/exporter.dart';
import '../../state/studio_controller.dart';
import '../widgets/common.dart';

Future<void> showExportSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Shade.bgAlt,
    builder: (_) => const _ExportSheet(),
  );
}

class _ExportSheet extends ConsumerStatefulWidget {
  const _ExportSheet();

  @override
  ConsumerState<_ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends ConsumerState<_ExportSheet> {
  int _index = -1;
  ExportFormat _format = ExportFormat.png;
  bool _busy = false;
  double _progress = 0;
  ExportResult? _result;
  String? _error;

  /// Default to the first option that clears 4K, which is the sweet spot
  /// between print quality and how long a phone takes to render.
  static int _defaultIndex(List<int> widths, FormatSpec format) {
    for (var i = 0; i < widths.length; i++) {
      final w = widths[i];
      final h = format.heightFor(w);
      if ((w > h ? w : h) >= 3840) return i;
    }
    return widths.length - 1;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(studioControllerProvider);
    final format = state.format;
    final widths = format.exportWidths;
    if (_index < 0) _index = _defaultIndex(widths, format);

    final width = widths[_index.clamp(0, widths.length - 1)];
    final height = format.heightFor(width);
    final tooBigForJpeg = width * height > PosterExporter.jpegMaxPixels;

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('Export',
                      style: TextStyle(
                          color: Shade.text, fontSize: 19, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  Text('${format.name}  ${format.hint}',
                      style: const TextStyle(color: Shade.textFaint, fontSize: 12.5)),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  for (final f in ExportFormat.values) ...[
                    Expanded(
                      child: _FormatTile(
                        format: f,
                        selected: _format == f,
                        disabled: f == ExportFormat.jpeg && tooBigForJpeg,
                        onTap: () => setState(() => _format = f),
                      ),
                    ),
                    if (f != ExportFormat.values.last) const SizedBox(width: 8),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _format == ExportFormat.pdf
                    ? 'Page ${(width / PosterExporter.printDpi).toStringAsFixed(1)} x '
                        '${(height / PosterExporter.printDpi).toStringAsFixed(1)} inch '
                        'at ${PosterExporter.printDpi.round()} DPI'
                    : _format.hint,
                style: const TextStyle(color: Shade.textFaint, fontSize: 11.5),
              ),
              const SizedBox(height: 16),
              for (var i = 0; i < widths.length; i++) _option(format, widths[i], i),
              const SizedBox(height: 14),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(_error!,
                      style: const TextStyle(color: Shade.danger, fontSize: 12.5)),
                ),
              if (_result != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      Icon(
                        _result!.savedToGallery
                            ? Icons.check_circle_outline
                            : Icons.info_outline,
                        size: 17,
                        color: _result!.savedToGallery ? Shade.accent : Shade.textDim,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _result!.savedToGallery
                              ? 'Saved to your gallery (CARTA album) - '
                                  '${formatBytes(_result!.bytes)}'
                              : '${_result!.format.label} written to app storage - '
                                  '${formatBytes(_result!.bytes)}. Use Share to keep it.',
                          style: const TextStyle(
                              color: Shade.textDim, fontSize: 12, height: 1.35),
                        ),
                      ),
                    ],
                  ),
                ),
              if (_busy)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: _progress <= 0 ? null : _progress,
                          minHeight: 5,
                          backgroundColor: Shade.surfaceHi,
                          valueColor: const AlwaysStoppedAnimation(Shade.accent),
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        'Rendering ${(_progress * 100).round()}%  -  keep the app open',
                        style: const TextStyle(color: Shade.textDim, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: PrimaryButton(
                      label: _result == null ? 'Render & save' : 'Render again',
                      icon: Icons.download_outlined,
                      busy: _busy,
                      onPressed: _busy ? null : () => _run(share: false),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: GhostButton(
                      label: 'Share',
                      icon: Icons.ios_share,
                      onPressed: _busy ? null : () => _run(share: true),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'Every export carries the OpenStreetMap credit required by the ODbL '
                'licence.',
                style: TextStyle(color: Shade.textFaint, fontSize: 11, height: 1.4),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _option(FormatSpec format, int width, int i) {
    final height = format.heightFor(width);
    final selected = i == _index;
    final mp = format.megapixelsFor(width);
    return GestureDetector(
      onTap: () => setState(() {
        _index = i;
        if (_format == ExportFormat.jpeg &&
            width * height > PosterExporter.jpegMaxPixels) {
          _format = ExportFormat.png;
        }
      }),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
        decoration: BoxDecoration(
          color: selected ? Shade.surfaceHi : Shade.surface,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: selected ? Shade.accent : Shade.line),
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              size: 18,
              color: selected ? Shade.accent : Shade.textFaint,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text('$width x $height',
                  style: const TextStyle(
                      color: Shade.text, fontSize: 14.5, fontWeight: FontWeight.w600)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Shade.bg,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                resolutionTier(width, height),
                style: const TextStyle(
                    color: Shade.accent, fontSize: 10.5, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 8),
            Text('${mp.toStringAsFixed(1)} MP',
                style: const TextStyle(color: Shade.textFaint, fontSize: 11.5)),
          ],
        ),
      ),
    );
  }

  Future<void> _run({required bool share}) async {
    final state = ref.read(studioControllerProvider);
    if (!state.hasArtwork) return;
    final format = state.format;
    final width = format.exportWidths[_index.clamp(0, format.exportWidths.length - 1)];
    final height = format.heightFor(width);

    setState(() {
      _busy = true;
      _progress = 0;
      _error = null;
      _result = null;
    });
    try {
      final result = await PosterExporter.export(
        state.scene,
        width: width,
        height: height,
        baseName: state.place?.name ?? 'carta',
        format: _format,
        toGallery: !share,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (!mounted) return;
      setState(() => _result = result);
      if (share) {
        await PosterExporter.share(result.filePath, state.place?.name ?? 'CARTA');
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _FormatTile extends StatelessWidget {
  const _FormatTile({
    required this.format,
    required this.selected,
    required this.disabled,
    required this.onTap,
  });

  final ExportFormat format;
  final bool selected;
  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: disabled ? 0.35 : 1,
      child: GestureDetector(
        onTap: disabled ? null : onTap,
        child: Container(
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? Shade.accent : Shade.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: selected ? Shade.accent : Shade.line),
          ),
          child: Text(
            format.label,
            style: TextStyle(
              color: selected ? const Color(0xFF14100A) : Shade.text,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
