import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../model/place.dart';
import '../../presets/curated_places.dart';
import '../../state/search_controller.dart';
import 'common.dart';

/// Location search as a sheet, so the studio can move somewhere else without
/// throwing away the look you just built.
Future<PlaceRef?> showPlaceSearch(BuildContext context, {String? title}) {
  return showModalBottomSheet<PlaceRef>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Shade.bgAlt,
    builder: (_) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: _PlaceSearchSheet(title: title ?? 'Move the map'),
    ),
  );
}

class _PlaceSearchSheet extends ConsumerStatefulWidget {
  const _PlaceSearchSheet({required this.title});

  final String title;

  @override
  ConsumerState<_PlaceSearchSheet> createState() => _PlaceSearchSheetState();
}

class _PlaceSearchSheetState extends ConsumerState<_PlaceSearchSheet> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final search = ref.watch(searchControllerProvider);
    final showResults = search.query.trim().length >= 2;
    final suggestions = search.recent.isNotEmpty ? search.recent : kCuratedPlaces;

    return SafeArea(
      top: false,
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.72,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
              child: Text(widget.title,
                  style: const TextStyle(
                      color: Shade.text, fontSize: 17, fontWeight: FontWeight.w600)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _controller,
                autofocus: true,
                textInputAction: TextInputAction.search,
                style: const TextStyle(color: Shade.text, fontSize: 15),
                onChanged: ref.read(searchControllerProvider.notifier).onQueryChanged,
                onSubmitted: (_) => ref.read(searchControllerProvider.notifier).submit(),
                decoration: InputDecoration(
                  hintText: 'City, address or landmark',
                  prefixIcon: const Icon(Icons.search, color: Shade.textFaint, size: 20),
                  suffixIcon: search.loading
                      ? const Padding(
                          padding: EdgeInsets.all(14),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Shade.accent),
                          ),
                        )
                      : null,
                ),
              ),
            ),
            Expanded(
              child: showResults
                  ? _results(search)
                  : ListView(
                      padding: const EdgeInsets.only(top: 8, bottom: 24),
                      children: [
                        SectionLabel(
                            search.recent.isNotEmpty ? 'Recent' : 'Popular'),
                        for (final p in suggestions.take(12)) _tile(p),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _results(SearchState search) {
    if (search.results.isEmpty && !search.loading) {
      return EmptyHint(
        icon: Icons.travel_explore_outlined,
        title: search.error ?? 'Nothing found',
        body: 'Try another spelling, or add the country name.',
      );
    }
    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      children: [for (final p in search.results) _tile(p)],
    );
  }

  Widget _tile(PlaceRef place) => ListTile(
        onTap: () {
          ref.read(searchControllerProvider.notifier).remember(place);
          Navigator.of(context).pop(place);
        },
        leading: const Icon(Icons.place_outlined, size: 19, color: Shade.accent),
        title: Text(place.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Shade.text, fontSize: 15)),
        subtitle: place.context.isEmpty
            ? null
            : Text(place.context,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Shade.textFaint, fontSize: 12)),
      );
}
