import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/gpx_import.dart';
import '../../model/design.dart';
import '../../model/place.dart';
import '../../presets/curated_places.dart';
import '../../state/library_controller.dart';
import '../../state/providers.dart';
import '../../state/search_controller.dart';
import '../../state/studio_controller.dart';
import '../settings_screen.dart';
import '../studio/studio_screen.dart';
import '../widgets/common.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  bool _importing = false;

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _open(PlaceRef place) async {
    _focus.unfocus();
    ref.read(searchControllerProvider.notifier).remember(place);
    ref.read(studioControllerProvider.notifier).openPlace(place);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const StudioScreen()),
    );
    if (mounted) ref.read(libraryControllerProvider.notifier).refresh();
  }

  Future<void> _openDesign(Design design) async {
    _focus.unfocus();
    ref.read(studioControllerProvider.notifier).loadDesign(design);
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const StudioScreen()),
    );
    if (mounted) ref.read(libraryControllerProvider.notifier).refresh();
  }

  Future<void> _importGpx() async {
    setState(() => _importing = true);
    try {
      FilePickerResult? picked;
      try {
        picked = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: const ['gpx'],
        );
      } catch (_) {
        picked = await FilePicker.platform.pickFiles();
      }
      final path = picked?.files.single.path;
      if (path == null) return;

      final text = await File(path).readAsString();
      final route = parseGpx(text, fallbackName: 'My route');

      final geo = await ref.read(nominatimProvider).reverse(route.centre);
      final place = geo ??
          PlaceRef(
            name: route.name,
            context: formatDecimal(route.centre),
            country: '',
            centre: route.centre,
          );

      final studio = ref.read(studioControllerProvider.notifier);
      await studio.openPlace(
        PlaceRef(
          name: place.name,
          context: place.context,
          country: place.country,
          centre: route.centre,
        ),
        radius: route.suggestedRadius,
      );
      await studio.attachRoute(route, refit: false);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const StudioScreen()),
      );
      if (mounted) ref.read(libraryControllerProvider.notifier).refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not read that GPX: $e')));
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final search = ref.watch(searchControllerProvider);
    final showResults = search.query.trim().length >= 2;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _header(),
            _searchField(search.loading),
            Expanded(
              child: showResults ? _results(search) : _browse(search.recent),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'CARTA',
                  style: TextStyle(
                    color: Shade.text,
                    fontSize: 30,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 7,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  'Turn any place on Earth into art',
                  style: TextStyle(
                    color: Shade.accent.withValues(alpha: 0.85),
                    fontSize: 12.5,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
          ),
          _RoundAction(
            icon: Icons.route_outlined,
            busy: _importing,
            onTap: _importing ? null : _importGpx,
          ),
          const SizedBox(width: 10),
          _RoundAction(
            icon: Icons.tune,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _searchField(bool loading) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: TextField(
        controller: _controller,
        focusNode: _focus,
        textInputAction: TextInputAction.search,
        style: const TextStyle(color: Shade.text, fontSize: 15),
        onChanged: ref.read(searchControllerProvider.notifier).onQueryChanged,
        onSubmitted: (_) => ref.read(searchControllerProvider.notifier).submit(),
        decoration: InputDecoration(
          hintText: 'Search a city, address or landmark',
          prefixIcon: const Icon(Icons.search, color: Shade.textFaint, size: 20),
          suffixIcon: loading
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Shade.accent),
                  ),
                )
              : (_controller.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close, size: 18, color: Shade.textFaint),
                      onPressed: () {
                        _controller.clear();
                        ref.read(searchControllerProvider.notifier).clear();
                        setState(() {});
                      },
                    )),
        ),
      ),
    );
  }

  Widget _results(SearchState search) {
    if (search.error != null && search.results.isEmpty && !search.loading) {
      return EmptyHint(
        icon: Icons.travel_explore_outlined,
        title: search.error!,
        body: 'Try another spelling, or add the country name.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
      itemCount: search.results.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) => _PlaceTile(
        place: search.results[i],
        onTap: () => _open(search.results[i]),
      ),
    );
  }

  Widget _browse(List<PlaceRef> recent) {
    final library = ref.watch(libraryControllerProvider);
    return ListView(
      padding: const EdgeInsets.only(bottom: 44),
      children: [
        if (recent.isNotEmpty) ...[
          const SectionLabel('Recent'),
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: recent.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) => GestureDetector(
                onTap: () => _open(recent[i]),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 15),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Shade.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Shade.line),
                  ),
                  child: Text(recent[i].name,
                      style: const TextStyle(color: Shade.text, fontSize: 13.5)),
                ),
              ),
            ),
          ),
        ],
        const SectionLabel('Start with a place'),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 1.55,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
          ),
          itemCount: kCuratedPlaces.length,
          itemBuilder: (context, i) => _CuratedCard(
            place: kCuratedPlaces[i],
            index: i,
            onTap: () => _open(kCuratedPlaces[i]),
          ),
        ),
        const SectionLabel('Your library'),
        library.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(28),
            child: Center(
                child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Shade.accent))),
          ),
          error: (e, _) => EmptyHint(
              icon: Icons.error_outline, title: 'Library unavailable', body: '$e'),
          data: (designs) => designs.isEmpty
              ? const EmptyHint(
                  icon: Icons.bookmark_border,
                  title: 'Nothing saved yet',
                  body: 'Save a design in the studio and it will appear here, ready to '
                      're-export any time.',
                )
              : _LibraryGrid(designs: designs, onOpen: _openDesign),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(24, 22, 24, 0),
          child: Text(
            'Map data (c) OpenStreetMap contributors, ODbL. Search by Nominatim.',
            style: TextStyle(color: Shade.textFaint, fontSize: 11, height: 1.5),
          ),
        ),
      ],
    );
  }
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({required this.icon, this.onTap, this.busy = false});

  final IconData icon;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: Shade.surface,
          shape: BoxShape.circle,
          border: Border.all(color: Shade.line),
        ),
        child: busy
            ? const Padding(
                padding: EdgeInsets.all(14),
                child: CircularProgressIndicator(strokeWidth: 2, color: Shade.accent))
            : Icon(icon, size: 21, color: Shade.text),
      ),
    );
  }
}

class _PlaceTile extends StatelessWidget {
  const _PlaceTile({required this.place, required this.onTap});

  final PlaceRef place;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Shade.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Shade.line),
        ),
        child: Row(
          children: [
            const Icon(Icons.place_outlined, size: 19, color: Shade.accent),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(place.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Shade.text, fontSize: 15, fontWeight: FontWeight.w600)),
                  if (place.context.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(place.context,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Shade.textFaint, fontSize: 12)),
                    ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, size: 13, color: Shade.textFaint),
          ],
        ),
      ),
    );
  }
}

const _cardTints = [
  [Color(0xFF1B2432), Color(0xFF0D1017)],
  [Color(0xFF2A1F2D), Color(0xFF120D14)],
  [Color(0xFF1E2A24), Color(0xFF0C1310)],
  [Color(0xFF2C241A), Color(0xFF14100A)],
];

class _CuratedCard extends StatelessWidget {
  const _CuratedCard({required this.place, required this.index, required this.onTap});

  final PlaceRef place;
  final int index;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tint = _cardTints[index % _cardTints.length];
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: tint,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Shade.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            const Spacer(),
            Text(place.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Shade.text, fontSize: 16.5, fontWeight: FontWeight.w600)),
            const SizedBox(height: 3),
            Text(place.country,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Shade.textFaint, fontSize: 11.5)),
          ],
        ),
      ),
    );
  }
}

class _LibraryGrid extends ConsumerWidget {
  const _LibraryGrid({required this.designs, required this.onOpen});

  final List<Design> designs;
  final ValueChanged<Design> onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.66,
        crossAxisSpacing: 10,
        mainAxisSpacing: 12,
      ),
      itemCount: designs.length,
      itemBuilder: (context, i) {
        final d = designs[i];
        return GestureDetector(
          onTap: () => onOpen(d),
          onLongPress: () => _confirmDelete(context, ref, d),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    color: Shade.surface,
                    child: d.thumbnail == null
                        ? const Center(
                            child: Icon(Icons.image_outlined,
                                color: Shade.textFaint, size: 20))
                        : FutureBuilder<String>(
                            future: ref
                                .read(libraryControllerProvider.notifier)
                                .thumbnailPath(d.thumbnail!),
                            builder: (context, snap) {
                              if (!snap.hasData) return const SizedBox.shrink();
                              final file = File(snap.data!);
                              if (!file.existsSync()) {
                                return const Center(
                                    child: Icon(Icons.image_outlined,
                                        color: Shade.textFaint, size: 20));
                              }
                              return Image.file(file, fit: BoxFit.cover);
                            },
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  if (d.favorite) ...[
                    const Icon(Icons.star, size: 11, color: Shade.accent),
                    const SizedBox(width: 3),
                  ],
                  Expanded(
                    child: Text(d.place.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Shade.textDim, fontSize: 11.5)),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref, Design d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Shade.surface,
        title: const Text('Delete design?', style: TextStyle(color: Shade.text)),
        content: Text('"${d.place.name}" will be removed from your library.',
            style: const TextStyle(color: Shade.textDim)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel', style: TextStyle(color: Shade.textDim))),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete', style: TextStyle(color: Shade.danger))),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(libraryControllerProvider.notifier).delete(d.id);
    }
  }
}
