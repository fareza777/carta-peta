import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../render/exporter.dart';
import '../../state/library_controller.dart';
import '../../state/studio_controller.dart';
import '../widgets/common.dart';
import '../widgets/place_search_sheet.dart';
import '../widgets/poster_view.dart';
import 'export_sheet.dart';
import 'panels/frame_panel.dart';
import 'panels/layers_panel.dart';
import 'panels/palette_panel.dart';
import 'panels/place_panel.dart';
import 'panels/presets_panel.dart';
import 'panels/size_panel.dart';
import 'panels/text_panel.dart';

const _tabs = ['Looks', 'Colour', 'Layers', 'Place', 'Text', 'Frame', 'Size'];

class StudioScreen extends ConsumerStatefulWidget {
  const StudioScreen({super.key});

  @override
  ConsumerState<StudioScreen> createState() => _StudioScreenState();
}

class _StudioScreenState extends ConsumerState<StudioScreen> {
  int _tab = 0;
  bool _panelOpen = true;
  bool _saving = false;

  double _startZoom = 1;
  Offset _startPan = Offset.zero;
  Size _previewSize = const Size(1, 1);
  Offset _accumulated = Offset.zero;

  Future<void> _save() async {
    final state = ref.read(studioControllerProvider);
    if (!state.hasArtwork) return;
    setState(() => _saving = true);
    try {
      final design = ref.read(studioControllerProvider.notifier).toDesign();
      final thumb = await PosterExporter.thumbnail(state.scene, width: 360);
      await ref.read(libraryControllerProvider.notifier).save(design, thumbnail: thumb);
      ref.read(studioControllerProvider.notifier).markSaved();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Saved to your library')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not save: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _changePlace() async {
    final place = await showPlaceSearch(context);
    if (place == null || !mounted) return;
    await ref.read(studioControllerProvider.notifier).recentre(place);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(studioControllerProvider);

    return Scaffold(
      backgroundColor: Shade.bg,
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, c) {
            final wide = c.maxWidth > c.maxHeight && c.maxWidth > 640;
            if (wide) {
              return Row(
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        _topBar(state, compact: true),
                        Expanded(child: _preview(state)),
                      ],
                    ),
                  ),
                  Container(
                    width: 356,
                    decoration: const BoxDecoration(
                      color: Shade.bgAlt,
                      border: Border(left: BorderSide(color: Shade.line)),
                    ),
                    child: _panel(state, collapsible: false),
                  ),
                ],
              );
            }
            final panelHeight =
                _panelOpen ? (c.maxHeight * 0.42).clamp(268.0, 400.0) : 62.0;
            return Column(
              children: [
                _topBar(state),
                Expanded(child: _preview(state)),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  height: panelHeight + MediaQuery.of(context).padding.bottom,
                  decoration: const BoxDecoration(
                    color: Shade.bgAlt,
                    border: Border(top: BorderSide(color: Shade.line)),
                  ),
                  child: _panel(state, collapsible: true),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _topBar(StudioState state, {bool compact = false}) {
    final controller = ref.read(studioControllerProvider.notifier);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, size: 19),
            onPressed: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: InkWell(
              onTap: _changePlace,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            state.place?.name ?? 'Studio',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Shade.text,
                                fontSize: 16,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                        const SizedBox(width: 5),
                        const Icon(Icons.search, size: 15, color: Shade.accent),
                      ],
                    ),
                    Text(
                      '${formatRadius(state.visibleSpanMetres)} across  -  '
                      '${state.style.name}'
                      '${state.fromCache ? '  -  offline' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Shade.textFaint, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Undo',
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.undo,
                size: 20, color: state.canUndo ? Shade.text : Shade.textFaint),
            onPressed: state.canUndo ? controller.undo : null,
          ),
          IconButton(
            tooltip: 'Redo',
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.redo,
                size: 20, color: state.canRedo ? Shade.text : Shade.textFaint),
            onPressed: state.canRedo ? controller.redo : null,
          ),
          IconButton(
            tooltip: 'Save to library',
            visualDensity: VisualDensity.compact,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Shade.accent))
                : Icon(
                    state.savedToLibrary ? Icons.bookmark : Icons.bookmark_border,
                    size: 21,
                    color: state.savedToLibrary ? Shade.accent : Shade.text,
                  ),
            onPressed: _saving || !state.hasArtwork ? null : _save,
          ),
          GestureDetector(
            onTap: state.hasArtwork ? () => showExportSheet(context, ref) : null,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 16, vertical: 9),
              decoration: BoxDecoration(
                color: state.hasArtwork ? Shade.accent : Shade.surfaceHi,
                borderRadius: BorderRadius.circular(11),
              ),
              child: const Text(
                'Export',
                style: TextStyle(
                    color: Color(0xFF14100A), fontSize: 13.5, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _preview(StudioState state) {
    final controller = ref.read(studioControllerProvider.notifier);
    return LayoutBuilder(
      builder: (context, c) {
        _previewSize = Size(c.maxWidth, c.maxHeight);
        return Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              onScaleStart: (_) {
                controller.beginViewChange();
                _startZoom = state.zoom;
                _startPan = state.pan;
                _accumulated = Offset.zero;
              },
              onScaleUpdate: (d) {
                if (d.pointerCount > 1) {
                  controller.setZoom(_startZoom * d.scale);
                }
                _accumulated += d.focalPointDelta;
                final span = _previewSize.height * ref.read(studioControllerProvider).zoom;
                if (span > 0) {
                  controller.setPan(_startPan + _accumulated / span);
                }
              },
              onDoubleTap: controller.resetView,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(26, 14, 26, 20),
                child: Center(child: PosterFrame(scene: state.scene)),
              ),
            ),
            if (state.status == StudioStatus.loading) _loading(state),
            if (state.status == StudioStatus.error) _error(state),
            if (state.contourStatus == ContourStatus.loading) _contourBadge(),
          ],
        );
      },
    );
  }

  Widget _contourBadge() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 6,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: Shade.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Shade.line),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 2, color: Shade.accent),
              ),
              SizedBox(width: 9),
              Text('Tracing terrain contours',
                  style: TextStyle(color: Shade.textDim, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _loading(StudioState state) {
    return IgnorePointer(
      child: Container(
        color: Shade.bg.withValues(alpha: 0.72),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(strokeWidth: 2.2, color: Shade.accent),
            ),
            const SizedBox(height: 16),
            Text(
              state.statusMessage.isEmpty ? 'Preparing...' : state.statusMessage,
              style: const TextStyle(color: Shade.textDim, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _error(StudioState state) {
    return Container(
      color: Shade.bg.withValues(alpha: 0.9),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 34),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_outlined, color: Shade.textFaint, size: 30),
          const SizedBox(height: 14),
          Text(
            state.error ?? 'Something went wrong',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Shade.textDim, fontSize: 13.5, height: 1.45),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: 190,
            child: PrimaryButton(
              label: 'Try again',
              icon: Icons.refresh,
              onPressed: () =>
                  ref.read(studioControllerProvider.notifier).reload(force: true),
            ),
          ),
        ],
      ),
    );
  }

  Widget _panel(StudioState state, {required bool collapsible}) {
    return Column(
      children: [
        SizedBox(
          height: 62,
          child: Row(
            children: [
              Expanded(
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
                  itemCount: _tabs.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 7),
                  itemBuilder: (context, i) {
                    final active = i == _tab;
                    return GestureDetector(
                      onTap: () => setState(() {
                        _tab = i;
                        _panelOpen = true;
                      }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 15),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: active ? Shade.surfaceHi : Colors.transparent,
                          borderRadius: BorderRadius.circular(11),
                          border:
                              Border.all(color: active ? Shade.line : Colors.transparent),
                        ),
                        child: Text(
                          _tabs[i],
                          style: TextStyle(
                            color: active ? Shade.text : Shade.textFaint,
                            fontSize: 13.5,
                            fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              if (collapsible)
                IconButton(
                  icon: Icon(
                    _panelOpen ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
                    color: Shade.textDim,
                  ),
                  onPressed: () => setState(() => _panelOpen = !_panelOpen),
                ),
            ],
          ),
        ),
        if (_panelOpen || !collapsible)
          Expanded(
            child: IndexedStack(
              index: _tab,
              sizing: StackFit.expand,
              children: const [
                PresetsPanel(),
                PalettePanel(),
                LayersPanel(),
                PlacePanel(),
                TextPanel(),
                FramePanel(),
                SizePanel(),
              ],
            ),
          ),
      ],
    );
  }
}
