import 'dart:async';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/geo.dart';
import '../data/map_repository.dart';
import '../data/osm/overpass_query.dart';
import '../data/store/prefs_store.dart';
import '../model/design.dart';
import '../model/format_spec.dart';
import '../model/layer.dart';
import '../model/map_style.dart';
import '../model/place.dart';
import '../model/poster_config.dart';
import '../model/route_track.dart';
import '../model/terrain_relief.dart';
import '../presets/format_presets.dart';
import '../presets/style_presets.dart';
import '../render/path_cache.dart';
import '../render/poster_renderer.dart';
import 'providers.dart';

enum StudioStatus { empty, loading, ready, error }

enum ContourStatus { off, loading, ready, unavailable }

/// The undoable part of a design. Everything the user can change by hand
/// belongs here, including where the map is centred and how it is framed -
/// leaving either out makes undo restore a state that never existed.
class _Snapshot {
  final PlaceRef? place;
  final MapStyle style;
  final PosterConfig poster;
  final FormatSpec format;
  final double radiusMetres;
  final double zoom;
  final Offset pan;
  final RouteTrack? route;
  const _Snapshot(this.place, this.style, this.poster, this.format, this.radiusMetres,
      this.zoom, this.pan, this.route);
}

class StudioState {
  final String designId;
  final PlaceRef? place;
  final double radiusMetres;
  final StudioStatus status;
  final String statusMessage;
  final String? error;
  final MapPathCache? paths;
  final MapStyle style;
  final PosterConfig poster;
  final FormatSpec format;
  final RouteTrack? route;
  final double zoom;
  final Offset pan;
  final DetailLevel detail;
  final bool fromCache;
  final bool savedToLibrary;
  final bool canUndo;
  final bool canRedo;
  final ContourStatus contourStatus;
  final String? contourMessage;
  final TerrainRelief? relief;

  StudioState({
    required this.designId,
    required this.style,
    required this.poster,
    required this.format,
    this.place,
    this.radiusMetres = 1600,
    this.status = StudioStatus.empty,
    this.statusMessage = '',
    this.error,
    this.paths,
    this.route,
    this.zoom = 1.0,
    this.pan = Offset.zero,
    this.detail = DetailLevel.full,
    this.fromCache = false,
    this.savedToLibrary = false,
    this.canUndo = false,
    this.canRedo = false,
    this.contourStatus = ContourStatus.off,
    this.contourMessage,
    this.relief,
  });

  bool get hasArtwork => paths != null;

  late final PosterScene scene = PosterScene(
    paths: paths,
    style: style,
    poster: poster,
    format: format,
    route: route,
    place: place,
    relief: relief,
    zoom: zoom,
    pan: pan,
  );

  StudioState copyWith({
    String? designId,
    PlaceRef? place,
    double? radiusMetres,
    StudioStatus? status,
    String? statusMessage,
    String? error,
    bool clearError = false,
    MapPathCache? paths,
    MapStyle? style,
    PosterConfig? poster,
    FormatSpec? format,
    RouteTrack? route,
    bool clearRoute = false,
    double? zoom,
    Offset? pan,
    DetailLevel? detail,
    bool? fromCache,
    bool? savedToLibrary,
    bool? canUndo,
    bool? canRedo,
    ContourStatus? contourStatus,
    String? contourMessage,
    bool clearContourMessage = false,
    TerrainRelief? relief,
    bool clearRelief = false,
  }) =>
      StudioState(
        designId: designId ?? this.designId,
        place: place ?? this.place,
        radiusMetres: radiusMetres ?? this.radiusMetres,
        status: status ?? this.status,
        statusMessage: statusMessage ?? this.statusMessage,
        error: clearError ? null : (error ?? this.error),
        paths: paths ?? this.paths,
        style: style ?? this.style,
        poster: poster ?? this.poster,
        format: format ?? this.format,
        route: clearRoute ? null : (route ?? this.route),
        zoom: zoom ?? this.zoom,
        pan: pan ?? this.pan,
        detail: detail ?? this.detail,
        fromCache: fromCache ?? this.fromCache,
        savedToLibrary: savedToLibrary ?? this.savedToLibrary,
        canUndo: canUndo ?? this.canUndo,
        canRedo: canRedo ?? this.canRedo,
        contourStatus: contourStatus ?? this.contourStatus,
        contourMessage:
            clearContourMessage ? null : (contourMessage ?? this.contourMessage),
        relief: clearRelief ? null : (relief ?? this.relief),
      );
}

class StudioController extends StateNotifier<StudioState> {
  StudioController(this._repo, this._prefs)
      : super(StudioState(
          designId: _newId(),
          style: defaultStyle,
          poster: const PosterConfig(),
          format: kFormats.first,
        ));

  final MapRepository _repo;
  final PrefsStore _prefs;
  int _loadSeq = 0;
  int _contourSeq = 0;

  static const int _historyLimit = 40;
  final List<_Snapshot> _undo = [];
  final List<_Snapshot> _redo = [];
  String? _lastKind;
  DateTime _lastPush = DateTime.fromMillisecondsSinceEpoch(0);
  bool _restoring = false;

  static String _newId() =>
      'd${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';

  // ---------------------------------------------------------------- history

  _Snapshot get _current => _Snapshot(state.place, state.style, state.poster,
      state.format, state.radiusMetres, state.zoom, state.pan, state.route);

  /// Records the state before a change. Consecutive tweaks of the same control
  /// collapse into one entry so dragging a slider is a single undo.
  void _push(String kind) {
    if (_restoring) return;
    final now = DateTime.now();
    final sameGesture =
        kind == _lastKind && now.difference(_lastPush) < const Duration(milliseconds: 900);
    _lastKind = kind;
    _lastPush = now;
    if (sameGesture && _undo.isNotEmpty) return;
    _undo.add(_current);
    if (_undo.length > _historyLimit) _undo.removeAt(0);
    _redo.clear();
  }

  void _apply(_Snapshot s) {
    _restoring = true;
    final movedTo = s.place;
    final needsReload = s.radiusMetres != state.radiusMetres ||
        movedTo?.centre.lat != state.place?.centre.lat ||
        movedTo?.centre.lon != state.place?.centre.lon;
    state = state.copyWith(
      place: s.place,
      style: s.style,
      poster: s.poster,
      format: s.format,
      radiusMetres: s.radiusMetres,
      zoom: s.zoom,
      pan: s.pan,
      route: s.route,
      clearRoute: s.route == null,
      savedToLibrary: false,
      canUndo: _undo.isNotEmpty,
      canRedo: _redo.isNotEmpty,
    );
    _restoring = false;
    _lastKind = null;
    if (needsReload) _load();
  }

  void undo() {
    if (_undo.isEmpty) return;
    _redo.add(_current);
    _apply(_undo.removeLast());
  }

  void redo() {
    if (_redo.isEmpty) return;
    _undo.add(_current);
    _apply(_redo.removeLast());
  }

  void _clearHistory() {
    _undo.clear();
    _redo.clear();
    _lastKind = null;
  }

  // ------------------------------------------------------------------ place

  Future<void> openPlace(PlaceRef place, {double? radius}) async {
    _clearHistory();
    state = StudioState(
      designId: _newId(),
      place: place,
      radiusMetres: radius ?? state.radiusMetres,
      style: state.style,
      poster: state.poster.copyWith(title: '', subtitle: '', custom: ''),
      format: state.format,
      status: StudioStatus.loading,
      statusMessage: 'Preparing...',
    );
    await _load();
  }

  /// Moves the studio to a new place without throwing away the look the user
  /// has built up. This is what the search button in the studio calls.
  Future<void> recentre(PlaceRef place) async {
    _push('place');
    state = state.copyWith(
      place: place,
      poster: state.poster.copyWith(title: '', subtitle: ''),
      zoom: 1.0,
      pan: Offset.zero,
      savedToLibrary: false,
      canUndo: _undo.isNotEmpty,
      canRedo: false,
      contourStatus: ContourStatus.off,
      clearContourMessage: true,
    );
    await _load();
  }

  Future<void> reload({bool force = false}) => _load(force: force);

  Future<void> _load({bool force = false}) async {
    final place = state.place;
    if (place == null) return;
    final id = ++_loadSeq;
    state = state.copyWith(
      status: StudioStatus.loading,
      statusMessage: 'Preparing...',
      clearError: true,
    );
    try {
      final result = await _repo.load(
        centre: place.centre,
        radiusMetres: state.radiusMetres,
        forceRefresh: force,
        onStatus: (msg) {
          if (mounted && id == _loadSeq) {
            state = state.copyWith(statusMessage: msg);
          }
        },
      );
      if (!mounted || id != _loadSeq) return;
      state.paths?.dispose();
      state.relief?.dispose();
      state = state.copyWith(
        paths: MapPathCache(result.data),
        clearRelief: true,
        status: StudioStatus.ready,
        statusMessage: '',
        detail: result.detail,
        fromCache: result.fromCache,
        contourStatus: ContourStatus.off,
        clearError: true,
      );
      if (state.style.wantsContours) unawaited(ensureContours());
    } catch (e) {
      if (!mounted || id != _loadSeq) return;
      state = state.copyWith(
        status: state.hasArtwork ? StudioStatus.ready : StudioStatus.error,
        error: '$e',
        statusMessage: '',
      );
    }
  }

  void setRadius(double metres) {
    _push('radius');
    state = state.copyWith(
      radiusMetres: metres.clamp(250.0, 20000.0),
      canUndo: _undo.isNotEmpty,
      canRedo: _redo.isNotEmpty,
    );
  }

  Future<void> commitRadius() => _load();

  // --------------------------------------------------------------- contours

  /// Downloads elevation tiles and traces contour lines for the current view.
  Future<void> ensureContours() async {
    final paths = state.paths;
    if (paths == null) return;
    if (paths.data.hasContours && state.relief != null) {
      state = state.copyWith(contourStatus: ContourStatus.ready);
      return;
    }
    final id = ++_contourSeq;
    state = state.copyWith(contourStatus: ContourStatus.loading, clearContourMessage: true);
    try {
      final result = await _repo.withContours(
        paths.data,
        interval: state.style.contourInterval > 0 ? state.style.contourInterval : 10,
        onStatus: (msg) {
          if (mounted && id == _contourSeq) state = state.copyWith(statusMessage: msg);
        },
      );
      if (!mounted || id != _contourSeq) {
        result.relief?.dispose();
        return;
      }
      if (!identical(result.data, paths.data)) paths.dispose();
      state = state.copyWith(
        paths: MapPathCache(result.data),
        relief: result.relief,
        contourStatus:
            result.data.hasContours ? ContourStatus.ready : ContourStatus.unavailable,
        statusMessage: '',
      );
    } catch (e) {
      if (!mounted || id != _contourSeq) return;
      state = state.copyWith(
        contourStatus: ContourStatus.unavailable,
        contourMessage: '$e',
        statusMessage: '',
      );
    }
  }

  void setContours(bool on) {
    _push('contours');
    final style = state.style.copyWith(contourInterval: on ? 10 : 0);
    state = state.copyWith(
      style: style,
      savedToLibrary: false,
      canUndo: _undo.isNotEmpty,
      canRedo: _redo.isNotEmpty,
      contourStatus: on ? state.contourStatus : ContourStatus.off,
    );
    if (on) unawaited(ensureContours());
  }

  /// Hillshading needs the same elevation download contours do, so turning it
  /// on fetches terrain if it is not already there.
  void setRelief(bool on) {
    _push('relief');
    state = state.copyWith(
      style: state.style.copyWith(reliefStrength: on ? 0.55 : 0),
      savedToLibrary: false,
      canUndo: _undo.isNotEmpty,
      canRedo: _redo.isNotEmpty,
    );
    if (on && state.relief == null) unawaited(ensureContours());
  }

  // ------------------------------------------------------------------ style

  void applyPreset(MapStyle preset) {
    _push('preset');
    state = state.copyWith(
      style: preset,
      savedToLibrary: false,
      canUndo: _undo.isNotEmpty,
      canRedo: _redo.isNotEmpty,
    );
    _prefs.setLastStyleId(preset.id);
    if (preset.wantsContours) unawaited(ensureContours());
  }

  void updateStyle(MapStyle style, {String kind = 'style'}) {
    _push(kind);
    state = state.copyWith(
      style: style,
      savedToLibrary: false,
      canUndo: _undo.isNotEmpty,
      canRedo: _redo.isNotEmpty,
    );
  }

  void updateLayer(LayerId id, LayerStyle layer) => updateStyle(
        state.style.withLayer(id, layer).copyWith(id: 'custom', name: 'Custom'),
        kind: 'layer:${id.index}',
      );

  void setLineScale(double v) =>
      updateStyle(state.style.copyWith(lineScale: v), kind: 'lineScale');

  // ----------------------------------------------------------------- poster

  void updatePoster(PosterConfig poster, {String kind = 'poster'}) {
    _push(kind);
    state = state.copyWith(
      poster: poster,
      savedToLibrary: false,
      canUndo: _undo.isNotEmpty,
      canRedo: _redo.isNotEmpty,
    );
  }

  /// Picking a phone format switches the poster into wallpaper mode (edge to
  /// edge, text over the map); picking a print format switches it back.
  void setFormat(FormatSpec format) {
    _push('format');
    final wallpaper = format.id == 'phone';
    var poster = state.poster;
    if (wallpaper && poster.shape != ShapeMask.fill) {
      poster = poster.copyWith(
        shape: ShapeMask.fill,
        margin: 0,
        placement: poster.placement == TextPlacement.below
            ? TextPlacement.overlayBottom
            : poster.placement,
      );
    } else if (!wallpaper && poster.shape == ShapeMask.fill && poster.margin == 0) {
      poster = poster.copyWith(
        shape: ShapeMask.rectangle,
        margin: 0.075,
        placement: poster.placement == TextPlacement.overlayBottom
            ? TextPlacement.below
            : poster.placement,
      );
    }
    state = state.copyWith(
      format: format,
      poster: poster,
      savedToLibrary: false,
      canUndo: _undo.isNotEmpty,
      canRedo: _redo.isNotEmpty,
    );
    _prefs.setLastFormatId(format.id);
  }

  // ------------------------------------------------------------- view/zoom

  /// How far the view may drift before it would run past the captured data.
  static double _panLimit(double zoom) =>
      (((1 - 1 / zoom) / 2) + 0.08).clamp(0.0, 0.6);

  void setZoom(double zoom) {
    final next = zoom.clamp(0.6, 4.0);
    final limit = _panLimit(next);
    state = state.copyWith(
      zoom: next,
      pan: Offset(state.pan.dx.clamp(-limit, limit), state.pan.dy.clamp(-limit, limit)),
    );
  }

  void setPan(Offset pan) {
    final limit = _panLimit(state.zoom);
    state = state.copyWith(
      pan: Offset(pan.dx.clamp(-limit, limit), pan.dy.clamp(-limit, limit)),
    );
  }

  /// Called once when a pan/zoom gesture starts. Without this the view is in
  /// the snapshot but never recorded, so undoing an unrelated colour change
  /// would silently throw away the framing the user just set up.
  void beginViewChange() => _push('view');

  void resetView() {
    _push('view');
    state = state.copyWith(zoom: 1.0, pan: Offset.zero, canUndo: _undo.isNotEmpty);
  }

  // ------------------------------------------------------------------ route

  Future<void> attachRoute(RouteTrack route, {bool refit = true}) async {
    state = state.copyWith(route: route, savedToLibrary: false);
    if (!refit) return;
    final centre = route.centre;
    final radius = route.suggestedRadius;
    final place = state.place ??
        PlaceRef(name: route.name, context: '', country: '', centre: centre);
    state = state.copyWith(
      place: PlaceRef(
        name: place.name.isEmpty ? route.name : place.name,
        context: place.context,
        country: place.country,
        centre: centre,
      ),
      radiusMetres: radius,
      zoom: 1.0,
      pan: Offset.zero,
    );
    await _load();
  }

  void detachRoute() {
    _push('route');
    state = state.copyWith(
      clearRoute: true,
      savedToLibrary: false,
      canUndo: _undo.isNotEmpty,
    );
  }

  // ---------------------------------------------------------------- library

  Design toDesign() => Design(
        id: state.designId,
        place: state.place ??
            const PlaceRef(
                name: 'Untitled', context: '', country: '', centre: LatLng(0, 0)),
        radiusMetres: state.radiusMetres,
        style: state.style,
        poster: state.poster,
        formatId: state.format.id,
        route: state.route,
        zoom: state.zoom,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

  Future<void> loadDesign(Design design) async {
    _clearHistory();
    state = StudioState(
      designId: design.id,
      place: design.place,
      radiusMetres: design.radiusMetres,
      style: design.style,
      poster: design.poster,
      format: formatById(design.formatId),
      route: design.route,
      zoom: design.zoom,
      status: StudioStatus.loading,
      statusMessage: 'Preparing...',
      savedToLibrary: true,
    );
    await _load();
  }

  void markSaved() => state = state.copyWith(savedToLibrary: true);

  @override
  void dispose() {
    state.paths?.dispose();
    state.relief?.dispose();
    super.dispose();
  }
}

final studioControllerProvider =
    StateNotifierProvider<StudioController, StudioState>((ref) => StudioController(
          ref.watch(mapRepositoryProvider),
          ref.watch(prefsStoreProvider),
        ));
