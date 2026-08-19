import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/format.dart';
import '../../core/geo.dart';
import '../../core/strings.dart';
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
  bool _locating = false;

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _open(PlaceRef place) async {
    _focus.unfocus();
    await ref.read(searchControllerProvider.notifier).remember(place);
    unawaited(ref.read(studioControllerProvider.notifier).openPlace(place));
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const StudioScreen()),
    );
    if (mounted) unawaited(ref.read(libraryControllerProvider.notifier).refresh());
  }

  Future<void> _openDesign(Design design) async {
    _focus.unfocus();
    unawaited(ref.read(studioControllerProvider.notifier).loadDesign(design));
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const StudioScreen()),
    );
    if (mounted) unawaited(ref.read(libraryControllerProvider.notifier).refresh());
  }

  Future<void> _useMyLocation() async {
    final s = ref.read(stringsProvider);
    setState(() => _locating = true);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _toast(s.locationDenied);
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
      );
      final here = LatLng(position.latitude, position.longitude);
      final resolved = await ref.read(nominatimProvider).reverse(here);
      final place = resolved ??
          PlaceRef(
            name: s.useMyLocation,
            context: formatDecimal(here),
            country: '',
            centre: here,
          );
      await _open(PlaceRef(
        name: place.name,
        context: place.context,
        country: place.country,
        centre: here,
      ));
    } catch (_) {
      _toast(s.locationUnavailable);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
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
      if (mounted) unawaited(ref.read(libraryControllerProvider.notifier).refresh());
    } catch (e) {
      _toast('GPX: $e');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final search = ref.watch(searchControllerProvider);
    final showResults = search.query.trim().length >= 2;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _header(s),
            _searchField(s, search.loading),
            Expanded(
              child: showResults ? _results(s, search) : _browse(s, search.recent),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(S s) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 18, 18, 14),
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
                  s.tagline,
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
            tooltip: s.importRoute,
            busy: _importing,
            onTap: _importing ? null : _importGpx,
          ),
          const SizedBox(width: 10),
          _RoundAction(
            icon: Icons.tune,
            tooltip: s.openSettings,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _searchField(S s, bool loading) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focus,
              textInputAction: TextInputAction.search,
              style: const TextStyle(color: Shade.text, fontSize: 15),
              onChanged: ref.read(searchControllerProvider.notifier).onQueryChanged,
              onSubmitted: (_) =>
                  unawaited(ref.read(searchControllerProvider.notifier).submit()),
              decoration: InputDecoration(
                hintText: s.searchHint,
                prefixIcon: const Icon(Icons.search, color: Shade.textFaint, size: 20),
                suffixIcon: loading
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Shade.accent,
                          ),
                        ),
                      )
                    : (_controller.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close,
                                size: 18, color: Shade.textFaint),
                            onPressed: () {
                              _controller.clear();
                              ref.read(searchControllerProvider.notifier).clear();
                              setState(() {});
                            },
                          )),
              ),
            ),
          ),
          const SizedBox(width: 10),
          _RoundAction(
            icon: Icons.my_location,
            tooltip: s.useMyLocation,
            busy: _locating,
            onTap: _locating ? null : _useMyLocation,
          ),
        ],
      ),
    );
  }

  Widget _results(S s, SearchState search) {
    if (search.results.isEmpty && !search.loading) {
      return EmptyHint(
        icon: Icons.travel_explore_outlined,
        title: search.error ?? s.nothingFound,
        body: s.tryAnotherSpelling,
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

  Widget _browse(S s, List<PlaceRef> recent) {
    final library = ref.watch(libraryControllerProvider);
    return ListView(
      padding: const EdgeInsets.only(bottom: 44),
      children: [
        if (recent.isNotEmpty) ...[
          SectionLabel(s.recent),
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
                  child: Text(
                    recent[i].name,
                    style: const TextStyle(color: Shade.text, fontSize: 13.5),
                  ),
                ),
              ),
            ),
          ),
        ],
        SectionLabel(s.startWithPlace),
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
        SectionLabel(
          s.yourLibrary,
          trailing: library.designs.isEmpty ? null : _librarySort(s, library),
        ),
        if (library.designs.isNotEmpty) _libraryFilters(s, library),
        if (library.loading)
          const Padding(
            padding: EdgeInsets.all(28),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Shade.accent),
              ),
            ),
          )
        else if (library.designs.isEmpty)
          EmptyHint(
            icon: Icons.bookmark_border,
            title: s.nothingSaved,
            body: s.nothingSavedBody,
          )
        else if (library.visible.isEmpty)
          EmptyHint(
            icon: Icons.star_border,
            title: s.noFavourites,
            body: s.noFavouritesBody,
          )
        else
          _LibraryGrid(
            state: library,
            onOpen: _openDesign,
            onMenu: (d) => _designMenu(s, d),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
          child: Text(
            s.attributionLine,
            style: const TextStyle(color: Shade.textFaint, fontSize: 11, height: 1.5),
          ),
        ),
      ],
    );
  }

  Widget _libraryFilters(S s, LibraryState library) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: Row(
        children: [
          _FilterChip(
            label: s.all,
            selected: !library.favouritesOnly,
            onTap: () =>
                ref.read(libraryControllerProvider.notifier).setFavouritesOnly(false),
          ),
          const SizedBox(width: 8),
          _FilterChip(
            label: '${s.favouritesOnly} (${library.favouriteCount})',
            selected: library.favouritesOnly,
            onTap: () =>
                ref.read(libraryControllerProvider.notifier).setFavouritesOnly(true),
          ),
        ],
      ),
    );
  }

  Widget _librarySort(S s, LibraryState library) {
    return PopupMenuButton<LibrarySort>(
      color: Shade.surface,
      tooltip: s.sortRecent,
      initialValue: library.sort,
      onSelected: ref.read(libraryControllerProvider.notifier).setSort,
      itemBuilder: (_) => [
        PopupMenuItem(value: LibrarySort.recent, child: Text(s.sortRecent)),
        PopupMenuItem(value: LibrarySort.oldest, child: Text(s.sortOldest)),
        PopupMenuItem(value: LibrarySort.name, child: Text(s.sortName)),
      ],
      child: const Icon(Icons.sort, size: 18, color: Shade.textDim),
    );
  }

  Future<void> _designMenu(S s, Design design) async {
    final controller = ref.read(libraryControllerProvider.notifier);
    final name = LibraryState.displayName(design);
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Shade.bgAlt,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
              child: Text(
                name,
                style: const TextStyle(
                  color: Shade.text,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ListTile(
              leading: Icon(design.favorite ? Icons.star : Icons.star_border,
                  color: Shade.accent),
              title: Text(design.favorite ? s.removeFavourite : s.addFavourite,
                  style: const TextStyle(color: Shade.text)),
              onTap: () => Navigator.pop(context, 'fav'),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined, color: Shade.text),
              title: Text(s.rename, style: const TextStyle(color: Shade.text)),
              onTap: () => Navigator.pop(context, 'rename'),
            ),
            ListTile(
              leading: const Icon(Icons.copy_all_outlined, color: Shade.text),
              title: Text(s.duplicate, style: const TextStyle(color: Shade.text)),
              onTap: () => Navigator.pop(context, 'duplicate'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Shade.danger),
              title: Text(s.delete, style: const TextStyle(color: Shade.danger)),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;

    switch (action) {
      case 'fav':
        await controller.toggleFavorite(design.id);
      case 'duplicate':
        await controller.duplicate(design.id);
      case 'rename':
        final next = await _askName(s, name);
        if (next != null && next.trim().isNotEmpty) {
          await controller.rename(design.id, next);
        }
      case 'delete':
        final ok = await _confirmDelete(s, name);
        if (ok) await controller.delete(design.id);
    }
  }

  Future<String?> _askName(S s, String current) {
    final controller = TextEditingController(text: current);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Shade.surface,
        title: Text(s.renameTitle, style: const TextStyle(color: Shade.text)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Shade.text),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(s.cancel, style: const TextStyle(color: Shade.textDim)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text(s.save, style: const TextStyle(color: Shade.accent)),
          ),
        ],
      ),
    );
  }

  Future<bool> _confirmDelete(S s, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Shade.surface,
        title: Text(s.deleteDesignTitle(name),
            style: const TextStyle(color: Shade.text)),
        content: Text(s.deleteDesignBody,
            style: const TextStyle(color: Shade.textDim)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(s.cancel, style: const TextStyle(color: Shade.textDim)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(s.delete, style: const TextStyle(color: Shade.danger)),
          ),
        ],
      ),
    );
    return ok ?? false;
  }
}

void unawaited(Future<void> future) {
  future.catchError((Object _) {});
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({
    required this.icon,
    required this.tooltip,
    this.onTap,
    this.busy = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        child: GestureDetector(
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
                    child: CircularProgressIndicator(strokeWidth: 2, color: Shade.accent),
                  )
                : Icon(icon, size: 21, color: Shade.text),
          ),
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? Shade.accent : Shade.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? Shade.accent : Shade.line),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? const Color(0xFF14100A) : Shade.textDim,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
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
                  Text(
                    place.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Shade.text,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (place.context.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        place.context,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Shade.textFaint, fontSize: 12),
                      ),
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
            Text(
              place.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Shade.text,
                fontSize: 16.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              place.country,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Shade.textFaint, fontSize: 11.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _LibraryGrid extends StatelessWidget {
  const _LibraryGrid({
    required this.state,
    required this.onOpen,
    required this.onMenu,
  });

  final LibraryState state;
  final ValueChanged<Design> onOpen;
  final ValueChanged<Design> onMenu;

  @override
  Widget build(BuildContext context) {
    final designs = state.visible;
    final ratio = MediaQuery.of(context).devicePixelRatio;
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
        final path = state.thumbPathOf(d);
        return Semantics(
          button: true,
          label: LibraryState.displayName(d),
          child: GestureDetector(
            onTap: () => onOpen(d),
            onLongPress: () => onMenu(d),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: ColoredBox(
                      color: Shade.surface,
                      child: path == null
                          ? const Center(
                              child: Icon(Icons.image_outlined,
                                  color: Shade.textFaint, size: 20),
                            )
                          : Image.file(
                              File(path),
                              fit: BoxFit.cover,
                              width: double.infinity,
                              // Decode at roughly the size actually shown.
                              cacheWidth: (140 * ratio).round(),
                              errorBuilder: (_, __, ___) => const Center(
                                child: Icon(Icons.image_outlined,
                                    color: Shade.textFaint, size: 20),
                              ),
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
                      child: Text(
                        LibraryState.displayName(d),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Shade.textDim, fontSize: 11.5),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
