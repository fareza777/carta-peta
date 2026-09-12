import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format.dart';
import '../../../core/theme.dart';
import '../../../data/device_location.dart';
import '../../../data/routing/osrm_client.dart';
import '../../../data/store/prefs_store.dart';
import '../../../model/place.dart';
import '../../../state/providers.dart';
import '../../../state/studio_controller.dart';
import '../../widgets/common.dart';
import '../../widgets/place_search_sheet.dart';

/// Everything about *which* place the poster is about: lifting one
/// neighbourhood out of its surroundings, and drawing the journey between two
/// addresses.
class PlacePanel extends ConsumerStatefulWidget {
  const PlacePanel({super.key});

  @override
  ConsumerState<PlacePanel> createState() => _PlacePanelState();
}

class _PlacePanelState extends ConsumerState<PlacePanel> {
  PlaceRef? _from;
  PlaceRef? _to;
  PlaceRef? _home;
  PlaceRef? _work;
  TravelMode _mode = TravelMode.car;
  bool _planning = false;
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    _restoreSaved();
  }

  /// A commute poster is nearly always the same two places, so they are
  /// remembered and pre-filled.
  Future<void> _restoreSaved() async {
    final prefs = ref.read(prefsStoreProvider);
    final home = await prefs.savedPlace(SavedSpot.home);
    final work = await prefs.savedPlace(SavedSpot.work);
    if (!mounted) return;
    setState(() {
      _home = home;
      _work = work;
      _from ??= home;
      _to ??= work;
    });
  }

  void _set(bool isFrom, PlaceRef place) =>
      setState(() => isFrom ? _from = place : _to = place);

  Future<void> _handle(bool isFrom, EndpointAction action) async {
    final messenger = ScaffoldMessenger.of(context);
    switch (action) {
      case EndpointAction.search:
        final place = await showPlaceSearch(context);
        if (place != null && mounted) _set(isFrom, place);
      case EndpointAction.myLocation:
        setState(() => _locating = true);
        final found = await locateDevice(ref.read(nominatimProvider));
        if (!mounted) return;
        setState(() => _locating = false);
        final place = found.place;
        if (place != null) {
          _set(isFrom, place);
        } else {
          messenger.showSnackBar(SnackBar(
            content: Text(found.outcome == LocationOutcome.denied
                ? 'Location permission is off, so the app cannot use where you are'
                : 'Could not get a location fix right now'),
          ));
        }
      case EndpointAction.useHome:
        final home = _home;
        if (home != null) _set(isFrom, home);
      case EndpointAction.useWork:
        final work = _work;
        if (work != null) _set(isFrom, work);
      case EndpointAction.saveHome:
      case EndpointAction.saveWork:
        final place = isFrom ? _from : _to;
        if (place == null) return;
        final spot =
            action == EndpointAction.saveHome ? SavedSpot.home : SavedSpot.work;
        await ref.read(prefsStoreProvider).setSavedPlace(spot, place);
        if (!mounted) return;
        setState(() => spot == SavedSpot.home ? _home = place : _work = place);
        messenger.showSnackBar(SnackBar(
          content: Text('Saved ${place.name} as '
              '${spot == SavedSpot.home ? 'Home' : 'Work'}'),
        ));
    }
  }

  void _swap() => setState(() {
        final was = _from;
        _from = _to;
        _to = was;
      });

  Future<void> _plan() async {
    final from = _from, to = _to;
    if (from == null || to == null) return;
    setState(() => _planning = true);
    final error = await ref
        .read(studioControllerProvider.notifier)
        .planRoute(from: from, to: to, mode: _mode);
    if (!mounted) return;
    setState(() => _planning = false);
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(studioControllerProvider);
    final controller = ref.read(studioControllerProvider.notifier);
    final style = state.style;
    final highlighted = state.highlight != null;

    return ListView(
      padding: const EdgeInsets.only(bottom: 26),
      children: [
        const SectionLabel('Highlight an area'),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Text(
            _highlightNote(state),
            style: const TextStyle(color: Shade.textFaint, fontSize: 11.5, height: 1.4),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Expanded(
                child: GhostButton(
                  label: state.highlightStatus == HighlightStatus.loading
                      ? 'Looking up...'
                      : (highlighted ? 'Update outline' : 'Highlight this area'),
                  icon: Icons.interests_outlined,
                  onPressed: state.place == null ||
                          state.highlightStatus == HighlightStatus.loading
                      ? null
                      : () => controller.highlightPlace(),
                ),
              ),
              if (highlighted) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: GhostButton(
                    label: 'Remove',
                    icon: Icons.close,
                    onPressed: controller.clearHighlight,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (highlighted) ...[
          LabeledSlider(
            label: 'Fade the surroundings',
            value: style.highlightDim,
            min: 0,
            max: 1,
            valueLabel: '${(style.highlightDim * 100).round()}%',
            onChanged: (v) => controller.setHighlightStyle(dim: v),
          ),
          LabeledSlider(
            label: 'Tint inside',
            value: style.highlightTint,
            min: 0,
            max: 1,
            valueLabel: '${(style.highlightTint * 100).round()}%',
            onChanged: (v) => controller.setHighlightStyle(tint: v),
          ),
          LabeledSlider(
            label: 'Outline weight',
            value: style.highlightWidth,
            min: 0,
            max: 8,
            valueLabel: style.highlightWidth.toStringAsFixed(1),
            onChanged: (v) => controller.setHighlightStyle(width: v),
          ),
        ],
        const SectionLabel('Route between two places'),
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Text(
            'Home to work, the school run, a favourite ride - the real roads '
            'between them become the artwork, and the title becomes "A to B".',
            style: TextStyle(color: Shade.textFaint, fontSize: 11.5, height: 1.4),
          ),
        ),
        _EndpointRow(
          label: 'From',
          place: _from,
          busy: _locating,
          hasHome: _home != null,
          hasWork: _work != null,
          onAction: (a) => _handle(true, a),
        ),
        _EndpointRow(
          label: 'To',
          place: _to,
          busy: _locating,
          hasHome: _home != null,
          hasWork: _work != null,
          onAction: (a) => _handle(false, a),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.only(right: 14),
            child: TextButton.icon(
              onPressed: _from == null && _to == null ? null : _swap,
              icon: const Icon(Icons.swap_vert, size: 17),
              label: const Text('Swap'),
              style: TextButton.styleFrom(foregroundColor: Shade.textDim),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
          child: ChoiceStrip<TravelMode>(
            items: TravelMode.values,
            selected: _mode,
            labelOf: (m) => m.label,
            onSelect: (m) => setState(() => _mode = m),
          ),
        ),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: PrimaryButton(
            label: _planning ? 'Planning...' : 'Draw this journey',
            icon: Icons.alt_route,
            onPressed:
                _from == null || _to == null || _planning ? null : _plan,
          ),
        ),
        if (state.routes.isNotEmpty) ...[
          const SectionLabel('On this poster'),
          for (var i = 0; i < state.routes.length; i++)
            _TrackRow(
              name: state.routes[i].name,
              detail: formatDistance(state.routes[i].distanceMetres),
              onRemove: () => controller.detachRoute(i),
            ),
        ],
      ],
    );
  }

  String _highlightNote(StudioState state) => switch (state.highlightStatus) {
        HighlightStatus.loading => 'Asking OpenStreetMap for the outline...',
        HighlightStatus.ready =>
          'Outline drawn from OpenStreetMap boundary data. The title now reads '
              '${state.highlight?.name ?? ''}.',
        HighlightStatus.unavailable =>
          'OpenStreetMap has no outline for this place. Villages, kelurahan, '
              'districts and cities usually have one; a single address does not.',
        HighlightStatus.off =>
          'Dims everything outside the chosen area so one neighbourhood, village '
              'or district reads as the subject.',
      };
}

enum EndpointAction { search, myLocation, useHome, useWork, saveHome, saveWork }

class _EndpointRow extends StatelessWidget {
  const _EndpointRow({
    required this.label,
    required this.place,
    required this.busy,
    required this.hasHome,
    required this.hasWork,
    required this.onAction,
  });

  final String label;
  final PlaceRef? place;
  final bool busy;
  final bool hasHome;
  final bool hasWork;
  final ValueChanged<EndpointAction> onAction;

  @override
  Widget build(BuildContext context) {
    final chosen = place;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: PopupMenuButton<EndpointAction>(
        onSelected: onAction,
        color: Shade.bgAlt,
        position: PopupMenuPosition.under,
        itemBuilder: (context) => [
          const PopupMenuItem(
            value: EndpointAction.search,
            child: _MenuLine(icon: Icons.search, label: 'Search a place'),
          ),
          const PopupMenuItem(
            value: EndpointAction.myLocation,
            child: _MenuLine(icon: Icons.my_location, label: 'Use my location'),
          ),
          if (hasHome)
            const PopupMenuItem(
              value: EndpointAction.useHome,
              child: _MenuLine(icon: Icons.home_outlined, label: 'Use Home'),
            ),
          if (hasWork)
            const PopupMenuItem(
              value: EndpointAction.useWork,
              child: _MenuLine(icon: Icons.work_outline, label: 'Use Work'),
            ),
          if (chosen != null) ...[
            const PopupMenuDivider(),
            const PopupMenuItem(
              value: EndpointAction.saveHome,
              child: _MenuLine(icon: Icons.home_outlined, label: 'Save as Home'),
            ),
            const PopupMenuItem(
              value: EndpointAction.saveWork,
              child: _MenuLine(icon: Icons.work_outline, label: 'Save as Work'),
            ),
          ],
        ],
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Shade.bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Shade.line),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 42,
                child: Text(
                  label,
                  style: const TextStyle(
                      color: Shade.textFaint, fontSize: 11.5, letterSpacing: 0.6),
                ),
              ),
              Expanded(
                child: Text(
                  chosen?.name ?? 'Choose a place',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: chosen == null ? Shade.textFaint : Shade.text,
                    fontSize: 13.5,
                  ),
                ),
              ),
              if (busy)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 1.6),
                )
              else
                const Icon(Icons.expand_more, size: 18, color: Shade.textFaint),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuLine extends StatelessWidget {
  const _MenuLine({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, size: 17, color: Shade.textDim),
          const SizedBox(width: 10),
          Text(label, style: const TextStyle(color: Shade.text, fontSize: 13.5)),
        ],
      );
}

class _TrackRow extends StatelessWidget {
  const _TrackRow(
      {required this.name, required this.detail, required this.onRemove});

  final String name;
  final String detail;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 12, 4),
      child: Row(
        children: [
          const Icon(Icons.route_outlined, size: 16, color: Shade.textFaint),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Shade.text, fontSize: 13),
            ),
          ),
          Text(detail,
              style: const TextStyle(color: Shade.textFaint, fontSize: 12)),
          IconButton(
            icon: const Icon(Icons.close, size: 17, color: Shade.textFaint),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}
